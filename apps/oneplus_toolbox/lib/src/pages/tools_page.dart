import 'package:flutter/material.dart';
import 'package:toolbox_service/toolbox_service.dart';

import '../controller.dart';
import '../platform.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key, required this.tb});

  final ToolboxController tb;

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  String _playApk = '';

  ToolboxController get tb => widget.tb;

  Future<void> _disableOta() async {
    final ok = await confirmAction(
      context,
      const ConfirmSpec(
        title: '禁用系统更新',
        intro: '禁用后手机不会再收到系统更新推送，只能回到这里恢复。',
        checks: ['我知道禁用后需要用本工具恢复，才能再次接收系统更新'],
        confirmText: '禁用',
      ),
    );
    if (ok) await tb.start('禁用系统更新', const OtaUpdatesRequest(disable: true));
  }

  @override
  Widget build(BuildContext context) {
    final g = gate(tb, {DeviceMode.system});
    final installReason = g.reason ?? (_playApk.isEmpty ? '请先选择 APK' : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader('系统工具', '免 Root 的常用调整，需要手机开机并开启 USB 调试'),
        ResponsiveGrid(
          minItemWidth: 320,
          maxColumns: 2,
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ActionIcon(Icons.shopping_bag_outlined, tone: Tone.info),
                  const SizedBox(height: 14),
                  const Text('安装 Play 商店', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  const Muted('先卸载系统内置 Play 商店的更新，再安装你提供的 APK，最后通过应用商店的详情页触发 Play 商店自身更新。', small: true),
                  const SizedBox(height: 14),
                  PathField(
                    icon: Icons.upload_file_outlined,
                    hint: '选择 Play 商店 APK（com.android.vending）',
                    value: _playApk,
                    onBrowse: () async {
                      final p = await pickApk();
                      if (p != null) setState(() => _playApk = p);
                    },
                  ),
                  const Spacer(),
                  const SizedBox(height: 14),
                  Gated(
                    reason: installReason,
                    child: AppButton(
                      label: '安装',
                      kind: ButtonKind.primary,
                      onPressed:
                          installReason != null ? null : () => tb.start('安装 Play 商店', InstallPlayRequest(_playApk)),
                    ),
                  ),
                ],
              ),
            ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ActionIcon(Icons.notifications_off_outlined, tone: Tone.danger),
                  const SizedBox(height: 14),
                  const Text('禁用 / 恢复系统更新', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  const Muted('停用并卸载（仅对当前用户）系统更新组件，关闭更新提示。适用于 ColorOS、氧 OS、氢 OS。之后需要升级时，在这里恢复即可。', small: true),
                  const Spacer(),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      Gated(
                        reason: g.reason,
                        child: AppButton(
                          label: '禁用系统更新',
                          icon: Icons.notifications_off_outlined,
                          kind: ButtonKind.danger,
                          onPressed: g.disabled ? null : _disableOta,
                        ),
                      ),
                      Gated(
                        reason: g.reason,
                        child: AppButton(
                          label: '恢复系统更新',
                          icon: Icons.notifications_active_outlined,
                          onPressed:
                              g.disabled ? null : () => tb.start('恢复系统更新', const OtaUpdatesRequest(disable: false)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        GateHint(g.hint(tb)),
      ],
    );
  }
}
