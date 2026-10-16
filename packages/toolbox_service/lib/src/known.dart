import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 开机时读到的设备信息，按序列号记到 `<dataDir>/devices.json`。
/// Fastboot 下读不到品牌和系统版本，卡开机时更是只能进 Fastboot，
/// 这时就靠之前开机连接时记下的信息（例如校验刷回的原厂镜像与系统版本是否一致）。
///
/// 对应 TS 版的 src/main/known.ts。
class KnownDevice {
  const KnownDevice({
    this.brand,
    this.manufacturer,
    this.model,
    this.buildDateUtc,
    this.buildId,
    this.romVersion,
    this.seen = 0,
  });

  final String? brand;
  final String? manufacturer;
  final String? model;

  /// ro.build.date.utc，与 ROM payload 的 max_timestamp 相同
  final String? buildDateUtc;
  final String? buildId;
  final String? romVersion;

  /// 最后一次开机连接的时间（毫秒）
  final int seen;

  Map<String, Object?> toJson({bool withSeen = true}) => {
        if (brand != null) 'brand': brand,
        if (manufacturer != null) 'manufacturer': manufacturer,
        if (model != null) 'model': model,
        if (buildDateUtc != null) 'buildDateUtc': buildDateUtc,
        if (buildId != null) 'buildId': buildId,
        if (romVersion != null) 'romVersion': romVersion,
        if (withSeen) 'seen': seen,
      };

  factory KnownDevice.fromJson(Map<String, Object?> json) => KnownDevice(
        brand: json['brand'] as String?,
        manufacturer: json['manufacturer'] as String?,
        model: json['model'] as String?,
        buildDateUtc: json['buildDateUtc'] as String?,
        buildId: json['buildId'] as String?,
        romVersion: json['romVersion'] as String?,
        seen: json['seen'] is num ? (json['seen'] as num).toInt() : 0,
      );
}

class KnownStore {
  KnownStore(this.dataDir);

  final String dataDir;
  Map<String, KnownDevice>? _cache;

  File get _file => File(p.join(dataDir, 'devices.json'));

  Map<String, KnownDevice> _load() {
    final cached = _cache;
    if (cached != null) return cached;
    try {
      final raw = jsonDecode(_file.readAsStringSync());
      _cache = {
        if (raw is Map)
          for (final e in raw.entries)
            if (e.value is Map) '${e.key}': KnownDevice.fromJson(Map<String, Object?>.from(e.value as Map)),
      };
    } catch (_) {
      _cache = {};
    }
    return _cache!;
  }

  KnownDevice? get(String serial) => _load()[serial];

  void remember(String serial, KnownDevice info) {
    final all = _load();
    final prev = all[serial];
    final next = KnownDevice(
      brand: info.brand,
      manufacturer: info.manufacturer,
      model: info.model,
      buildDateUtc: info.buildDateUtc,
      buildId: info.buildId,
      romVersion: info.romVersion,
      seen: DateTime.now().millisecondsSinceEpoch,
    );
    all[serial] = next;
    // 信息没变就不写盘（轮询每次状态变化都会调用）
    if (prev != null && jsonEncode(prev.toJson(withSeen: false)) == jsonEncode(next.toJson(withSeen: false))) return;
    try {
      _file.parent.createSync(recursive: true);
      _file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
        for (final e in all.entries) e.key: e.value.toJson(),
      }));
    } catch (_) {
      // 写不进去只是少了离线信息
    }
  }
}
