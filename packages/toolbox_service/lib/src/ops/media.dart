import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:toolbox_commands/toolbox_commands.dart';
import 'package:toolbox_core/toolbox_core.dart';

import '../device_probe.dart';
import 'context.dart';
import 'root.dart';

/// 投屏 / 截图 / 文件传输，对应 TS 版 src/main/ops/media.ts。
///
/// [screenshot] / [listRemote] / [pushFiles] / [pullFile] 走操作队列；
/// [startMirror] / [stopMirror] 是独立进程，不走操作队列（投屏期间可以照常做别的事）。

/// `20261014120000` 形式的时间戳，用于截图文件名和接收文件的重名后缀
String _stamp() => DateTime.now().toIso8601String().replaceAll(RegExp('[-:T]'), '').substring(0, 14);

/// 规范化手机端路径并校验在 /sdcard 内
String _remotePath(String path) {
  try {
    return remotePath(path);
  } on PathOutsideStorageException catch (e) {
    throw OpException(e.message);
  }
}

// ───────────── 截图 ─────────────

/// 截图并保存到「文档\一加工具箱\截图」
Future<OperationResult> screenshot(OpContext ctx) async {
  final serial = await ctx.requireSystem();
  ctx.step('正在截图');
  // 先拉到临时目录（adb 对中文路径支持不好），再移到「文档\一加工具箱\截图」
  final tmp = p.join(workDir(ctx.env), 'screen.png');
  if (!await captureScreenshot(ctx.adb, serial, tmp) || !File(tmp).existsSync()) {
    throw const OpException('截图失败，详见日志');
  }
  final dir = Directory(p.join(outputDir(ctx.env), '截图'))..createSync(recursive: true);
  final file = p.join(dir.path, 'screenshot_${_stamp()}.png');
  File(tmp).copySync(file);
  return OperationResult(ok: true, message: '截图已保存', outputPath: file);
}

// ───────────── 文件传输 ─────────────

Future<OperationResult> listRemote(String path, OpContext ctx) async {
  final dir = _remotePath(path);
  final serial = await ctx.requireSystem();
  final entries = await listRemoteEntries(ctx.adb, serial, dir);
  if (entries == null) throw OpException('读取 $dir 失败');
  return OperationResult(
    ok: true,
    message: '$dir：${entries.length} 项',
    remote: RemoteListing(path: dir, entries: entries),
  );
}

/// 推送到手机：先复制到临时目录（避开中文路径），再 adb push
Future<OperationResult> pushFiles(List<String> files, String to, OpContext ctx) async {
  if (files.isEmpty) throw const OpException('请先选择文件');
  final dir = _remotePath(to);
  final serial = await ctx.requireSystem();
  final tmp = workDir(ctx.env);
  final done = <String>[];
  for (var i = 0; i < files.length; i++) {
    final f = files[i];
    final stat = File(f).statSync();
    if (stat.type != FileSystemEntityType.file) {
      ctx.log(LogLevel.warn, '跳过 $f：不是文件');
      continue;
    }
    final name = p.basename(f);
    // 临时文件名只用 ASCII，避免 adb 处理中文路径出问题；文件名全是中文时拼不出临时名
    final ascii = name.replaceAll(RegExp(r'[^\w.-]'), '_');
    if (ascii.isEmpty) throw OpException('发送 $name 失败，详见日志');
    ctx.step('正在发送 $name（${i + 1}/${files.length}）');
    final local = p.join(tmp, '${i}_$ascii');
    File(f).copySync(local);
    if (!await pushFile(ctx.adb, serial, local, '$dir/$name')) {
      throw OpException('发送 $name 失败，详见日志');
    }
    done.add(name);
  }
  return OperationResult(ok: true, message: '已发送 ${done.length} 个文件到 $dir');
}

/// 从手机拉取一个文件到「文档\一加工具箱\传输」
Future<OperationResult> pullFile(String path, OpContext ctx) async {
  final remote = _remotePath(path);
  final serial = await ctx.requireSystem();
  final name = p.basename(remote);
  ctx.step('正在接收 $name');
  final tmp = p.join(workDir(ctx.env), 'pull.bin');
  if (!await pullFileTo(ctx.adb, serial, remote, tmp) || !File(tmp).existsSync()) {
    throw OpException('接收 $name 失败，详见日志');
  }
  final dir = Directory(p.join(outputDir(ctx.env), '传输'))..createSync(recursive: true);
  var file = p.join(dir.path, name);
  if (File(file).existsSync()) file = p.join(dir.path, '${_stamp()}_$name');
  try {
    File(tmp).renameSync(file);
  } on FileSystemException {
    File(tmp).copySync(file);
    try {
      File(tmp).deleteSync();
    } catch (_) {
      // 临时文件清理失败不影响结果
    }
  }
  return OperationResult(ok: true, message: '已保存 $name', outputPath: file);
}

// ───────────── 投屏 ─────────────

/// 正在运行的 scrcpy 进程，同时最多一个
Process? _mirror;

/// 投屏窗口是否还开着
bool get mirrorRunning => _mirror != null;

/// 启动 scrcpy 投屏。独立于操作队列运行（投屏期间可以照常做别的事），关掉窗口即结束。
/// ADB 环境变量指向工具箱自己的 adb，scrcpy 就不会再起一个不同版本的 adb server
Future<OperationResult> startMirror(
  MirrorOptions opts,
  ToolPaths tools,
  DeviceProbe probe,
  LogSink log,
) async {
  if (mirrorRunning) return const OperationResult.fail('投屏窗口已经打开了');
  final DeviceInfo d;
  try {
    d = await probe.detect();
  } catch (_) {
    return const OperationResult.fail('投屏需要手机开机并开启 USB 调试');
  }
  if (d.mode != DeviceMode.system || d.serial == null) return const OperationResult.fail('投屏需要手机开机并开启 USB 调试');
  if (d.needsPick) return const OperationResult.fail('连接了多台设备，请先在左下角选择要操作的那一台');
  if (!File(tools.scrcpy).existsSync()) {
    return const OperationResult.fail('缺少 scrcpy，开发环境请先运行 melos run fetch-tools');
  }
  final List<String> args;
  try {
    args = mirrorCommandArgs(d.serial!, opts, d.model ?? d.serial!);
  } on InvalidMirrorOptionsException catch (e) {
    return OperationResult.fail(e.message);
  }
  log(LogLevel.cmd, 'scrcpy ${args.join(' ')}');
  final Process child;
  try {
    child = await Process.start(
      tools.scrcpy,
      args,
      environment: {...Platform.environment, 'ADB': tools.adb},
    );
  } on ProcessException catch (e) {
    log(LogLevel.error, 'scrcpy 启动失败：${e.message}');
    return const OperationResult.fail('scrcpy 启动失败，详见日志');
  }
  _mirror = child;
  void onData(String chunk) {
    for (final line in chunk.split(RegExp(r'\r?\n'))) {
      final text = line.trim();
      if (text.isNotEmpty) log(LogLevel.info, '[scrcpy] $text');
    }
  }

  final out = child.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen(onData);
  final err = child.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen(onData);
  unawaited(child.exitCode.then((code) {
    log(code == 0 ? LogLevel.info : LogLevel.warn, '投屏已结束${code != 0 ? '（退出码 $code）' : ''}');
    if (identical(_mirror, child)) _mirror = null;
  }));
  unawaited(out.asFuture<void>().catchError((_) {}));
  unawaited(err.asFuture<void>().catchError((_) {}));
  final display = opts.display;
  return OperationResult(
    ok: true,
    message: display != null
        ? '独立屏幕正在打开${display.app == null || display.app!.isEmpty ? '，在窗口里点右下角的图标选择应用' : ''}。'
            '关掉窗口即结束${display.keepApp ? '，应用会移回手机' : '，上面的应用会被关闭'}'
        : '投屏窗口正在打开，关掉窗口即结束投屏',
  );
}

/// 关掉投屏窗口
void stopMirror() => _mirror?.kill();
