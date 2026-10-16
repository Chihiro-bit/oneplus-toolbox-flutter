import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:toolbox_commands/toolbox_commands.dart';
import 'package:toolbox_core/toolbox_core.dart';

/// 刷写记录，按序列号存到 `<dataDir>/flash-history.json`。
/// 每次刷写前记下槽位、分区、方案、系统版本和刷入镜像的 sha256，并把被覆盖分区的原厂镜像备份到
/// 文档\一加工具箱\backups\<序列号>\<构建时间>\。卡开机时「撤销上一次刷写」和开机诊断都靠这份记录。
///
/// 对应 TS 版的 src/main/history.ts。
class FlashHistory {
  FlashHistory({required this.dataDir, required this.documentsDir});

  final String dataDir;

  /// 备份镜像放到「<documentsDir>/一加工具箱/backups/...」
  final String documentsDir;

  static const keepPerDevice = 20;

  Map<String, List<FlashRecord>>? _cache;
  final _random = Random();

  File get _file => File(p.join(dataDir, 'flash-history.json'));

  Map<String, List<FlashRecord>> _load() {
    final cached = _cache;
    if (cached != null) return cached;
    try {
      final raw = jsonDecode(_file.readAsStringSync());
      _cache = {
        if (raw is Map)
          for (final e in raw.entries)
            if (e.value is List)
              '${e.key}': [
                for (final r in e.value as List)
                  if (r is Map) FlashRecord.fromJson(Map<String, Object?>.from(r)),
              ],
      };
    } catch (_) {
      _cache = {};
    }
    return _cache!;
  }

  void _save() {
    try {
      _file.parent.createSync(recursive: true);
      _file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
        for (final e in _load().entries) e.key: [for (final r in e.value) r.toJson()],
      }));
    } catch (_) {
      // 写不进去只是少了记录，不影响刷写本身
    }
  }

  List<FlashRecord> history(String serial) => _load()[serial] ?? const [];

  /// 最近一条记录（不论成败）
  FlashRecord? lastFlash(String serial) {
    final list = history(serial);
    return list.isEmpty ? null : list.last;
  }

  /// 记录一次刷写的开始，返回这条记录（用它的 id 更新后续状态）
  FlashRecord add({
    required String serial,
    required FlashKind kind,
    String? scheme,
    String? slot,
    required FlashBuild build,
    List<FlashPartition> partitions = const [],
    Map<String, FlashBackup> backups = const {},
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rec = FlashRecord(
      id: '${now.toRadixString(36)}${_random.nextInt(1 << 20).toRadixString(36).padLeft(4, '0').substring(0, 4)}',
      time: now,
      serial: serial,
      kind: kind,
      scheme: scheme,
      slot: slot,
      build: build,
      partitions: partitions,
      backups: backups,
      status: FlashStatus.started,
    );
    final all = _load();
    final list = [...?all[serial], rec];
    all[serial] = list.length > keepPerDevice ? list.sublist(list.length - keepPerDevice) : list;
    _save();
    return rec;
  }

  /// 还能撤销的最近一次刷写
  FlashRecord? undoable(String serial) => undoableFlash(history(serial));

  void update(String serial, String id, {FlashStatus? status, bool? undone}) {
    final list = _load()[serial];
    if (list == null) return;
    final i = list.indexWhere((r) => r.id == id);
    if (i < 0) return;
    list[i] = list[i].copyWith(status: status, undone: undone);
    _save();
  }

  /// 备份目录：文档\一加工具箱\backups\<序列号>\<构建时间或 unknown>
  String backupDir(String serial, String? buildDateUtc) {
    final dir = p.join(
      documentsDir,
      '一加工具箱',
      'backups',
      serial.replaceAll(RegExp(r'[^\w.-]'), '_'),
      (buildDateUtc == null || buildDateUtc.isEmpty) ? 'unknown' : buildDateUtc,
    );
    Directory(dir).createSync(recursive: true);
    return dir;
  }

  /// 把原厂镜像复制到备份目录；同名文件已存在且内容相同就不再复制
  Future<({String path, String sha256})> backupImage(
    String serial,
    String? buildDateUtc,
    String partition,
    String src,
  ) async {
    final sha256 = await sha256File(src);
    final path = p.join(backupDir(serial, buildDateUtc), '$partition.img');
    final target = File(path);
    if (!target.existsSync() || await sha256File(path) != sha256) {
      File(src).copySync(path);
    }
    return (path: path, sha256: sha256);
  }
}
