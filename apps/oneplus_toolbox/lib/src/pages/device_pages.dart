import 'package:flutter/material.dart';
import 'package:toolbox_service/toolbox_service.dart';

import '../controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';

const _anyMode = {DeviceMode.system, DeviceMode.recovery, DeviceMode.fastboot, DeviceMode.fastbootd};

/// 操作卡片：图标、标题、说明、按钮
class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.icon, required this.title, required this.children, this.tone});

  final IconData icon;
  final Tone? tone;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ActionIcon(icon, tone: tone),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}

// ───────────── 重启 ─────────────

class RebootPage extends StatelessWidget {
  const RebootPage({super.key, required this.tb});

  final ToolboxController tb;

  static const _items = [
    (RebootTarget.system, '重启到系统', '正常开机', Icons.restart_alt),
    (RebootTarget.recovery, 'Recovery', '部分机型不支持从 Fastboot 直接进入', Icons.build_outlined),
    (RebootTarget.bootloader, 'Fastboot', '解锁、刷写分区时使用', Icons.bolt_outlined),
    (RebootTarget.fastbootd, 'fastbootd', '用户空间的 Fastboot，取消未合并的系统更新、刷逻辑分区时用', Icons.bolt_outlined),
  ];

  /// 9008 已停用（[Features.edl] 为 false）时，这一项不显示
  static const _edlItem = (RebootTarget.edl, 'EDL / 9008', '高通线刷 / MTK 深刷模式，建议从开机状态进入', Icons.gpp_maybe_outlined);

  Future<void> _run(BuildContext context, RebootTarget target, String title) async {
    if (target == RebootTarget.edl) {
      final ok = await confirmAction(
        context,
        const ConfirmSpec(
          title: '进入 EDL 模式',
          intro: 'EDL 是高通线刷 / MTK 深刷模式，手机会黑屏，只能用专用线刷工具或按键组合退出。',
          checks: ['我知道如何退出 EDL：长按 音量上 + 电源键（老机型长按电源键）'],
          confirmText: '进入 EDL',
        ),
      );
      if (!ok) return;
    }
    await tb.start('重启到 $title', RebootRequest(target));
  }

  @override
  Widget build(BuildContext context) {
    final g = gate(tb, _anyMode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader('重启与模式', '在开机、Recovery、Fastboot 之间切换'),
        ResponsiveGrid(
          minItemWidth: 200,
          children: [
            for (final (target, title, desc, icon) in [..._items, if (Features.edl) _edlItem])
              _ActionCard(
                icon: icon,
                title: title,
                children: [
                  Expanded(child: Muted(desc, small: true)),
                  const SizedBox(height: 14),
                  Gated(
                    reason: g.reason,
                    child: AppButton(label: '执行', onPressed: g.disabled ? null : () => _run(context, target, title)),
                  ),
                ],
              ),
          ],
        ),
        GateHint(g.hint(tb)),
      ],
    );
  }
}

// ───────────── Bootloader ─────────────

class BootloaderPage extends StatelessWidget {
  const BootloaderPage({super.key, required this.tb});

  final ToolboxController tb;

  Future<void> _unlock(BuildContext context) async {
    final ok = await confirmAction(
      context,
      const ConfirmSpec(
        title: '解锁 Bootloader',
        danger: true,
        intro: '手机将自动进入 Fastboot 并发送解锁指令。确认后手机上的所有数据都会被清除。',
        checks: [
          '我已备份手机数据到电脑、云端或其它设备',
          '我已在开发者选项中打开「OEM 解锁」',
          '我的机型不需要深度测试，或已通过深度测试审核',
        ],
        confirmText: '开始解锁',
      ),
    );
    if (ok) await tb.start('解锁 Bootloader', const UnlockRequest());
  }

  Future<void> _relock(BuildContext context) async {
    final ok = await confirmAction(
      context,
      const ConfirmSpec(
        title: '上锁 Bootloader',
        danger: true,
        intro: '上锁同样会清空全部数据。如果系统被修改过，上锁后可能无法开机。',
        checks: ['我已备份手机数据', '当前系统是完全官方、未修改的状态（已卸载 Magisk 或刚平刷过全量包）'],
        confirmText: '开始上锁',
      ),
    );
    if (ok) await tb.start('上锁 Bootloader', const RelockRequest());
  }

  @override
  Widget build(BuildContext context) {
    final g = gate(tb, {DeviceMode.system, DeviceMode.fastboot, DeviceMode.fastbootd});
    final d = tb.device;
    const steps = [
      '备份手机数据（解锁会清除全部数据，包括内置存储）',
      '在「开发者选项」中打开「OEM 解锁」',
      '部分机型需要先申请并通过「深度测试」',
      '执行后，在手机上用音量键选中 UNLOCK THE BOOTLOADER，按电源键确认',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader('Bootloader', '解锁是 Root 和刷第三方系统的前提。解锁、上锁都会清空手机全部数据'),
        if ((d.mode == DeviceMode.fastboot || d.mode == DeviceMode.fastbootd) && d.unlocked != null)
          Callout(Tone.info, text: '当前 Bootloader 状态：${d.unlocked! ? '已解锁' : '已锁定'}'),
        ResponsiveGrid(
          minItemWidth: 320,
          maxColumns: 2,
          children: [
            _ActionCard(
              icon: Icons.lock_open_outlined,
              tone: Tone.info,
              title: '解锁 Bootloader',
              children: [
                for (var i = 0; i < steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 20,
                          child: Text('${i + 1}.',
                              style: TextStyle(color: context.palette.accent, fontWeight: FontWeight.w600)),
                        ),
                        Expanded(child: Muted(steps[i], small: true)),
                      ],
                    ),
                  ),
                const Spacer(),
                const SizedBox(height: 14),
                Gated(
                  reason: g.reason,
                  child: AppButton(
                    label: '开始解锁',
                    kind: ButtonKind.primary,
                    onPressed: g.disabled ? null : () => _unlock(context),
                  ),
                ),
              ],
            ),
            _ActionCard(
              icon: Icons.lock_outline,
              tone: Tone.danger,
              title: '上锁 Bootloader',
              children: [
                const SizedBox(height: 4),
                const Callout(
                  Tone.danger,
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '上锁前系统分区必须是'),
                    TextSpan(text: '完全官方、未经任何修改', style: TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: '的状态。已 Root 或刷过第三方镜像时直接上锁，可能导致无法开机。不确定的话，请先用官方全量包本地升级或平刷一次。'),
                  ])),
                ),
                const Spacer(),
                Gated(
                  reason: g.reason,
                  child: AppButton(
                    label: '开始上锁',
                    kind: ButtonKind.danger,
                    onPressed: g.disabled ? null : () => _relock(context),
                  ),
                ),
              ],
            ),
          ],
        ),
        GateHint(g.hint(tb)),
      ],
    );
  }
}

// ───────────── A/B 槽位 ─────────────

class SlotPage extends StatelessWidget {
  const SlotPage({super.key, required this.tb});

  final ToolboxController tb;

  Future<void> _switch(BuildContext context) async {
    final ok = await confirmAction(
      context,
      const ConfirmSpec(
        title: '切换 A/B 槽位',
        intro: '另一个槽位里的系统可能是旧版本，或者是空的。请确认你清楚自己在做什么。',
        checks: ['我了解切换后可能需要再切回来'],
        confirmText: '切换槽位',
      ),
    );
    if (ok) await tb.start('切换 A/B 槽位', const SwitchSlotRequest());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final g = gate(tb, _anyMode);
    final slot = tb.device.slot?.toUpperCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader('A/B 槽位', '适用于 A/B 分区机型。刷坏一个槽位后，切换到另一个槽位往往能重新开机'),
        AppCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (final s in ['A', 'B']) ...[
                    if (s == 'B') const SizedBox(width: 14),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          color: slot == s ? c.accentSoft : c.surface2,
                          border: Border.all(color: slot == s ? c.accent : c.border, width: slot == s ? 1.5 : 1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Text(s,
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w700,
                                  color: slot == s ? c.accent : c.muted,
                                )),
                            Text(
                              slot == s ? '当前槽位' : (slot != null ? '备用槽位' : '未知'),
                              style: TextStyle(fontSize: 12.5, color: c.muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              const Muted('会先进入 Fastboot 模式，再执行 fastboot --set-active=other。完成后设备停留在 Fastboot。'),
              const SizedBox(height: 16),
              Gated(
                reason: g.reason,
                child: AppButton(
                  label: '切换到另一个槽位',
                  icon: Icons.swap_horiz,
                  kind: ButtonKind.primary,
                  onPressed: g.disabled ? null : () => _switch(context),
                ),
              ),
              GateHint(g.hint(tb)),
            ],
          ),
        ),
      ],
    );
  }
}
