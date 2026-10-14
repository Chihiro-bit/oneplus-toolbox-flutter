import 'dart:convert';
import 'dart:typed_data';

import 'adb.dart';
import 'patch_script.dart';

/// 手机上一个第三方应用的原始信息
class RawApp {
  const RawApp({required this.package, required this.label, this.apkPath, this.iconPath});

  final String package;
  final String label;
  final String? apkPath;

  /// APK 内的图标位图路径（自适应图标是 XML，无法直接显示，不会出现在这里）
  final String? iconPath;
}

class AppListing {
  const AppListing(this.apps, this.clonedPackages);

  final List<RawApp> apps;

  /// 已安装到指定用户（双开空间）中的包名
  final Set<String> clonedPackages;
}

/// 生成列出第三方应用的手机端脚本。
/// 应用名用手机端的 aapt2 读取，整个循环在一次 adb shell 里完成，避免每个应用一次 adb 往返。
/// 每个应用一个子 shell，8 个一批并行跑 aapt2（串行时 200 个应用要两分多钟）。
/// 图标路径也来自同一次 badging 输出，不增加耗时。
String appListScript(String aapt2Remote, String cloneUser) {
  String field(String prefix) => '\$(echo "\$b" | grep "^$prefix:" | head -n 1 | sed "s/^[^:]*:\'\\(.*\\)\'\$/\\1/")';
  return [
    'A=$aapt2Remote',
    r'chmod 755 $A',
    'i=0',
    r'for p in $(pm list packages -3 | sed "s/package://"); do',
    '  (',
    r'    path=$(pm path "$p" | head -n 1 | sed "s/package://")',
    r'    b=$($A d badging "$path" 2>/dev/null | grep -E "^application-(label(-zh-CN)?|icon-(160|240|320|480)):")',
    '    l=${field('application-label-zh-CN')}',
    '    [ -z "\$l" ] && l=${field('application-label')}',
    '    ic=""',
    '    for d in 240 320 160 480; do',
    '      c=${field(r'application-icon-$d')}',
    r'      case "$c" in *.png|*.webp|*.jpg) ic=$c; break;; esac',
    '    done',
    r'    echo "APP|$p|$path|$ic|$l"',
    '  ) &',
    r'  i=$((i + 1)); [ $((i % 8)) -eq 0 ] && wait',
    'done',
    'wait',
    'for p in \$(pm list packages -3 --user $cloneUser | sed "s/package://"); do echo "CLONED|\$p"; done',
  ].join('\n');
}

/// 解析 [appListScript] 的输出
AppListing parseAppListing(String out) {
  final apps = <RawApp>[];
  final cloned = <String>{};
  for (final line in const LineSplitter().convert(out)) {
    final parts = line.split('|');
    if (parts.length < 2) continue;
    final pkg = parts[1].trim();
    if (pkg.isEmpty) continue;
    if (parts[0] == 'CLONED') cloned.add(pkg);
    if (parts[0] == 'APP' && parts.length >= 5) {
      final apk = parts[2].trim();
      final icon = parts[3].trim();
      final label = parts.sublist(4).join('|').trim();
      apps.add(RawApp(
        package: pkg,
        label: label.isEmpty ? pkg : label,
        apkPath: apk.isEmpty ? null : apk,
        iconPath: icon.isEmpty ? null : icon,
      ));
    }
  }
  return AppListing(apps, cloned);
}

/// 列出第三方应用：推送 aapt2 到手机，运行 [appListScript]
Future<AppListing> listThirdPartyApps(Adb adb, String serial,
    {required String aapt2Local, required String cloneUser}) async {
  await adb.shell(serial, ['mkdir', '-p', remoteDir]);
  await adb.push(serial, aapt2Local, '$remoteDir/aapt2', timeout: const Duration(seconds: 60));
  final r = await adb.shell(serial, [appListScript('$remoteDir/aapt2', cloneUser)],
      timeout: const Duration(minutes: 5), echoOutput: false);
  return parseAppListing(r.stdout);
}

/// 一次 adb shell 从多个 APK 中解出图标位图。返回 包名 → 图片字节；失败的条目直接缺省。
Future<Map<String, Uint8List>> readIcons(
    Adb adb, String serial, Map<String, ({String apk, String icon})> sources) async {
  if (sources.isEmpty) return {};
  final script = sources.entries
      .map(
          (e) => 'echo "ICON|${e.key}|\$(unzip -p ${shq(e.value.apk)} ${shq(e.value.icon)} 2>/dev/null | base64 -w 0)"')
      .join('\n');
  final r = await adb.shell(serial, [script], echoOutput: false);
  final icons = <String, Uint8List>{};
  for (final line in const LineSplitter().convert(r.stdout)) {
    final parts = line.split('|');
    if (parts.length != 3 || parts[0] != 'ICON' || !sources.containsKey(parts[1])) continue;
    final b64 = parts[2].trim();
    if (b64.isEmpty) continue;
    try {
      icons[parts[1]] = base64Decode(b64);
    } on FormatException {
      // 截断的输出，跳过
    }
  }
  return icons;
}
