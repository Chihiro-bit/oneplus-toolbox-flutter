import 'package:flutter/material.dart';
import 'package:toolbox_service/toolbox_service.dart';

import '../controller.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import 'page_id.dart';

/// 救援与恢复页面。对应 TS 版的 src/renderer/src/rescue.tsx。
class RescuePage extends StatefulWidget {
  const RescuePage({super.key, required this.tb, required this.go});

  final ToolboxController tb;
  final Navigate go;

  @override
  State<RescuePage> createState() => _RescuePageState();
}

class _RescuePageState extends State<RescuePage> {
  final _rom = TextEditingController();
  bool _uninstallManagers = true;
  bool _allowUnverified = false;
  FlashRecord? _undo;

  /// 已经按哪个「序列号 + 操作结果」读过可撤销的刷写记录
  Object? _undoToken;

  ToolboxController get tb => widget.tb;

  @override
  void initState() {
    super.initState();
    _refreshUndo();
  }

  @override
  void didUpdateWidget(covariant RescuePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换了设备或刚跑完一次操作后重读记录（直接改字段，本帧还会重建一次）
    _refreshUndo();
  }

  @override
  void dispose() {
    _rom.dispose();
    super.dispose();
  }

  void _refreshUndo() {
    final serial = tb.device.serial;
    final token = Object.hash(serial, identityHashCode(tb.run.result));
    if (token == _undoToken) return;
    _undoToken = token;
    _undo = serial == null ? null : tb.service.undoableFlash(serial);
  }

  Future<void> _confirmUndo(FlashRecord undo) async {
    final ok = await confirmAction(
      context,
      ConfirmSpec(
        title: '撤销上一次刷写',
        intro: '把备份的原厂 ${undo.backups.keys.join('、')} 刷回 ${undo.slot?.toUpperCase() ?? '原来的'} 槽，然后重启。'
            '手机在那之后升级过系统时，工具箱会拒绝执行。',
        checks: const ['我知道撤销后 Root 会失效'],
        confirmText: '撤销',
      ),
    );
    if (ok) await tb.start('撤销上一次刷写', const UndoFlashRequest());
  }

  Future<void> _confirmUnroot() async {
    final ok = await confirmAction(
      context,
      ConfirmSpec(
        title: '刷回原厂镜像',
        danger: true,
        intro: '会从 ROM 中提取原厂的 boot / init_boot，进入 Fastboot 刷回当前槽位，然后重启。',
        checks: [
          'ROM 与手机当前系统版本完全一致',
          'Bootloader 已经解锁',
          if (_allowUnverified) '我确认这个 ROM 就是手机现在的系统版本（工具箱无法校验）',
        ],
        confirmText: '刷回原厂',
      ),
    );
    if (ok) {
      await tb.start(
        '刷回原厂镜像',
        UnrootRequest(UnrootOptions(
          rom: _rom.text.trim(),
          uninstallManagers: _uninstallManagers,
          allowUnverified: _allowUnverified,
        )),
      );
    }
  }

  Future<void> _modules(ModuleAction action) async {
    final title = action.label;
    final req = ModulesRequest(action);
    // 重新启用不会让手机重启，直接执行
    if (action == ModuleAction.enable) {
      await tb.start(title, req);
      return;
    }
    final ok = await confirmAction(
      context,
      ConfirmSpec(
        title: title,
        danger: action == ModuleAction.remove,
        intro: action == ModuleAction.remove
            ? '执行 magisk --remove-modules：删除 /data/adb/modules 下的全部模块并立即重启。模块的设置会一起丢失，无法恢复。'
            : '给每个模块写入 disable 标记后重启手机，模块文件和设置都会保留，之后可以在 Root 管理器里逐个启用。',
        checks:
            tb.device.mode == DeviceMode.none ? const ['这台电脑之前已经被手机授权过 USB 调试（否则卡开机时连不上 adb）'] : const ['我知道手机会立即重启'],
        confirmText: action == ModuleAction.remove ? '删除全部模块' : '禁用并重启',
      ),
    );
    if (ok) await tb.start(title, req);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final d = tb.device;
    final run = tb.run.running;
    final undo = _undo;
    final rom = _rom.text.trim();
    final unrootGate = gate(tb, {DeviceMode.system, DeviceMode.fastboot, DeviceMode.fastbootd});
    final systemGate = gate(tb, {DeviceMode.system});
    // 模块救援：手机不在线时也能点，工具会一直等到 adb 连上（卡开机时 adb 只出现几秒）
    final modulesBlocked = run
        ? '有操作正在进行'
        // 与 TSX 一致：连了多台、一台都没选才拦；选中的那台正卡在开机时要放行，好去等它连上 adb
        : (d.needsPick && d.selected == null)
            ? '连接了多台设备，请先在左下角选择要操作的那一台'
            : d.mode == DeviceMode.unauthorized
                ? '请先在手机上允许 USB 调试'
                : (d.mode == DeviceMode.fastboot || d.mode == DeviceMode.fastbootd || d.mode == DeviceMode.edl)
                    ? '需要手机开机（卡在开机画面也可以），Fastboot 下无法操作模块'
                    : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader('救援与恢复', 'Root 之后卡开机、想卸载 Root，先试这里。大多数情况下不需要用到 9008'),
        if (undo != null) ...[
          _undoCard(c, undo, unrootGate, run),
          const SizedBox(height: 16),
        ],
        _unrootCard(d, unrootGate, run, rom),
        const SizedBox(height: 16),
        _modulesCard(d, modulesBlocked, run),
        const SizedBox(height: 16),
        _backupCard(systemGate, run, rom),
        const SizedBox(height: 16),
        _othersCard(),
      ],
    );
  }

  // ───────────── 撤销上一次刷写 ─────────────

  Widget _undoCard(Palette c, FlashRecord undo, Gate g, bool run) {
    final parts = [
      for (final p in undo.partitions) '${p.name}${p.source == FlashSource.patched ? '（修补）' : ''}',
    ].join('、');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardTitle('撤销上一次刷写'),
          Muted(
            '${_dateTime(undo.time)} 用工具箱刷入了 ${undo.scheme ?? ''}（$parts，'
            '${undo.slot?.toUpperCase() ?? '?'} 槽）。 刷写前备份了原厂镜像，可以直接恢复，不需要 ROM。'
            'Root 后卡开机时，这是最快的办法。',
            small: true,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Gated(
                reason: g.reason,
                child: AppButton(
                  label: '撤销',
                  icon: Icons.undo,
                  kind: ButtonKind.primary,
                  onPressed: g.disabled ? null : () => _confirmUndo(undo),
                ),
              ),
              if (!run && g.reason != null) Muted(g.reason!, small: true),
            ],
          ),
        ],
      ),
    );
  }

  // ───────────── 刷回原厂镜像（卸载 Root） ─────────────

  Widget _unrootCard(DeviceInfo d, Gate g, bool run, String rom) {
    final url = isUrl(rom);
    final missing = rom.isEmpty ? '请先选择 ROM' : null;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardTitle('刷回原厂镜像（卸载 Root）'),
          const Muted(
            '从与手机系统版本一致的全量包中取出原厂的 boot 和 init_boot，一起刷回当前槽位。各家 Root 方案改的都是这两个分区之一，'
            '刷回之后就彻底卸载了 Root；修补后的镜像不兼容导致卡开机时，这也是最可靠的救法。',
            small: true,
          ),
          if (d.mode == DeviceMode.fastboot || d.mode == DeviceMode.fastbootd) ...[
            const SizedBox(height: 10),
            const Callout(
              Tone.info,
              text: '手机在 Fastboot 模式，读不到系统版本。工具箱会使用这台手机上次开机连接时记下的版本来校验；'
                  '从来没有开机连过的话，需要勾选下面的「仍然继续」。',
            ),
          ],
          const SizedBox(height: 10),
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
            value: _uninstallManagers,
            label: '刷完等手机开机，再卸载 Root 管理器 App（Magisk / APatch / KernelSU 及其分支）',
            onChanged: (v) => setState(() => _uninstallManagers = v),
          ),
          CheckRow(
            value: _allowUnverified,
            label: '读不到手机系统版本时仍然继续（只在 Fastboot 下、且确定 ROM 版本正确时勾选）',
            onChanged: (v) => setState(() => _allowUnverified = v),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Gated(
                reason: g.reason ?? missing,
                child: AppButton(
                  label: '刷回原厂',
                  icon: Icons.restart_alt,
                  kind: ButtonKind.primary,
                  onPressed: g.disabled || missing != null ? null : _confirmUnroot,
                ),
              ),
              if (!run && (g.reason ?? missing) != null) Muted((g.reason ?? missing)!, small: true),
            ],
          ),
        ],
      ),
    );
  }

  // ───────────── 模块导致卡开机 ─────────────

  Widget _modulesCard(DeviceInfo d, String? blocked, bool run) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardTitle('模块导致卡开机'),
          const Muted(
            '装了模块之后卡在开机画面、或进系统几秒就重启，多半是模块的问题。卡开机时 adb 往往只在开机过程中能连上几秒： '
            '先点下面的按钮，再让手机重启（或长按电源键强制重启），工具箱会一直等着，连上的瞬间立即执行。',
            small: true,
          ),
          if (d.root != null && d.mode == DeviceMode.system) ...[
            const SizedBox(height: 6),
            Muted('当前 Root 状态：${d.root}', small: true),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              Gated(
                reason: blocked,
                child: AppButton(
                  label: '禁用全部模块',
                  icon: Icons.toggle_off_outlined,
                  kind: ButtonKind.primary,
                  onPressed: blocked != null ? null : () => _modules(ModuleAction.disable),
                ),
              ),
              Gated(
                reason: blocked,
                child: AppButton(
                  label: '重新启用全部模块',
                  icon: Icons.toggle_on_outlined,
                  onPressed: blocked != null ? null : () => _modules(ModuleAction.enable),
                ),
              ),
              Gated(
                reason: blocked,
                child: AppButton(
                  label: '删除全部模块（Magisk）',
                  icon: Icons.delete_outline,
                  kind: ButtonKind.danger,
                  onPressed: blocked != null ? null : () => _modules(ModuleAction.remove),
                ),
              ),
            ],
          ),
          if (blocked != null && !run) GateHint(blocked),
          const SizedBox(height: 12),
          _bullet('禁用需要 Root 授权：手机能进系统时请在弹窗里点允许；卡开机时只有 Magisk 能直接授权给 Shell，其它情况请用下面两种办法'),
          _bullet('删除用的是 Magisk 官方的救砖命令 magisk --remove-modules，不需要授权，但模块会被删掉'),
          _bullet('KernelSU / APatch 可以进安全模式（所有模块临时失效）：开机出现第一屏后连续按几次音量下键；'
              'Magisk 的安全模式是开机时一直按住音量下键'),
        ],
      ),
    );
  }

  // ───────────── 备份关键分区 ─────────────

  Widget _backupCard(Gate g, bool run, String rom) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardTitle('备份关键分区'),
          const Muted(
            '趁手机还好好的时候做。persist、modemst1/2、fsg、ocdt 存着这台手机独有的基带和校准数据，'
            '坏了刷什么 ROM 都恢复不了（IMEI 丢失、没信号），只能靠自己的备份。',
            small: true,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              Gated(
                reason: g.reason,
                child: AppButton(
                  label: '备份关键分区（需要 Root）',
                  icon: Icons.download_for_offline_outlined,
                  kind: ButtonKind.primary,
                  onPressed: g.disabled
                      ? null
                      : () => tb.start(
                            '备份关键分区',
                            const BackupPartitionsRequest(BackupOptions(source: BackupSource.device)),
                          ),
                ),
              ),
              Gated(
                reason: g.reason ?? (rom.isEmpty ? '请先在上面选择 ROM' : null),
                child: AppButton(
                  label: '从 ROM 保存原厂镜像',
                  icon: Icons.folder_zip_outlined,
                  onPressed: g.disabled || rom.isEmpty
                      ? null
                      : () => tb.start(
                            '从 ROM 保存原厂镜像',
                            BackupPartitionsRequest(BackupOptions(source: BackupSource.rom, rom: rom)),
                          ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _bullet('备份关键分区：用 Root 权限读出上面几个分区和当前槽位的 boot / init_boot / vendor_boot / dtbo，只读不写，附带 sha256 校验文件'),
          _bullet('没 Root：用上面选择的、和手机版本一致的 ROM，提取原厂启动镜像和 vbmeta 存到本地，卡开机时不用再找 ROM'),
          _bullet('备份在「文档\\一加工具箱\\backups」，建议再复制一份到网盘或其它电脑'),
          if (g.reason != null && !run) GateHint(g.reason),
        ],
      ),
    );
  }

  // ───────────── 其它办法 ─────────────

  Widget _othersCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardTitle('其它办法'),
          ResponsiveGrid(
            minItemWidth: 250,
            maxColumns: 3,
            gap: 10,
            children: [
              _Tile(Icons.monitor_heart_outlined, '开机诊断', '不确定原因时，按现象和设备状态推断该用哪种办法', () => widget.go(PageId.diagnose)),
              _Tile(Icons.swap_horiz, '切换 A/B 槽位', '另一个槽位完好时，切过去往往能直接开机', () => widget.go(PageId.slot)),
              _Tile(Icons.notifications_off_outlined, '禁用系统更新', 'Root 后系统自动更新可能覆盖修补，甚至卡开机',
                  () => widget.go(PageId.tools)),
            ],
          ),
          const SizedBox(height: 14),
          const Muted('以上都不行、连 Fastboot 都进不去时，请联系售后。导出「设置 → 日志与诊断」里的诊断信息，能帮助定位问题。', small: true),
        ],
      ),
    );
  }

  Widget _bullet(String text) {
    final c = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('· ', style: TextStyle(color: c.muted, fontSize: 12.5)),
          Expanded(child: Muted(text, small: true)),
        ],
      ),
    );
  }
}

/// 跳转到其它页面的卡片
class _Tile extends StatelessWidget {
  const _Tile(this.icon, this.title, this.desc, this.onTap);

  final IconData icon;
  final String title;
  final String desc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(side: BorderSide(color: c.border), borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        hoverColor: c.surface2,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              ActionIcon(icon),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(desc, style: TextStyle(fontSize: 12.5, color: c.muted)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward, size: 16, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// 与 TS 版 `new Date(t).toLocaleString('zh-CN', { hour12: false })` 一致，形如 2026/10/15 14:30:05
String _dateTime(int millis) {
  final t = DateTime.fromMillisecondsSinceEpoch(millis);
  String two(int v) => '$v'.padLeft(2, '0');
  return '${t.year}/${t.month}/${t.day} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}
