import 'package:flutter/material.dart';
import 'package:toolbox_service/toolbox_service.dart';

import '../controller.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';

/// 开机诊断页面。对应 TS 版的 src/renderer/src/bootdiag.tsx。

/// 需要 ROM 的修复
const _needsRom = {FixKind.unroot, FixKind.restoreVbmeta};

const _confidenceLabel = {
  Confidence.high: '可能性高',
  Confidence.medium: '有可能',
  Confidence.low: '可能性低',
};

/// 每种修复办法的按钮文案与说明
class _FixText {
  const _FixText(this.label, [this.guide]);

  final String label;

  /// 不用工具箱做、只告诉用户怎么做的那些办法（显示成一段说明而不是按钮）
  final String? guide;
}

const _fixText = <FixKind, _FixText>{
  FixKind.undoFlash: _FixText('撤销上一次刷写'),
  FixKind.unroot: _FixText('刷回原厂 boot / init_boot'),
  FixKind.restoreVbmeta: _FixText('刷回原厂 vbmeta'),
  FixKind.modulesDisable: _FixText('禁用全部模块'),
  FixKind.modulesRemove: _FixText('删除全部 Magisk 模块'),
  FixKind.safeMode: _FixText(
    '进安全模式',
    'KernelSU / APatch：开机出现第一屏后连续按几次音量下键；Magisk：开机时一直按住音量下键。安全模式下所有模块临时失效',
  ),
  FixKind.snapshotCancel: _FixText('取消未合并的更新'),
  FixKind.snapshotMerge: _FixText('继续合并更新'),
  FixKind.switchSlot: _FixText('切换到另一个槽位'),
  FixKind.fullFlash: _FixText(
    '完整线刷',
    '工具箱暂不支持完整线刷。请用官方的本地升级包或线刷工具重新刷入完整系统；注意不能刷比当前版本更旧的系统（防回滚，会变硬砖）',
  ),
  FixKind.wipeData: _FixText(
    '清除数据',
    '在 Recovery 里选择「清除数据」或「格式化数据」，会删除手机上的全部数据。只在确认是数据分区的问题时再做',
  ),
  FixKind.service: _FixText(
    '联系售后',
    '带上购机凭证去官方售后，说明做过的操作。导出「设置 → 日志与诊断」里的诊断信息，能帮助定位问题',
  ),
};

/// 刷写记录里 kind 的显示名
const _flashKind = {
  FlashKind.root: 'Root',
  FlashKind.unroot: '刷回原厂',
  FlashKind.restore: '刷回原厂分区',
  FlashKind.undo: '撤销刷写',
};

class BootDiagPage extends StatefulWidget {
  const BootDiagPage({super.key, required this.tb});

  final ToolboxController tb;

  @override
  State<BootDiagPage> createState() => _BootDiagPageState();
}

class _BootDiagPageState extends State<BootDiagPage> {
  final _symptoms = <BootSymptom>{};
  LastAction _lastAction = LastAction.unknown;
  bool _waitAdb = true;
  BootState? _state;
  List<FlashRecord> _history = const [];
  final _rom = TextEditingController();
  bool _allowUnverified = false;

  /// 已经按哪个「序列号 + 操作结果」读过刷写记录了
  Object? _historyToken;

  ToolboxController get tb => widget.tb;

  String? get _serial => _state?.serial ?? tb.device.serial;

  FlashRecord? get _last => _history.isEmpty ? null : _history.last;

  FlashRecord? get _undo => undoableFlash(_history);

  @override
  void initState() {
    super.initState();
    _refreshHistory();
  }

  @override
  void didUpdateWidget(covariant BootDiagPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换了设备或刚跑完一次操作后，重读这台手机的刷写记录。
    // 这里直接改字段而不 setState：本帧马上还会重建一次（对应 TSX 的 useEffect 依赖）。
    _refreshHistory();
  }

  @override
  void dispose() {
    _rom.dispose();
    super.dispose();
  }

  /// 读这台手机的刷写记录，并据此预选「最后做了什么」
  void _refreshHistory() {
    final serial = _serial;
    final token = Object.hash(serial, identityHashCode(tb.run.result));
    if (token == _historyToken) return;
    _historyToken = token;
    if (serial == null) {
      _history = const [];
      return;
    }
    final history = tb.service.history(serial);
    _history = history;
    if (_lastAction == LastAction.unknown) _lastAction = guessLastAction(history.isEmpty ? null : history.last);
  }

  Future<void> _collect() async {
    final r = await tb.start('开机诊断：读取设备状态', BootCollectRequest(waitAdb: _waitAdb));
    if (!mounted) return;
    setState(() {
      if (r.bootState != null) _state = r.bootState;
      _historyToken = null;
      _refreshHistory();
    });
  }

  Future<void> _runFix(Fix fix) async {
    final undo = _undo;
    final rom = _rom.text.trim();
    Future<void> ask(
      String title,
      String intro,
      List<String> checks,
      String confirmText,
      OperationRequest req, {
      bool danger = false,
    }) async {
      final ok = await confirmAction(
        context,
        ConfirmSpec(title: title, intro: intro, checks: checks, confirmText: confirmText, danger: danger),
      );
      if (ok) await tb.start(title, req);
    }

    switch (fix.kind) {
      case FixKind.undoFlash:
        final keys = undo == null ? '' : undo.backups.keys.join('、');
        return ask(
          '撤销上一次刷写',
          '把 ${undo != null ? _dateTime(undo.time) : ''} 刷写前备份的原厂 $keys 刷回 ${undo?.slot?.toUpperCase() ?? '原来的'} 槽，然后重启。',
          const ['手机在那之后没有升级过系统'],
          '撤销',
          const UndoFlashRequest(),
        );
      case FixKind.unroot:
        return ask(
          '刷回原厂 boot / init_boot',
          '从 ROM 中提取原厂的 boot / init_boot，刷回当前槽位后重启。',
          [
            'ROM 与手机当前系统版本完全一致',
            if (_allowUnverified) '我确认这个 ROM 就是手机现在的系统版本（工具箱无法校验）',
          ],
          '刷回原厂',
          UnrootRequest(UnrootOptions(rom: rom, uninstallManagers: false, allowUnverified: _allowUnverified)),
          danger: true,
        );
      case FixKind.restoreVbmeta:
        return ask(
          '刷回原厂 vbmeta',
          '从 ROM 中提取原厂的 vbmeta / vbmeta_system / vbmeta_vendor，刷回当前槽位后重启。',
          [
            'ROM 与手机当前系统版本完全一致',
            if (_allowUnverified) '我确认这个 ROM 就是手机现在的系统版本（工具箱无法校验）',
          ],
          '刷回原厂',
          RestoreStockRequest(RestoreOptions(
            rom: rom,
            partitions: const [StockPartition.vbmeta, StockPartition.vbmetaSystem, StockPartition.vbmetaVendor],
            allowUnverified: _allowUnverified,
          )),
          danger: true,
        );
      case FixKind.modulesDisable:
        return ask(
          '禁用全部模块',
          '给每个模块写入 disable 标记后重启。手机不在线时会一直等到开机过程中 adb 连上。',
          const ['这台电脑之前已经被手机授权过 USB 调试'],
          '禁用并重启',
          const ModulesRequest(ModuleAction.disable),
        );
      case FixKind.modulesRemove:
        return ask(
          '删除全部 Magisk 模块',
          '执行 magisk --remove-modules：删除全部模块并立即重启，模块的设置会一起丢失。',
          const ['这台电脑之前已经被手机授权过 USB 调试', '我知道模块会被删除，无法恢复'],
          '删除全部模块',
          const ModulesRequest(ModuleAction.remove),
          danger: true,
        );
      case FixKind.snapshotCancel:
        return ask(
          '取消未合并的更新',
          '重启到 fastbootd，执行 fastboot snapshot-update cancel。这次系统更新会被放弃，之后需要重新升级或刷写。',
          const ['我知道这次系统更新会被放弃'],
          '取消更新',
          const SnapshotUpdateRequest(SnapshotUpdateAction.cancel),
          danger: true,
        );
      case FixKind.snapshotMerge:
        return ask(
          '继续合并更新',
          '重启到 fastbootd，执行 fastboot snapshot-update merge，让没合并完的更新继续合并。可能需要几分钟到半小时，中途不要拔线。',
          const ['电量充足，过程中不会拔线'],
          '继续合并',
          const SnapshotUpdateRequest(SnapshotUpdateAction.merge),
        );
      case FixKind.switchSlot:
        return ask(
          '切换 A/B 槽位',
          '进入 Fastboot 后执行 fastboot --set-active=other，完成后设备停留在 Fastboot。',
          const ['我了解切换后可能需要再切回来'],
          '切换槽位',
          const SwitchSlotRequest(),
        );
      // 只有说明、没有按钮的办法，由 _FindingCard 直接显示 guide
      case FixKind.safeMode:
      case FixKind.fullFlash:
      case FixKind.wipeData:
      case FixKind.service:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final d = tb.device;
    final busy = tb.run.running;
    // 对应 TSX 的 `!!d.multiple && !d.selected`：连了多台、却一台都没选时才拦。
    // 这里不能直接用 needsPick —— 选中的那台正卡在开机（不在线）时 needsPick 也是 true，
    // 那种情况必须放行，才能用「等待开机过程中的 adb」去抓它。
    final pickFirst = d.needsPick && d.selected == null;
    final state = _state;
    final findings = state == null
        ? const <Finding>[]
        : diagnose(DiagnoseInput(
            state: state,
            symptoms: _symptoms.toList(),
            lastAction: _lastAction,
            lastFlash: _last,
            canUndo: _undo != null,
          ));
    final needRom = findings.any((f) => f.fixes.any((x) => _needsRom.contains(x.kind)));
    final rom = _rom.text.trim();
    final url = isUrl(rom);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader('开机诊断', '卡开机、开不了机但还能进 Fastboot 时，根据现象和设备状态推断原因，并给出对应的修复办法'),
        _symptomsCard(),
        const SizedBox(height: 16),
        _collectCard(c, d, busy, pickFirst),
        if (state != null) ...[
          const SizedBox(height: 16),
          _resultCard(findings, needRom: needRom, url: url, rom: rom, busy: busy),
        ],
        const SizedBox(height: 16),
        _limitsCard(),
      ],
    );
  }

  // ───────────── 1. 你看到了什么 ─────────────

  Widget _symptomsCard() {
    final last = _last;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardTitle('1. 你看到了什么'),
          for (final s in BootSymptom.values)
            CheckRow(
              value: _symptoms.contains(s),
              label: s.label,
              onChanged: (v) => setState(() => v ? _symptoms.add(s) : _symptoms.remove(s)),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Muted('出问题前最后做了什么', small: true),
              Segmented<LastAction>(
                value: _lastAction,
                options: [for (final a in LastAction.values) (a, a.label)],
                onChanged: (v) => setState(() => _lastAction = v),
              ),
            ],
          ),
          if (last != null) ...[const SizedBox(height: 10), Muted(_lastFlashText(last), small: true)],
        ],
      ),
    );
  }

  String _lastFlashText(FlashRecord last) {
    final scheme = last.scheme;
    final status = last.status == FlashStatus.failed ? '，刷写失败' : (last.status == FlashStatus.started ? '，没有完成' : '');
    return '工具箱记录的最后一次刷写：${_dateTime(last.time)}，${_flashKind[last.kind]}'
        '${scheme != null ? '（$scheme）' : ''}，${last.partitions.map((x) => x.name).join('、')}，'
        '${last.slot?.toUpperCase() ?? '?'} 槽$status${last.undone ? '，已撤销' : ''}';
  }

  // ───────────── 2. 读取设备状态 ─────────────

  Widget _collectCard(Palette c, DeviceInfo d, bool busy, bool pickFirst) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardTitle('2. 读取设备状态'),
          Text.rich(
            TextSpan(
              style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.55),
              children: const [
                TextSpan(text: '只读取，不改动手机。最好让手机进入 '),
                TextSpan(text: 'Fastboot', style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(
                  text: '（关机后同时按住 音量下 + 电源键）：能读到两个槽位的状态、解锁状态和系统更新状态。 '
                      '卡在开机画面时也可以直接读取，工具箱会抓开机过程中 adb 能连上的那几秒。',
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 13.5),
              children: [
                const TextSpan(text: '当前：'),
                TextSpan(text: d.mode.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (d.mode == DeviceMode.fastbootd)
                  TextSpan(
                    text: '（fastbootd 下读不到槽位是否成功启动过，切到 bootloader 再读一次更准）',
                    style: TextStyle(color: c.muted, fontSize: 12.5),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          CheckRow(
            value: _waitAdb,
            label: '手机连不上时，等待开机过程中的 adb（最多 3 分钟，需要这台电脑之前被手机授权过 USB 调试）',
            onChanged: d.mode == DeviceMode.none ? (v) => setState(() => _waitAdb = v) : null,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Gated(
                reason: pickFirst ? '请先在左下角选择要操作的设备' : null,
                child: AppButton(
                  label: _state != null ? '重新读取' : '读取状态并诊断',
                  icon: Icons.manage_search,
                  kind: ButtonKind.primary,
                  onPressed: busy || pickFirst ? null : _collect,
                ),
              ),
              if (pickFirst) const Muted('连接了多台设备，请先在左下角选择要操作的那一台', small: true),
            ],
          ),
          if (_state != null) ...[const SizedBox(height: 16), _StateSummary(_state!)],
        ],
      ),
    );
  }

  // ───────────── 3. 诊断结果 ─────────────

  Widget _resultCard(
    List<Finding> findings, {
    required bool needRom,
    required bool url,
    required String rom,
    required bool busy,
  }) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardTitle('3. 诊断结果'),
          if (_symptoms.isEmpty && _lastAction == LastAction.unknown)
            const Callout(Tone.info, text: '还没选择现象和最后做的操作，结果只根据设备状态推断。补充这两项能让判断准确得多。'),
          if (needRom) ...[
            const Muted('部分修复需要和手机当前系统版本完全一致的全量包：', small: true),
            const SizedBox(height: 8),
            PathField(
              icon: url ? Icons.link : Icons.folder_zip_outlined,
              hint: '选择本地全量包，或粘贴下载链接',
              controller: _rom,
              onChanged: (_) => setState(() {}),
              onBrowse: () async {
                final picked = await pickRom();
                if (picked != null) setState(() => _rom.text = picked);
              },
            ),
            CheckRow(
              value: _allowUnverified,
              label: '读不到手机系统版本时仍然继续（只在确定 ROM 版本正确时勾选）',
              onChanged: (v) => setState(() => _allowUnverified = v),
            ),
            const SizedBox(height: 10),
          ],
          for (final f in findings) _FindingCard(f: f, busy: busy, rom: rom, onFix: _runFix),
        ],
      ),
    );
  }

  Widget _limitsCard() {
    final c = context.palette;
    Widget bullet(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('· ', style: TextStyle(color: c.muted, fontSize: 12.5)),
              Expanded(child: Muted(text, small: true)),
            ],
          ),
        );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardTitle('工具箱救不了的情况'),
          bullet('连 Fastboot 都进不去：只能 9008 深刷或送售后（新系统上免授权 9008 已被熔断）'),
          bullet('Bootloader 已上锁、系统又起不来：不能再刷写任何分区，只能清除数据或送售后'),
        ],
      ),
    );
  }
}

/// 一个诊断结论：标题、可信度、依据和可执行的修复办法
class _FindingCard extends StatelessWidget {
  const _FindingCard({required this.f, required this.busy, required this.rom, required this.onFix});

  final Finding f;
  final bool busy;
  final String rom;
  final void Function(Fix fix) onFix;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final fg = switch (f.confidence) {
      Confidence.high => c.danger,
      Confidence.medium => c.warn,
      Confidence.low => c.muted,
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface2,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: fg),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.medical_services_outlined, size: 16, color: c.text),
                        const SizedBox(width: 8),
                        Expanded(child: Text(f.title, style: const TextStyle(fontWeight: FontWeight.w700))),
                        TagChip(_confidenceLabel[f.confidence]!, color: fg),
                      ],
                    ),
                    const SizedBox(height: 6),
                    for (final e in f.evidence)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Muted('· $e', small: true),
                      ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < f.fixes.length; i++) _fix(context, f.fixes[i], primary: i == 0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fix(BuildContext context, Fix fix, {required bool primary}) {
    final text = _fixText[fix.kind]!;
    final guide = text.guide;
    if (guide != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text.rich(
          TextSpan(
            style: const TextStyle(fontSize: 12.5, height: 1.55),
            children: [
              TextSpan(text: '${text.label}：', style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: guide),
              if (fix.note != null) TextSpan(text: '（${fix.note}）', style: TextStyle(color: context.palette.muted)),
            ],
          ),
        ),
      );
    }
    final noRom = _needsRom.contains(fix.kind) && rom.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Gated(
            reason: noRom ? '请先在上面选择 ROM' : null,
            child: AppButton(
              label: text.label,
              kind: primary ? ButtonKind.primary : ButtonKind.secondary,
              onPressed: busy || noRom ? null : () => onFix(fix),
            ),
          ),
          if (fix.note != null || noRom) Muted(noRom ? '需要先选择 ROM' : fix.note!, small: true),
        ],
      ),
    );
  }
}

/// 采集到的设备状态：属性、两个槽位的表格、说明和崩溃日志
class _StateSummary extends StatelessWidget {
  const _StateSummary(this.state);

  final BootState state;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final s = state;
    final rows = <(String, String?)>[
      ('读取时的模式', s.mode.label),
      ('当前槽位', s.currentSlot?.toUpperCase()),
      ('Bootloader', s.unlocked == null ? null : (s.unlocked! ? '已解锁' : '已上锁')),
      ('关键分区（critical）', s.criticalUnlocked == null ? null : (s.criticalUnlocked! ? '已解锁' : '未解锁')),
      ('系统更新合并状态', s.snapshotStatus),
      ('开机过程中 adb', s.adbDuringBoot == null ? null : (s.adbDuringBoot! ? '连上过' : '没连上')),
      ('Root', s.root),
    ].where((r) => r.$2 != null && r.$2!.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10)),
          child: LayoutBuilder(builder: (context, box) {
            final w = (box.maxWidth - 32) / 3;
            return Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                for (final (k, v) in rows)
                  SizedBox(
                    width: w < 140 ? box.maxWidth : w,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(k, style: TextStyle(fontSize: 12, color: c.muted)),
                        SelectableText(v!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
              ],
            );
          }),
        ),
        if (s.slots['a'] != null || s.slots['b'] != null) ...[
          const SizedBox(height: 12),
          _slots(c, s),
        ],
        for (final n in s.notes) ...[
          const SizedBox(height: 6),
          Muted('· $n', small: true),
        ],
        if (s.crashLog != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ExpansionTile(
              title: const Text('崩溃日志（logcat -b crash）', style: TextStyle(fontSize: 12.5)),
              tilePadding: const EdgeInsets.symmetric(horizontal: 12),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(8)),
                  child: SelectableText(
                    s.crashLog!,
                    style: const TextStyle(fontFamily: 'Consolas', fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _slots(Palette c, BootState s) {
    Widget cell(String text, {bool head = false, bool current = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: head || current ? FontWeight.w600 : FontWeight.normal,
              color: head ? c.muted : null,
            ),
          ),
        );
    String yn(bool? v, String yes, String no) => v == null ? '未知' : (v ? yes : no);
    return Table(
      border: TableBorder.all(color: c.border),
      children: [
        TableRow(
          decoration: BoxDecoration(color: c.surface2),
          children: [
            for (final h in const ['槽位', '成功启动过', '不可启动', '剩余重试']) cell(h, head: true),
          ],
        ),
        for (final k in const ['a', 'b'])
          TableRow(
            children: [
              cell('${k.toUpperCase()}${s.currentSlot == k ? '（当前）' : ''}', current: s.currentSlot == k),
              cell(yn(s.slots[k]?.successful, '是', '否')),
              cell(yn(s.slots[k]?.unbootable, '是', '否')),
              cell(s.slots[k]?.retryCount?.toString() ?? '未知'),
            ],
          ),
      ],
    );
  }
}

/// 与 TS 版 `new Date(t).toLocaleString('zh-CN', { hour12: false })` 一致，形如 2026/10/15 14:30:05
String _dateTime(int millis) {
  final t = DateTime.fromMillisecondsSinceEpoch(millis);
  String two(int v) => '$v'.padLeft(2, '0');
  return '${t.year}/${t.month}/${t.day} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}
