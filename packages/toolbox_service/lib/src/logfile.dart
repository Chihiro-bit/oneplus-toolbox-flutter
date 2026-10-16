import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:toolbox_core/toolbox_core.dart';

/// 每次操作的日志写到「文档\一加工具箱\logs\」，按天分文件，保留 30 天。
///
/// 对应 TS 版的 src/main/logfile.ts。
class LogFile {
  LogFile(this.documentsDir);

  final String documentsDir;

  static const keepDays = 30;

  String get dir => p.join(documentsDir, '一加工具箱', 'logs');

  static String _day(int t) {
    final d = DateTime.fromMillisecondsSinceEpoch(t);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

  /// 写入失败（磁盘满、文档目录被重定向到不可写位置等）只影响落盘，不影响操作本身
  void append(LogEntry e) {
    try {
      final text = e.level == LogLevel.cmd ? '\$ ${e.text}' : e.text;
      File(p.join(dir, '${_day(e.time.millisecondsSinceEpoch)}.log'))
          .writeAsStringSync('${_time(e.time)} [${e.level.name}] $text\n', mode: FileMode.append);
    } catch (_) {
      // 忽略
    }
  }

  /// 删除 30 天前的日志
  void prune() {
    try {
      final cutoff = _day(DateTime.now().millisecondsSinceEpoch - keepDays * 86400000);
      final d = Directory(dir);
      if (!d.existsSync()) return;
      for (final f in d.listSync()) {
        if (f is! File) continue;
        final name = p.basename(f.path);
        if (RegExp(r'^\d{4}-\d{2}-\d{2}\.log$').hasMatch(name) && name.substring(0, 10).compareTo(cutoff) < 0) {
          f.deleteSync();
        }
      }
    } catch (_) {
      // 忽略
    }
  }

  /// 最近两天日志的最后 [maxLines] 行
  List<String> recent(int maxLines) {
    final lines = <String>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final t in [now - 86400000, now]) {
      final f = File(p.join(dir, '${_day(t)}.log'));
      if (!f.existsSync()) continue;
      lines.addAll([
        '──── ${_day(t)} ────',
        ...f.readAsStringSync().split('\n').where((l) => l.isNotEmpty),
      ]);
    }
    return lines.length <= maxLines ? lines : lines.sublist(lines.length - maxLines);
  }
}
