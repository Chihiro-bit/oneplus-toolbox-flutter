import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:toolbox_core/toolbox_core.dart';

import '../catalog_repository.dart';
import '../known.dart';
import 'context.dart';

/// 导出诊断信息。
///
/// 对应 TS 版 src/main/ops/diagnostics.ts。

/// 只导出和刷机相关的属性，不含 IMEI、账号、网络等信息
final _propAllow = RegExp(
  r'^(ro\.product\.|ro\.build\.|ro\.boot\.(slot_suffix|verifiedbootstate|vbmeta\.device_state|flash\.locked|hwc)$'
  r'|ro\.oplus|ro\.vendor\.oplus|ro\.rom\.version|ro\.crypto\.|ro\.virtual_ab|ro\.treble|ro\.kernel\.'
  r'|sys\.boot_completed|init\.svc\.adbd)',
);
final _propDeny = RegExp(r'serial|imei|meid|iccid|uuid|mac|android_id', caseSensitive: false);
final _serialLikeLine = RegExp('serial', caseSensitive: false);

/// 序列号只留首尾两位；Windows 用户名和主目录换成占位符
String maskReport(String text, List<String> serials, String user, String home) {
  var out = text;
  for (final s in serials) {
    if (s.isEmpty || s.length <= 4) continue;
    out = out.replaceAll(s, '${s.substring(0, 2)}${'*' * (s.length - 4)}${s.substring(s.length - 2)}');
  }
  if (home.isNotEmpty) out = out.replaceAll(home, '%USERPROFILE%');
  if (user.length > 2) out = out.replaceAll(user, '<user>');
  return out;
}

/// `new Date().toLocaleString('zh-CN', { hour12: false })` 的结果：2026/1/2 03:04:05
String _nowText() {
  final t = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}/${t.month}/${t.day} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// 与 [DeviceInfo] 对应的 JSON，键和 TS 版的 JSON.stringify(device, null, 2) 一致（读不到的字段不输出）
Map<String, Object?> _deviceJson(DeviceInfo d) => {
      if (d.serial != null) 'serial': d.serial,
      'mode': d.mode.name,
      if (d.edlPort != null) 'edlPort': d.edlPort,
      if (d.device != null) 'device': d.device,
      if (d.multiple) 'multiple': true,
      if (d.devices.isNotEmpty) 'devices': [for (final x in d.devices) x.toJson()],
      if (d.selected != null) 'selected': d.selected,
      if (d.multiple) 'needsPick': d.needsPick,
      if (d.model != null) 'model': d.model,
      if (d.brand != null) 'brand': d.brand,
      if (d.manufacturer != null) 'manufacturer': d.manufacturer,
      if (d.buildId != null) 'buildId': d.buildId,
      if (d.romVersion != null) 'romVersion': d.romVersion,
      if (d.androidVersion != null) 'androidVersion': d.androidVersion,
      if (d.slot != null) 'slot': d.slot,
      if (d.unlocked != null) 'unlocked': d.unlocked,
      if (d.root != null) 'root': d.root,
    };

/// 导出诊断信息：工具箱版本、系统、设备状态（开机读 getprop 白名单，Fastboot 读 getvar all）和最近两天的日志，
/// 写成一个纯文本文件，提交问题反馈时直接附上。
Future<OperationResult> exportDiagnostics(OpContext ctx, {required CatalogRepository catalog}) async {
  ctx.step('正在收集诊断信息');
  final lines = <String>[];
  void section(String title) => lines.addAll(['', '==== $title ====']);

  lines.add('一加工具箱诊断信息  ${_nowText()}');
  section('环境');
  lines.add('工具箱 ${ctx.env.appVersion}  Windows ${Platform.operatingSystemVersion}');
  final cat = await catalog.get();
  lines.add('方案目录：${cat.source.name}${cat.error != null ? '（${cat.error}）' : ''}');

  var device = DeviceInfo.disconnected;
  try {
    device = await ctx.probe.describe(await ctx.probe.detect(ctx.cancel), ctx.cancel);
  } on CancelledException {
    rethrow;
  } catch (_) {
    // 读不到设备信息时只导出环境与日志
  }
  section('设备');
  lines.add(const JsonEncoder.withIndent('  ').convert(_deviceJson(device)));
  final serial = device.serial;
  if (serial != null) {
    final k = KnownStore(ctx.env.dataDir).get(serial);
    if (k != null) lines.add('上次开机时的记录：${jsonEncode(k.toJson())}');
  }

  if (serial != null && device.mode == DeviceMode.system) {
    final props = await ctx.probe.getProps(serial, ctx.cancel);
    section('getprop（已过滤）');
    final keys = props.keys.toList()..sort();
    for (final k in keys) {
      if (_propAllow.hasMatch(k) && !_propDeny.hasMatch(k)) lines.add('$k=${props[k]}');
    }
  }
  if (serial != null && (device.mode == DeviceMode.fastboot || device.mode == DeviceMode.fastbootd)) {
    final all = await ctx.probe.getvarAll(serial, ctx.cancel);
    section('fastboot getvar all');
    lines.addAll([
      for (final line in all.split(RegExp(r'\r?\n')))
        if (line.trim().isNotEmpty && !_serialLikeLine.hasMatch(line)) line,
    ]);
  }

  section('最近日志');
  lines.addAll(ctx.logFile.recent(1500));

  final dir = Directory(p.join(ctx.env.documentsDir, '一加工具箱', 'diagnostics'))..createSync(recursive: true);
  final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[-:T]'), '').substring(0, 14);
  final file = p.join(dir.path, 'diagnostics_$stamp.txt');
  File(file).writeAsStringSync(maskReport(
    lines.join('\n'),
    [serial ?? ''],
    Platform.environment['USERNAME'] ?? '',
    Platform.environment['USERPROFILE'] ?? '',
  ));
  return OperationResult(ok: true, message: '诊断信息已导出，提交问题反馈时请附上这个文件', outputPath: file);
}
