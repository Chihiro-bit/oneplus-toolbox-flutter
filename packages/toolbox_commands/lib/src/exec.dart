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

  final process = await Process.start(file, args);
  final stdout = StringBuffer();
  final stderr = StringBuffer();
  final all = StringBuffer();
  var pending = '';

  void flush({bool last = false}) {
    if (log == null || !echoOutput) return;
    final parts = pending.split(RegExp(r'\r?\n|\r'));
    pending = last ? '' : parts.removeLast();
    for (final line in parts) {
      if (line.trim().isNotEmpty) log(LogLevel.info, line.trimRight());
    }
  }

  StreamSubscription<String> listen(Stream<List<int>> stream, StringBuffer into) =>
      stream.transform(const Utf8Decoder(allowMalformed: true)).listen((s) {
        into.write(s);
        all.write(s);
        pending += s;
        flush();
      });

  final outDone = listen(process.stdout, stdout).asFuture<void>();
  final errDone = listen(process.stderr, stderr).asFuture<void>();

  if (stdin != null) process.stdin.write(stdin);
  unawaited(process.stdin.close().catchError((_) {}));

  final result = Completer<ExecResult>();
  final timer = Timer(timeout, () {
    if (result.isCompleted) return;
    process.kill();
    result.complete(ExecResult(-1, '$stdout', '$stderr\n[超时]', '$all\n[超时]'));
  });
  cancel?.whenCancelled.then((_) {
    if (result.isCompleted) return;
    process.kill();
    result.completeError(const CancelledException());
  });
  unawaited(process.exitCode.then((code) async {
    await Future.wait([outDone, errDone]);
    flush(last: true);
    if (!result.isCompleted) result.complete(ExecResult(code, '$stdout', '$stderr', '$all'));
  }));

  try {
    return await result.future;
  } finally {
    timer.cancel();
  }
}

String _quoteForLog(String a) {
  // 多行 shell 脚本只显示第一行，避免刷屏
  if (a.contains('\n')) {
    final lines = a.split('\n');
    return '"${lines.first} …"（共 ${lines.length} 行脚本）';
  }
  return RegExp(r'[\s"]').hasMatch(a) ? '"$a"' : a;
}

/// 可取消的等待
Future<void> delay(Duration d, [CancelToken? cancel]) async {
  cancel?.throwIfCancelled();
  if (cancel == null) return Future.delayed(d);
  await Future.any([Future.delayed(d), cancel.whenCancelled]);
  cancel.throwIfCancelled();
}
