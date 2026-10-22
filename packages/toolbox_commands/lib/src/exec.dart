import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:toolbox_core/toolbox_core.dart';

class ExecResult {
  const ExecResult(this.code, this.stdout, this.stderr, this.all);

  final int code;
  final String stdout;
  final String stderr;

  /// stdout + stderr（fastboot 把大部分信息写在 stderr）
  final String all;

  bool get ok => code == 0;
}

/// 运行一个外部程序，收集输出。
///
/// - [cancel] 取消时结束子进程并抛出 [CancelledException]
/// - 超时后结束子进程，返回 code = -1（不抛异常，与 TS 版一致）
/// - [log] 不为空时先写一行命令，再把输出逐行写入（[echoOutput] 为 false 时只写命令）
Future<ExecResult> exec(
  String file,
  List<String> args, {
  CancelToken? cancel,
  Duration timeout = const Duration(seconds: 60),
  LogSink? log,
  bool echoOutput = true,
  String? stdin,
}) async {
  cancel?.throwIfCancelled();
  log?.call(LogLevel.cmd, '${p.basenameWithoutExtension(file)} ${args.map(_quoteForLog).join(' ')}');

  final watch = Stopwatch()..start();
  late final Process process;
  try {
    process = await Process.start(file, args);
  } catch (e) {
    log?.call(LogLevel.error, '命令启动失败：$e（耗时 ${watch.elapsedMilliseconds} ms）');
    rethrow;
  }
  final stdout = StringBuffer();
  final stderr = StringBuffer();
  final all = StringBuffer();
  final result = Completer<ExecResult>();
  final flushers = <void Function()>[];

  StreamSubscription<String> listen(Stream<List<int>> stream, StringBuffer into) {
    var pending = '';
    void flush({bool last = false}) {
      if (log == null || !echoOutput) return;
      final parts = pending.split(RegExp(r'\r\n|[\r\n]'));
      pending = last ? '' : parts.removeLast();
      for (final line in parts) {
        if (line.trim().isNotEmpty) log(LogLevel.info, line.trimRight());
      }
    }

    flushers.add(() => flush(last: true));
    return stream.transform(const Utf8Decoder(allowMalformed: true)).listen((s) {
      if (result.isCompleted) return;
      into.write(s);
      all.write(s);
      if (echoOutput && log != null) {
        pending += s;
        flush();
      }
    });
  }

  void flushAll() {
    for (final flush in flushers) {
      flush();
    }
  }

  final outDone = listen(process.stdout, stdout).asFuture<void>();
  final errDone = listen(process.stderr, stderr).asFuture<void>();

  if (stdin != null) process.stdin.write(stdin);
  unawaited(process.stdin.close().catchError((_) {}));

  final timer = Timer(timeout, () {
    if (result.isCompleted) return;
    process.kill();
    flushAll();
    log?.call(LogLevel.error, '命令超时（限制 ${timeout.inMilliseconds} ms，耗时 ${watch.elapsedMilliseconds} ms）');
    result.complete(ExecResult(-1, '$stdout', '$stderr\n[超时]', '$all\n[超时]'));
  });
  cancel?.whenCancelled.then((_) {
    if (result.isCompleted) return;
    process.kill();
    flushAll();
    log?.call(LogLevel.warn, '命令已取消（耗时 ${watch.elapsedMilliseconds} ms）');
    result.completeError(const CancelledException());
  });
  unawaited(process.exitCode.then((code) async {
    try {
      await Future.wait([outDone, errDone]);
      if (result.isCompleted) return;
      flushAll();
      log?.call(code == 0 ? LogLevel.info : LogLevel.error,
          '命令结束：退出码 $code，耗时 ${watch.elapsedMilliseconds} ms${echoOutput ? '' : '（此命令的输出为内部数据，不在日志中显示）'}');
      result.complete(ExecResult(code, '$stdout', '$stderr', '$all'));
    } catch (e, stack) {
      if (result.isCompleted) return;
      flushAll();
      log?.call(LogLevel.error, '命令输出读取失败：$e');
      result.completeError(e, stack);
    }
  }));

  try {
    return await result.future;
  } finally {
    timer.cancel();
  }
}

String _quoteForLog(String a) {
  // 只用于显示，保留完整脚本以及参数边界，不作为 shell 命令执行。
  return a.isEmpty || RegExp(r'[\s"\\]').hasMatch(a) ? '"${a.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"' : a;
}

/// 可取消的等待
Future<void> delay(Duration d, [CancelToken? cancel]) async {
  cancel?.throwIfCancelled();
  if (cancel == null) return Future.delayed(d);
  await Future.any([Future.delayed(d), cancel.whenCancelled]);
  cancel.throwIfCancelled();
}
