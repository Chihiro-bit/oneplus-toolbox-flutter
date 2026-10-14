import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:toolbox_core/toolbox_core.dart';

import 'exec.dart';

/// payload-dumper-rust：读取 OTA 包（本地 zip / payload.bin / http(s) URL）
class PayloadDumper {
  const PayloadDumper(this.exe, {this.cancel, this.log});

  final String exe;
  final CancelToken? cancel;
  final LogSink? log;

  /// 读取 payload 元数据中的 max_timestamp。它就是目标系统的构建时间，
  /// 与 OTA 包 META-INF/com/android/metadata 里的 post-timestamp、手机上的 ro.build.date.utc 相同。
  /// 不是标准 OTA 包时返回 null。
  Future<String?> maxTimestamp(String rom, String workDir) async {
    final metaDir = p.join(workDir, 'metadata');
    final r = await exec(exe, [rom, '--metadata', '-o', metaDir],
        cancel: cancel, log: log, echoOutput: false, timeout: const Duration(minutes: 5));
    final file = File(p.join(metaDir, 'metadata.json'));
    if (!r.ok || !file.existsSync()) return null;
    try {
      final ts = (jsonDecode(file.readAsStringSync()) as Map)['max_timestamp'];
      return ts == null ? null : '$ts';
    } catch (_) {
      return null;
    }
  }

  /// 提取指定分区的镜像到 [outDir]。使用 URL 时只下载这些分区所需的数据。
  Future<bool> extract(String rom, List<String> partitions, String outDir) async {
    final r = await exec(exe, [rom, '-i', partitions.join(','), '-o', outDir, '-q'],
        cancel: cancel, log: log, timeout: const Duration(minutes: 30));
    return r.ok;
  }
}
