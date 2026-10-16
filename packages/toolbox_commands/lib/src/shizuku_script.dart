import 'package:toolbox_core/toolbox_core.dart';

/// 对应 TS 版 src/main/ops/shizuku.ts 里发到手机上的部分。

/// 开机自启用它打开无线调试，需要 Shizuku 拿到这个权限
const writeSecureSettings = 'android.permission.WRITE_SECURE_SETTINGS';

/// Shizuku 的开机广播接收器
const bootReceiverComponent = 'moe.shizuku.manager.receiver.BootCompleteReceiver';

/// 探测输出里分隔「脚本自己的输出」与「dumpsys 原始输出」的标记
const dumpsysMarker = 'DUMPSYS|';

/// Shizuku 的官方安装包信息（下载地址、sha256、版本）。
/// 业务层的入口函数也叫 shizuku，会遮住目录里的同名常量，这里换一个名字转出去。
const shizukuRelease = shizuku;

/// Shizuku 用 adb 启动后，以 shell 身份常驻（进程名 shizuku_server），其它应用通过它调用系统 API。
/// 免 Root 的启动方式每次重启手机都要重新执行一次。
///
/// 13.x 起官方给出的命令是直接运行应用原生库目录里的 libshizuku.so；
/// 旧版本、或原生库没有解压出来时，退回打开过一次应用后写在 Android/data 下的 start.sh。
/// 装了 Shizuku 时，[dumpsysMarker] 之后是 dumpsys package 的完整输出（版本、权限、被关掉的组件都从这里读）。
///
/// 与 TS 版逐字一致，改动前请先对照 src/main/ops/shizuku.ts 的 PROBE。
final String shizukuProbeScript = [
  'P=${shizuku.package}',
  r'echo "SDK|$(getprop ro.build.version.sdk)"',
  r'pid=$(pidof shizuku_server)',
  r'[ -n "$pid" ] && echo "RUNNING|$pid"',
  r"apk=$(pm path $P 2>/dev/null | head -n 1 | sed 's/^package://')",
  r'if [ -n "$apk" ]; then',
  r'  d=${apk%/*}',
  r'  for f in $d/lib/arm64/libshizuku.so $d/lib/*/libshizuku.so /sdcard/Android/data/$P/start.sh; do',
  r'    [ -f "$f" ] && { echo "STARTER|$f"; break; }',
  r'  done',
  r'  echo "DUMPSYS|"',
  r'  dumpsys package $P',
  r'fi',
  'true',
].join('\n');

/// 探测结果：比 [ShizukuState] 多一个启动程序的路径
class ShizukuProbe extends ShizukuState {
  const ShizukuProbe({
    required super.installed,
    super.version,
    required super.running,
    super.sdk,
    super.secureSettings,
    super.bootReceiver,
    this.starter,
  });

  /// libshizuku.so 或 start.sh 的路径
  final String? starter;
}

/// dumpsys package 里 `disabledComponents:` 段列出的组件
Set<String> _disabledComponents(String dump) {
  final out = <String>{};
  var indent = -1;
  for (final line in dump.split(RegExp(r'\r?\n'))) {
    final depth = line.length - line.trimLeft().length;
    if (line.trim() == 'disabledComponents:') {
      indent = depth;
    } else if (indent >= 0 && line.trim().isNotEmpty && depth > indent) {
      out.add(line.trim());
    } else {
      indent = -1;
    }
  }
  return out;
}

final _sdkValue = RegExp(r'^\d+$');
final _versionName = RegExp(r'versionName=(\S+)');

/// 解析 [shizukuProbeScript] 的输出
ShizukuProbe parseShizukuProbe(String out) {
  var installed = false;
  String? version;
  var running = false;
  int? sdk;
  String? starter;
  bool? secureSettings;
  bool? bootReceiver;

  final at = out.indexOf(dumpsysMarker);
  final head = at >= 0 ? out.substring(0, at) : out;
  for (final line in head.split(RegExp(r'\r?\n'))) {
    final parts = line.trim().split('|');
    final kind = parts.first;
    final value = parts.skip(1).join('|').trim();
    if (kind == 'SDK' && _sdkValue.hasMatch(value)) {
      sdk = int.parse(value);
    } else if (kind == 'STARTER' && value.isNotEmpty) {
      starter = value;
    } else if (kind == 'RUNNING' && value.isNotEmpty) {
      running = true;
    }
  }
  if (at >= 0) {
    final dump = out.substring(at + dumpsysMarker.length);
    installed = true;
    version = _versionName.firstMatch(dump)?.group(1);
    secureSettings = parsePackagePermissions(dump).granted.contains(writeSecureSettings);
    bootReceiver = !_disabledComponents(dump).contains(bootReceiverComponent);
  }
  return ShizukuProbe(
    installed: installed,
    version: version,
    running: running,
    sdk: sdk,
    secureSettings: secureSettings,
    bootReceiver: bootReceiver,
    starter: starter,
  );
}

/// 启动 Shizuku 时交给 `adb shell` 的参数：start.sh 要用 sh 跑，原生库直接执行
List<String> starterCommand(String starter) => starter.endsWith('.sh') ? ['sh', starter] : [starter];
