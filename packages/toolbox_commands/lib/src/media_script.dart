import 'package:toolbox_core/toolbox_core.dart';

import 'adb.dart';
import 'patch_script.dart';

/// 对应 TS 版 src/main/ops/media.ts（投屏 / 截图 / 文件传输）。

/// 手机上可以浏览的根目录；不允许跳出内置存储
const remoteRoot = '/sdcard';

/// 规范化手机端路径，只接受 /sdcard 下的绝对路径
String remotePath(String input) {
  final parts = <String>[];
  for (final seg in input.replaceAll(r'\', '/').split('/')) {
    if (seg.isEmpty || seg == '.') continue;
    if (seg == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else {
      parts.add(seg);
    }
  }
  final out = '/${parts.join('/')}';
  if (out != remoteRoot && !out.startsWith('$remoteRoot/')) {
    throw const PathOutsideStorageException('只能访问手机内置存储（/sdcard）');
  }
  return out;
}

/// 路径不在 /sdcard 内。业务层收到后转成用户可见的 [OpException] 文案。
class PathOutsideStorageException implements Exception {
  const PathOutsideStorageException(this.message);

  final String message;

  @override
  String toString() => message;
}

// ───────────── 截图 ─────────────

/// 在手机上截图到 [remoteDir]/screen.png 并拉回 [local]。
/// 先拉到临时目录（adb 对中文路径支持不好），再由业务层移到「文档\一加工具箱\截图」
Future<bool> captureScreenshot(Adb adb, String serial, String local) async {
  final shot = '$remoteDir/screen.png';
  await adb.shell(serial, ['mkdir -p $remoteDir && screencap -p $shot'], timeout: const Duration(seconds: 30));
  final r = await adb.pull(serial, shot, local, timeout: const Duration(seconds: 60));
  await adb.shell(serial, ['rm', '-f', shot]);
  return r.code == 0;
}

// ───────────── 文件传输 ─────────────

/// 列出 [remoteDir] 之外任意目录时用的手机端脚本。
/// stat 跟随符号链接（-L），/sdcard 本身就是链接
String listRemoteScript(String dir) =>
    'find ${shq(dir)}/ -mindepth 1 -maxdepth 1 -exec stat -L -c \'%F|%s|%Y|%n\' {} + 2>/dev/null';

/// 解析 `stat -c '%F|%s|%Y|%n'` 的输出
List<RemoteEntry> parseStat(String out) {
  final list = <RemoteEntry>[];
  for (final line in out.split(RegExp(r'\r?\n'))) {
    final m = RegExp(r'^([^|]+)\|(\d+)\|(\d+)\|(.+)$').firstMatch(line);
    if (m == null) continue;
    final name = m[4]!.split('/').last;
    if (name == '.' || name == '..') continue;
    list.add(RemoteEntry(
      name: name,
      dir: RegExp('directory', caseSensitive: false).hasMatch(m[1]!),
      size: int.parse(m[2]!),
      mtime: int.parse(m[3]!) * 1000,
    ));
  }
  list.sort((a, b) {
    if (a.dir != b.dir) return a.dir ? -1 : 1;
    return a.name.compareTo(b.name);
  });
  return list;
}

/// 列出手机目录下的一项。失败且没有任何输出时返回 null，由业务层决定提示文案
Future<List<RemoteEntry>?> listRemoteEntries(Adb adb, String serial, String dir) async {
  final r = await adb.shell(serial, [listRemoteScript(dir)], timeout: const Duration(seconds: 60), echoOutput: false);
  if (r.code != 0 && r.stdout.trim().isEmpty) return null;
  return parseStat(r.stdout);
}

/// 推送一个文件；失败返回 false（源文件是否存在由业务层判断）
Future<bool> pushFile(Adb adb, String serial, String local, String remote) async {
  final r = await adb.push(serial, local, remote, timeout: const Duration(minutes: 30));
  return r.code == 0;
}

/// 拉取手机上的一个文件到本地临时文件
Future<bool> pullFileTo(Adb adb, String serial, String remote, String local) async {
  final r = await adb.pull(serial, remote, local, timeout: const Duration(minutes: 30));
  return r.code == 0;
}

// ───────────── 投屏 ─────────────

/// scrcpy 参数。独立屏幕用 --new-display 在手机上建一块虚拟屏幕（Android 10+），
/// 一加 13（ColorOS 16）上实测：不指定应用时显示系统的副屏桌面；指定的应用已在后台时会被移到虚拟屏，
/// 手机屏幕不受影响；手机锁屏后虚拟屏照常运行
List<String> mirrorArgs(MirrorOptions opts, String title) {
  final vd = opts.display;
  final List<String> args;
  if (vd == null) {
    args = [
      '--window-title',
      title,
      if (opts.turnScreenOff) '--turn-screen-off',
      if (opts.stayAwake) '--stay-awake',
    ];
  } else {
    final app = vd.app;
    if (app != null && !RegExp(r'^[\w.]+$').hasMatch(app)) {
      throw const InvalidMirrorOptionsException('包名不合法');
    }
    final arg = vd.size.arg;
    // 软键盘弹在虚拟屏上，不打扰手机屏幕；手机屏幕要留给用户用，不关屏也不保持亮屏（锁屏不影响虚拟屏）
    args = [
      '--window-title',
      '$title（独立屏幕）',
      arg != null ? '--new-display=$arg' : '--new-display',
      '--display-ime-policy=local',
      if (app != null && app.isNotEmpty) '--start-app=$app',
      if (vd.keepApp) '--no-vd-destroy-content',
      if (vd.audioOnPhone) '--no-audio',
    ];
  }
  if (opts.alwaysOnTop) args.add('--always-on-top');
  return args;
}

/// 投屏参数不合法。业务层收到后转成用户可见的 [OpException] 文案。
class InvalidMirrorOptionsException implements Exception {
  const InvalidMirrorOptionsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 传给 scrcpy 的完整参数：`-s <serial> …`，供业务层核对与写日志
List<String> mirrorCommandArgs(String serial, MirrorOptions opts, String title) => [
      '-s',
      serial,
      ...mirrorArgs(opts, title),
    ];
