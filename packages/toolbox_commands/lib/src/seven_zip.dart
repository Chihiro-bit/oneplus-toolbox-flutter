import 'package:toolbox_core/toolbox_core.dart';

import 'exec.dart';

/// 7-Zip 命令行（7za.exe）
class SevenZip {
  const SevenZip(this.exe, {this.cancel, this.log});

  final String exe;
  final CancelToken? cancel;
  final LogSink? log;

  /// 列出压缩包内容（原始输出）
  Future<String> list(String archive) async {
    final r = await exec(exe, ['l', archive], cancel: cancel, echoOutput: false, timeout: const Duration(minutes: 2));
    return r.stdout;
  }

  /// 压缩包根目录是否包含指定文件名
  static bool listContains(String listing, String name) =>
      RegExp('\\s${RegExp.escape(name)}\\r?\$', multiLine: true).hasMatch(listing);

  /// 把压缩包里的指定文件解到 [outDir]
  Future<ExecResult> extract(String archive, List<String> files, String outDir) =>
      exec(exe, ['x', archive, ...files, '-o$outDir', '-y'],
          cancel: cancel, log: log, timeout: const Duration(minutes: 10));
}
