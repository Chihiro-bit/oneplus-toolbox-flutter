/// 开机诊断规则。输入「设备状态 + 刷写记录 + 用户看到的现象」，输出可能的原因、可信度和修复办法。
/// 纯函数，不连设备，规则都有单元测试（test/bootdiag_test.dart）。
///
/// 判断槽位状态时注意（一加 13 实测）：
/// - 正常 OTA 之后，另一个槽位常被标成 unbootable，这本身不是故障
/// - fastbootd 报的 slot-successful 和 bootloader 不一致，采集时已丢弃 fastbootd 的这个值
///
/// 对应 TS 版的 src/shared/bootdiag.ts。
library;

import 'models.dart';
import 'root.dart';

enum FixKind {
  undoFlash,
  unroot,
  restoreVbmeta,
  modulesDisable,
  modulesRemove,
  safeMode,
  snapshotCancel,
  snapshotMerge,
  switchSlot,
  fullFlash,
  wipeData,
  service,
}

class Fix {
  const Fix(this.kind, {this.note});

  final FixKind kind;

  /// 补充说明，显示在按钮旁
  final String? note;
}

enum Confidence { high, medium, low }

class Finding {
  const Finding({
    required this.id,
    required this.title,
    required this.confidence,
    required this.evidence,
    required this.fixes,
  });

  final String id;
  final String title;
  final Confidence confidence;

  /// 判断依据，逐条显示
  final List<String> evidence;

  /// 推荐的修复办法，按优先级排列
  final List<Fix> fixes;
}

class DiagnoseInput {
  const DiagnoseInput({
    required this.state,
    required this.symptoms,
    required this.lastAction,
    this.lastFlash,
    this.canUndo = false,
  });

  final BootState state;
  final List<BootSymptom> symptoms;
  final LastAction lastAction;

  /// 最近一次刷写记录
  final FlashRecord? lastFlash;

  /// 有能撤销的刷写（带原厂备份）
  final bool canUndo;
}

const _rank = {Confidence.high: 0, Confidence.medium: 1, Confidence.low: 2};

String _other(String s) => s == 'a' ? 'b' : 'a';

/// 另一个槽位明确可用：没被标成不可启动，并且成功启动过
bool _otherSlotUsable(BootState st) {
  final current = st.currentSlot;
  if (current == null) return false;
  final o = st.slots[_other(current)];
  return o?.unbootable == false && o?.successful == true;
}

bool _currentUnbootable(BootState st) {
  final current = st.currentSlot;
  if (current == null) return false;
  final c = st.slots[current];
  return c != null && (c.unbootable == true || c.retryCount == 0);
}

List<Finding> diagnose(DiagnoseInput input) {
  final st = input.state;
  final lastAction = input.lastAction;
  final lastFlash = input.lastFlash;
  bool has(BootSymptom s) => input.symptoms.contains(s);
  final findings = <Finding>[];
  final slotName = st.currentSlot?.toUpperCase();

  // ── Bootloader 已上锁：什么都不能刷，只剩清数据和售后 ──
  if (st.unlocked == false) {
    findings.add(const Finding(
      id: 'locked',
      title: 'Bootloader 已上锁，工具箱无法刷写',
      confidence: Confidence.high,
      evidence: ['Fastboot 报告 unlocked: no', '上锁状态下镜像被改过就会起不来，而且不能再刷写任何分区'],
      fixes: [Fix(FixKind.wipeData, note: '只对数据分区不兼容的情况有效'), Fix(FixKind.service)],
    ));
    return findings;
  }

  final rootRecent = lastAction == LastAction.root ||
      (lastFlash?.kind == FlashKind.root && lastFlash?.undone == false && lastAction == LastAction.unknown);

  // ── 修补后的镜像不兼容（版本不对、KMI 不匹配、刷错分区） ──
  if (rootRecent) {
    final evidence = <String>['出问题前最后一次操作是 Root（刷入了修补后的镜像）'];
    if (lastFlash?.kind == FlashKind.root) {
      final patched = lastFlash!.partitions.where((p) => p.source == FlashSource.patched).map((p) => p.name).join('、');
      evidence.add('刷写记录：${lastFlash.scheme ?? ''} 修补 $patched，${lastFlash.slot?.toUpperCase() ?? '?'} 槽');
    }
    if (has(BootSymptom.crashdump)) evidence.add('出现 QUALCOMM CrashDump Mode，内核或 ramdisk 在启动早期就崩了');
    if (_currentUnbootable(st)) evidence.add('当前 $slotName 槽已被 bootloader 标为不可启动');
    final strong = has(BootSymptom.crashdump) || _currentUnbootable(st);
    final looping = has(BootSymptom.logo) || has(BootSymptom.bootloop);
    findings.add(Finding(
      id: 'patched-image',
      title: '修补后的镜像和系统不兼容',
      confidence: strong ? Confidence.high : (looping ? Confidence.medium : Confidence.low),
      evidence: evidence,
      fixes: [
        if (input.canUndo) const Fix(FixKind.undoFlash, note: '用刷写前备份的原厂镜像恢复，不需要 ROM'),
        const Fix(FixKind.unroot, note: '需要和手机系统版本一致的全量包'),
      ],
    ));
  }

  // ── 模块导致卡开机 ──
  final rooted = isRooted(st.root);
  if (lastAction == LastAction.module ||
      (st.adbDuringBoot == true && rooted && !rootRecent && (has(BootSymptom.logo) || has(BootSymptom.bootloop)))) {
    final evidence = <String>[];
    if (lastAction == LastAction.module) evidence.add('出问题前最后一次操作是安装或更新模块');
    if (st.adbDuringBoot == true) evidence.add('开机过程中 adb 能连上，说明内核和 Root 已经起来，卡在了更后面');
    if (rooted) evidence.add('Root 状态：${st.root}');
    findings.add(Finding(
      id: 'module',
      title: 'Root 模块导致卡开机',
      confidence: lastAction == LastAction.module
          ? (st.adbDuringBoot == true ? Confidence.high : Confidence.medium)
          : Confidence.low,
      evidence: evidence,
      fixes: const [Fix(FixKind.modulesDisable), Fix(FixKind.modulesRemove), Fix(FixKind.safeMode)],
    ));
  }

  // ── vbmeta / 镜像校验失败 ──
  if (has(BootSymptom.destroyed)) {
    findings.add(Finding(
      id: 'vbmeta',
      title: 'vbmeta 或镜像校验失败',
      confidence: Confidence.high,
      evidence: const ['出现 The current image have been destroyed，bootloader 校验镜像签名没通过'],
      fixes: [
        const Fix(FixKind.restoreVbmeta, note: '刷回和系统版本一致的原厂 vbmeta'),
        if (input.canUndo) const Fix(FixKind.undoFlash),
        const Fix(FixKind.wipeData, note: '之前用 --disable-verity 关过校验的话，恢复校验后需要清除数据'),
      ],
    ));
  }

  // ── 系统更新的数据还没合并完 ──
  final snap = st.snapshotStatus?.toLowerCase();
  if (snap == 'snapshotted' || snap == 'merging') {
    final afterUpdate = lastAction == LastAction.ota || lastAction == LastAction.flash;
    findings.add(Finding(
      id: 'snapshot',
      title: snap == 'merging' ? '系统更新正在合并，合并没能完成' : '有一个还没合并的系统更新',
      confidence: snap == 'merging' || afterUpdate ? Confidence.high : Confidence.medium,
      evidence: [
        'snapshot-update-status: $snap',
        snap == 'merging' ? '虚拟 A/B 更新的数据还在往原分区合并，中途被打断或失败都会卡开机' : '更新已经装好但还没开机合并；这时手动刷分区，新旧数据会冲突',
      ],
      fixes: snap == 'merging'
          ? const [Fix(FixKind.snapshotMerge, note: '在 fastbootd 下让合并继续完成')]
          : const [Fix(FixKind.snapshotCancel, note: '放弃这次更新；之后可以重新升级或刷写')],
    ));
  }

  // ── 刷系统后槽位不一致、只刷了一半 ──
  if (lastAction == LastAction.flash || lastAction == LastAction.ota) {
    final usable = _otherSlotUsable(st);
    findings.add(Finding(
      id: 'slots',
      title: lastAction == LastAction.ota ? '系统更新没装好，当前槽位起不来' : '系统没刷完整，两个槽位的版本可能不一致',
      confidence: _currentUnbootable(st) ? Confidence.high : Confidence.medium,
      evidence: [
        lastAction == LastAction.ota ? '出问题前最后一次操作是系统更新' : '出问题前最后一次操作是刷系统',
        if (_currentUnbootable(st)) '当前 $slotName 槽已被标为不可启动',
        usable ? '另一个 ${_other(st.currentSlot!).toUpperCase()} 槽成功启动过，也没被标为不可启动' : '另一个槽位不确定是否完好（被标为不可启动，或读不到状态）',
      ],
      fixes: usable ? const [Fix(FixKind.switchSlot), Fix(FixKind.fullFlash)] : const [Fix(FixKind.fullFlash)],
    ));
  }

  // ── 跨版本刷机后数据分区不兼容 ──
  if (has(BootSymptom.recovery)) {
    findings.add(Finding(
      id: 'data',
      title: '数据分区和当前系统不兼容',
      confidence: lastAction == LastAction.flash || lastAction == LastAction.ota ? Confidence.high : Confidence.medium,
      evidence: const ['开机后自动进入 Recovery 并提示无法启动系统，通常是降级或跨版本刷机后，旧数据新系统读不了'],
      fixes: const [Fix(FixKind.wipeData, note: '会清除全部数据')],
    ));
  }

  // ── 没有 Root 相关操作却进了 CrashDump ──
  if (has(BootSymptom.crashdump) && !rootRecent) {
    findings.add(Finding(
      id: 'crash',
      title: '系统在启动早期崩溃',
      confidence: Confidence.medium,
      evidence: const ['出现 QUALCOMM CrashDump Mode，但最近没有刷入修补后的镜像，可能是固件或内核镜像损坏'],
      fixes: [
        if (_otherSlotUsable(st)) const Fix(FixKind.switchSlot),
        const Fix(FixKind.fullFlash),
        const Fix(FixKind.service),
      ],
    ));
  }

  // ── 没有规则命中 ──
  if (findings.isEmpty) {
    findings.add(Finding(
      id: 'unknown',
      title: '没有找到明确的原因',
      confidence: Confidence.low,
      evidence: const ['根据目前采集到的信息和你选择的现象，没有匹配到已知的情况。可以补充「最后做了什么」，或导出诊断信息反馈问题'],
      fixes: [
        if (_otherSlotUsable(st)) const Fix(FixKind.switchSlot),
        if (input.canUndo) const Fix(FixKind.undoFlash),
        const Fix(FixKind.service),
      ],
    ));
  }

  // 按可信度排序（同级别保持原有顺序：Dart 的 List.sort 不保证稳定，这里自己带上原下标）
  final indexed = findings.asMap().entries.toList()
    ..sort((a, b) {
      final r = _rank[a.value.confidence]! - _rank[b.value.confidence]!;
      return r != 0 ? r : a.key.compareTo(b.key);
    });
  return [for (final e in indexed) e.value];
}

/// 还能撤销的最近一次刷写：没被撤销过、带原厂备份；失败的撤销不算数，可以重试
FlashRecord? undoableFlash(List<FlashRecord> history) {
  final usable = [
    for (final r in history)
      if (r.kind != FlashKind.undo || r.status == FlashStatus.ok) r
  ];
  if (usable.isEmpty) return null;
  final last = usable.last;
  return !last.undone && last.kind != FlashKind.undo && last.backups.isNotEmpty ? last : null;
}

/// 从刷写记录推断「最后做了什么」的默认值：一天内刷过 Root 且没撤销就预选 Root
LastAction guessLastAction(FlashRecord? lastFlash, [int? now]) {
  final t = now ?? DateTime.now().millisecondsSinceEpoch;
  if (lastFlash != null && lastFlash.kind == FlashKind.root && !lastFlash.undone && t - lastFlash.time < 86400000) {
    return LastAction.root;
  }
  return LastAction.unknown;
}

// ───────────── 解析 fastboot 输出（纯函数，便于测试） ─────────────

/// 这些变量带一个子键，例如 slot-retry-count:b:7、partition-size:boot_a:0x6000000
final _subkeyVars =
    RegExp(r'^(slot-successful|slot-unbootable|slot-retry-count|partition-size|partition-type|has-slot|is-logical)$');
final _getvarLine = RegExp(r'^\(bootloader\)\s+([\w.-]+):(.*)$');
final _digits = RegExp(r'^\d+$');

/// 解析 getvar all 的输出（每行 (bootloader) key:value）。值里可能还有冒号（如 fingerprint），只按第一个冒号切
Map<String, String> parseGetvarAll(String out) {
  final vars = <String, String>{};
  for (final line in out.split(RegExp(r'\r?\n'))) {
    final m = _getvarLine.firstMatch(line);
    if (m == null) continue;
    var key = m.group(1)!;
    var rest = m.group(2)!;
    final i = rest.indexOf(':');
    if (_subkeyVars.hasMatch(key) && i >= 0) {
      key = '$key:${rest.substring(0, i)}';
      rest = rest.substring(i + 1);
    }
    vars[key] = rest.trim();
  }
  return vars;
}

bool? _yesNo(String? v) => v == 'yes' ? true : (v == 'no' ? false : null);

/// 从 getvar 结果整理槽位状态。fastbootd 报的 slot-successful 不可靠（实测与 bootloader 相反），丢弃
Map<String, SlotState> slotsFromVars(Map<String, String> vars, bool userspace) {
  final slots = <String, SlotState>{};
  for (final s in const ['a', 'b']) {
    final retry = vars['slot-retry-count:$s'];
    final st = SlotState(
      successful: userspace ? null : _yesNo(vars['slot-successful:$s']),
      unbootable: _yesNo(vars['slot-unbootable:$s']),
      retryCount: retry != null && _digits.hasMatch(retry) ? int.parse(retry) : null,
    );
    if (!st.isEmpty) slots[s] = st;
  }
  return slots;
}

final _criticalUnlocked = RegExp(r'Device critical unlocked:\s*(true|false)', caseSensitive: false);

/// oem device-info 里的 Device critical unlocked
bool? parseCriticalUnlocked(String out) {
  final m = _criticalUnlocked.firstMatch(out);
  return m == null ? null : m.group(1)!.toLowerCase() == 'true';
}
