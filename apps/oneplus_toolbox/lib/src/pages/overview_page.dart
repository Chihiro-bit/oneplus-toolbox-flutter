import 'package:flutter/material.dart';
import 'package:toolbox_service/toolbox_service.dart';

import '../controller.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'page_id.dart';

class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key, required this.tb, required this.go});

  final ToolboxController tb;
  final Navigate go;

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  /// 「检查驱动」的结果；没查过时为 null
  List<DriverEntry>? _drivers;

  ToolboxController get tb => widget.tb;

  Future<void> _checkDrivers() async {
    final r = await tb.start('检查驱动', const DriverCheckRequest());
    if (mounted) setState(() => _drivers = r.drivers);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final d = tb.device;
    final rows = <(String, String?)>[
      ('设备代号', d.device),
      ('品牌', d.brand),
      ('Android 版本', d.androidVersion),
      ('系统版本', d.romVersion),
      ('构建号', d.buildId),
      ('当前槽位', d.slot?.toUpperCase()),
      ('Bootloader', d.unlocked == null ? null : (d.unlocked! ? '已解锁' : '已锁定')),
      ('Root', d.root),
      ('序列号', d.serial),
    ].where((r) => r.$2 != null && r.$2!.isNotEmpty).toList();
    final connected = d.mode != DeviceMode.none && d.mode != DeviceMode.unauthorized;
    // 与 TS 版的 `d.brand || d.manufacturer` 一致：品牌读不到时用厂商
    final brand = (d.brand?.isNotEmpty ?? false) ? d.brand! : (d.manufacturer ?? '');
    final drivers = _drivers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader('概览', '连接手机后，这里会实时显示设备状态'),
        if (d.isOnePlus == false)
          Callout(
            Tone.danger,
            text: '当前设备是 $brand，不是一加手机。本工具只在一加手机上验证过，在其它品牌上解锁、Root 或刷写可能导致变砖。',
          ),
        AppCard(
          padding: const EdgeInsets.all(24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.smartphone, size: 30, color: c.accent),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          d.model ?? (d.mode == DeviceMode.none ? '等待设备连接' : d.device ?? '未知设备'),
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
                        ),
                        ModeBadge(d.mode),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (d.mode == DeviceMode.none) const Muted('用数据线连接手机，并在「开发者选项」中打开「USB 调试」。如果一直检测不到，请先安装 USB 驱动。'),
                    if (d.mode == DeviceMode.unauthorized) const Muted('手机上弹出了 USB 调试授权窗口，请勾选「始终允许」并点击「允许」。'),
                    if (d.needsPick) Muted('连接了多台设备。为避免误操作，请先在左下角选择要操作的那一台。', color: c.warn),
                    if (d.mode == DeviceMode.edl && !Features.edl)
                      const Muted('手机处于 9008 模式。工具箱的 9008 功能暂时停用；退出方法：长按 音量上 + 电源键直到重启。'),
                    if (connected) _Props(rows),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (d.mode == DeviceMode.none) ...[
          const SizedBox(height: 14),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.usb, size: 18, color: c.muted),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('检测不到设备？', style: TextStyle(fontWeight: FontWeight.w600)),
                      Muted('安装 Google USB 驱动，或换一根支持数据传输的线、换一个 USB 口', small: true),
                    ],
                  ),
                ),
                AppButton(
                  label: '检查驱动',
                  onPressed: tb.run.running ? null : _checkDrivers,
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: '驱动下载',
                  kind: ButtonKind.ghost,
                  onPressed: () => openExternal('https://developer.android.com/studio/run/win-usb'),
                ),
              ],
            ),
          ),
        ],
        if (d.mode == DeviceMode.none && drivers != null && drivers.isNotEmpty) ...[
          const SizedBox(height: 14),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CardTitle('设备管理器里的手机'),
                for (final x in drivers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(x.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          x.problem ?? '驱动正常',
                          style: TextStyle(fontSize: 12.5, color: x.ok ? c.ok : c.danger),
                        ),
                        if (x.hint != null) Muted(x.hint!, small: true),
                        const SizedBox(height: 3),
                        Code(x.instanceId),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 28),
        Text('常用功能', style: TextStyle(fontWeight: FontWeight.w600, color: c.muted, fontSize: 13)),
        const SizedBox(height: 12),
        ResponsiveGrid(
          minItemWidth: 300,
          maxColumns: 2,
          gap: 12,
          children: [
            _Tile(Icons.power_settings_new, '重启与模式', '系统 / Recovery / Fastboot${Features.edl ? ' / EDL' : ''}',
                () => widget.go(PageId.reboot)),
            _Tile(Icons.lock_open_outlined, '解锁 Bootloader', 'Root 的前置步骤', () => widget.go(PageId.bootloader)),
            _Tile(Icons.auto_awesome_outlined, '一键 Root', 'Magisk / APatch / KernelSU 等 6 种方案',
                () => widget.go(PageId.root)),
            _Tile(Icons.monitor_heart_outlined, '开机诊断', '卡开机时找原因、给修复办法', () => widget.go(PageId.diagnose)),
            _Tile(Icons.health_and_safety_outlined, '救援与恢复', '卸载 Root、撤销刷写、模块导致卡开机', () => widget.go(PageId.rescue)),
            _Tile(Icons.swap_horiz, 'A/B 槽位切换', '变砖时的自救手段', () => widget.go(PageId.slot)),
            if (Features.edl) _Tile(Icons.healing_outlined, '9008 救砖', '高通 EDL 深刷（需自备散包）', () => widget.go(PageId.edl)),
            _Tile(Icons.content_copy_outlined, '应用管理', '应用双开、卸载预装应用', () => widget.go(PageId.apps)),
            _Tile(Icons.build_outlined, '系统工具', '安装应用、Play 商店、禁用系统更新', () => widget.go(PageId.tools)),
          ],
        ),
      ],
    );
  }
}

class _Props extends StatelessWidget {
  const _Props(this.rows);

  final List<(String, String?)> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return LayoutBuilder(builder: (context, box) {
      final w = (box.maxWidth - 32) / 3;
      return Wrap(
        spacing: 16,
        runSpacing: 14,
        children: [
          for (final (k, v) in rows)
            SizedBox(
              width: w < 140 ? box.maxWidth : w,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(k, style: TextStyle(fontSize: 12.5, color: c.muted)),
                  const SizedBox(height: 2),
                  SelectableText(v!, style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      );
    });
  }
}

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
