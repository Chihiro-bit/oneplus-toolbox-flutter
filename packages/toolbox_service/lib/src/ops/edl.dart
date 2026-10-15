import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:toolbox_commands/toolbox_commands.dart';
import 'package:toolbox_core/toolbox_core.dart';

import 'context.dart';

// ───────────── 9008 救砖 ─────────────
//
// 工具箱本身不实现 Sahara / Firehose，也不打包任何欧加真的专有文件：
// 刷写交给 qdl（BSD-3-Clause，随安装包分发），设备编程器、签名摘要和深刷散包
// 全部由用户自备。这里负责的是检测、文件校验、参数排序、日志和风险提示。

const _flashTimeout = Duration(minutes: 60);
const _dryRunTimeout = Duration(minutes: 15);

/// LUN5 上的分区一旦写错很难恢复，默认不刷
final _lun5Xml = RegExp(r'^(rawprogram|patch)5(_\d+)?\.xml$', caseSensitive: false);

void _ensureQdl(OpContext ctx) {
  if (!File(ctx.tools.qdl).existsSync()) {
    throw const OpException('缺少 qdl.exe，请先运行 melos run fetch-tools 准备第三方工具');
  }
}

/// 找到唯一一台在线的 9008 设备
Future<List<EdlDevice>> _requireSingleEdl(OpContext ctx) async {
  ctx.step('正在查找 9008 设备');
  final ports = await listEdlDevices(ctx.cancel);
  if (ports.isEmpty) {
    throw const OpException(
        '没有检测到 9008 设备。请依次确认：①已安装高通 9008（QDLoader）驱动；②手机确实进入了 EDL 模式；③数据线支持数据传输');
  }
  if (ports.length > 1) throw OpException('检测到 ${ports.length} 个 9008 设备，请只连接一台');
  ctx.log(LogLevel.ok, '已找到 ${ports.first.port.isNotEmpty ? ports.first.port : '9008 设备'}（${ports.first.name}）');
  return ports;
}

/// 返回文件集的问题列表，空数组表示可以开工
List<String> _profileProblems(EdlProfile profile) {
  final problems = <String>[];
  if (profile.programmer.trim().isEmpty) {
    problems.add('未选择设备编程器（devprg*.mbn）');
  } else if (!File(profile.programmer).existsSync()) {
    problems.add('找不到编程器：${profile.programmer}');
  }
  if (profile.imagesDir.trim().isEmpty) {
    problems.add('未选择散包目录');
  } else if (!Directory(profile.imagesDir).existsSync()) {
    problems.add('找不到散包目录：${profile.imagesDir}');
  }
  if (profile.xmls.isEmpty) problems.add('未选择 rawprogram / patch XML');
  for (final x in profile.xmls) {
    if (!File(x).existsSync()) problems.add('找不到 XML：$x');
  }
  final vip = profile.vipDir;
  if (vip != null && vip.isNotEmpty && !Directory(vip).existsSync()) problems.add('找不到摘要表目录：$vip');
  return problems;
}

/// qdl 按命令行顺序发送 XML，patch 必须排在 rawprogram 之后。
/// 同时按「保护 LUN5」把 rawprogram5 / patch5 挑出来。
({List<String> kept, List<String> skipped}) _orderXmls(List<String> xmls, bool protectLun5) {
  final kept = <String>[];
  final skipped = <String>[];
  for (final x in xmls) {
    if (protectLun5 && _lun5Xml.hasMatch(p.basename(x))) {
      skipped.add(p.basename(x));
    } else {
      kept.add(x);
    }
  }
  int rank(String path) => RegExp(r'^patch', caseSensitive: false).hasMatch(p.basename(path)) ? 1 : 0;
  kept.sort((a, b) {
    final r = rank(a) - rank(b);
    return r != 0 ? r : _naturalCompare(p.basename(a), p.basename(b));
  });
  return (kept: kept, skipped: skipped);
}

/// 按数字自然顺序比较文件名，使 rawprogram2 排在 rawprogram10 之前（对应 TS 的 localeCompare numeric）
int _naturalCompare(String a, String b) {
  final chunks = RegExp(r'\d+|\D+');
  final as = chunks.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final bs = chunks.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < as.length && i < bs.length; i++) {
    final x = as[i];
    final y = bs[i];
    final nx = int.tryParse(x);
    final ny = int.tryParse(y);
    final cmp = (nx != null && ny != null) ? nx.compareTo(ny) : x.compareTo(y);
    if (cmp != 0) return cmp;
  }
  return as.length.compareTo(bs.length);
}

List<String> _buildArgs(EdlProfile profile, List<String> xmls, {required bool dryRun}) {
  final args = <String>[];
  if (dryRun) args.add('--dry-run');
  args.add('--storage=${profile.storage.name}');
  final vip = profile.vipDir;
  if (vip != null && vip.isNotEmpty) args.add('--vip-table-path=$vip');
  if (profile.imagesDir.isNotEmpty) args.add('--include=${profile.imagesDir}');
  if (profile.allowMissing) args.add('--allow-missing');
  if (profile.skipReset) args.add('--skip-reset');
  args.add(profile.programmer);
  args.addAll(xmls);
  return args;
}

// ───────────── 检测 ─────────────

Future<OperationResult> edlDetect(OpContext ctx) async {
  _ensureQdl(ctx);
  ctx.step('正在查找 9008 设备');
  final ports = await listEdlDevices(ctx.cancel);
  for (final port in ports) {
    ctx.log(LogLevel.info, '9008 端口：${port.name}');
  }

  ctx.step('正在让 qdl 枚举设备');
  final listed = await ctx.qdl.run(['list'], timeout: const Duration(seconds: 30));
  final state = EdlState(ports: ports, qdlList: listed.all.trim(), saharaOk: false);

  if (ports.isEmpty) {
    return OperationResult(
      ok: false,
      message: '没有检测到 9008 设备。请先安装高通 9008（QDLoader）驱动，再让手机进入 EDL 模式',
      edl: state,
    );
  }
  ctx.log(LogLevel.ok, 'qdl 枚举到 ${ports.length} 台 9008 设备');
  return OperationResult(ok: true, message: '已找到 ${ports.length} 台 9008 设备', edl: state);
}

// ───────────── 预检（全程只读） ─────────────

Future<OperationResult> edlProbe(EdlProfile profile, OpContext ctx) async {
  _ensureQdl(ctx);
  final ports = await _requireSingleEdl(ctx);

  ctx.step('正在通过 Sahara 读取芯片信息（只读）');
  final chip = await ctx.qdl.run(['chipinfo'], timeout: const Duration(seconds: 60));
  final saharaOk = chip.code == 0;
  final state = EdlState(ports: ports, chipInfo: chip.all.trim(), saharaOk: saharaOk);

  if (!saharaOk) {
    ctx.log(LogLevel.error, chip.all.trim().isEmpty ? 'qdl chipinfo 失败' : chip.all.trim());
    return OperationResult(
      ok: false,
      message:
          'Sahara 通信失败。请先确认 9008 驱动、数据线和端口都正常；如果这台机器已经更新过带熔断的版本（例如一加 13 的 16.0.3.501 及以后），免授权 EDL 已经不可用',
      edl: state,
    );
  }
  ctx.log(LogLevel.ok, 'Sahara 通信正常，芯片信息已读出');

  final problems = _profileProblems(profile);
  if (problems.isNotEmpty) {
    return OperationResult(ok: false, message: 'Sahara 正常。文件还没准备好：${problems.join('；')}', edl: state);
  }

  ctx.step('正在离线预检文件集（qdl --dry-run，不接触设备）');
  final ordered = _orderXmls(profile.xmls, profile.protectLun5);
  if (ordered.skipped.isNotEmpty) ctx.log(LogLevel.warn, '按「保护 LUN5」跳过：${ordered.skipped.join('、')}');
  if (ordered.kept.isEmpty) throw const OpException('过滤后没有可用的 XML，请检查 rawprogram / patch 文件');

  final args = _buildArgs(profile, ordered.kept, dryRun: true);
  final dry = await ctx.qdl.run(args, timeout: _dryRunTimeout);
  return OperationResult(
    ok: dry.code == 0,
    message: dry.code == 0 ? '预检通过：Sahara 正常，文件集与摘要表一致，可以开始刷写' : '预检未通过：qdl --dry-run 报错，请按日志修正文件集后再试',
    edl: EdlState(ports: ports, chipInfo: chip.all.trim(), saharaOk: saharaOk, command: Qdl.asCommand(args)),
  );
}

// ───────────── 刷写 ─────────────

Future<OperationResult> edlFlash(EdlProfile profile, OpContext ctx) async {
  _ensureQdl(ctx);
  final problems = _profileProblems(profile);
  if (problems.isNotEmpty) throw OpException('文件不完整：${problems.join('；')}');
  final ports = await _requireSingleEdl(ctx);

  final ordered = _orderXmls(profile.xmls, profile.protectLun5);
  if (ordered.skipped.isNotEmpty) ctx.log(LogLevel.warn, '按「保护 LUN5」跳过：${ordered.skipped.join('、')}');
  if (ordered.kept.isEmpty) throw const OpException('过滤后没有可用的 XML，请检查 rawprogram / patch 文件');

  // 无论如何都先跑一遍离线预检：XML 与摘要表不匹配时，绝不碰设备
  ctx.step('刷写前先做一次离线预检');
  final dryArgs = _buildArgs(profile, ordered.kept, dryRun: true);
  final dry = await ctx.qdl.run(dryArgs, timeout: _dryRunTimeout);
  if (dry.code != 0) {
    return OperationResult(
      ok: false,
      message: '预检未通过，没有向设备写入任何数据。请按日志修正文件集后重试',
      edl: EdlState(ports: ports, saharaOk: true, command: Qdl.asCommand(dryArgs)),
    );
  }
  ctx.log(LogLevel.ok, '预检通过');

  if (profile.dryRunOnly) {
    return OperationResult(
      ok: true,
      message: '预检通过。按你的设置只做预检，没有刷入任何分区',
      edl: EdlState(ports: ports, saharaOk: true, command: Qdl.asCommand(dryArgs)),
    );
  }

  final args = _buildArgs(profile, ordered.kept, dryRun: false);
  final command = Qdl.asCommand(args);
  ctx.step('正在刷写分区');
  ctx.log(LogLevel.warn, '刷写期间不要拔线、不要让电脑休眠或断电');
  final r = await ctx.qdl.run(args, timeout: _flashTimeout);

  if (r.code != 0) {
    return OperationResult(
      ok: false,
      message: '刷写失败。请完整保留日志里的 qdl 输出，再对照散包与机型排查',
      edl: EdlState(ports: ports, saharaOk: true, command: command),
    );
  }
  return OperationResult(
    ok: true,
    message: profile.skipReset ? '刷写完成。按你的设置没有重启，设备仍停留在 9008' : '刷写完成，已向设备发出重启指令',
    edl: EdlState(ports: ports, saharaOk: true, command: command),
  );
}

// ───────────── 退出 9008 ─────────────

Future<OperationResult> edlReset(OpContext ctx) async {
  _ensureQdl(ctx);
  final ports = await _requireSingleEdl(ctx);
  ctx.step('正在让设备退出 9008 并重启');
  final r = await ctx.qdl.run(['reset'], timeout: const Duration(seconds: 60));
  return OperationResult(
    ok: r.code == 0,
    message: r.code == 0 ? '已发送重启指令' : '重启指令失败。可以长按电源键 10 秒以上强制重启',
    edl: EdlState(ports: ports, saharaOk: false),
  );
}
