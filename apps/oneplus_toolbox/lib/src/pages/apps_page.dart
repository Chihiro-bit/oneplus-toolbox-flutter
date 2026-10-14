import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:toolbox_service/toolbox_service.dart';

import '../controller.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 应用列表和搜索词，页面切走时保留
class AppsForm {
  List<AppEntry>? apps;
  final query = TextEditingController();

  void dispose() => query.dispose();
}

class AppsPage extends StatefulWidget {
  const AppsPage({super.key, required this.tb, required this.form});

  final ToolboxController tb;
  final AppsForm form;

  @override
  State<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends State<AppsPage> {
  String? _pending;

  ToolboxController get tb => widget.tb;
  AppsForm get f => widget.form;

  Future<void> _load() async {
    final r = await tb.start('读取应用列表', const ListAppsRequest());
    if (r.ok && r.apps != null && mounted) setState(() => f.apps = r.apps);
  }

  Future<void> _toggle(AppEntry a) async {
    setState(() => _pending = a.package);
    final r = await tb.start(
      a.cloned ? '移除双开：${a.label}' : '双开：${a.label}',
      CloneAppRequest(a.package, enable: !a.cloned),
    );
    if (!mounted) return;
    setState(() {
      _pending = null;
      if (r.ok) {
        f.apps = [for (final x in f.apps ?? const <AppEntry>[]) x.package == a.package ? x.withCloned(!a.cloned) : x];
      }
    });
  }

  List<AppEntry>? get _shown {
    final q = f.query.text.trim().toLowerCase();
    final apps = f.apps;
    if (apps == null || q.isEmpty) return apps;
    return apps.where((a) => a.label.toLowerCase().contains(q) || a.package.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final g = gate(tb, {DeviceMode.system});
    final shown = _shown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader('应用双开', '利用 ColorOS / 氧 OS 自带的分身空间（用户 999），把任意第三方应用克隆一份'),
        const Callout(Tone.info, text: '首次使用前，需要先在手机「设置 → 应用 → 应用分身」中任意双开一个应用，系统才会创建分身空间。'),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: f.query,
                        enabled: f.apps != null,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(fontSize: 13.5),
                        decoration: InputDecoration(
                          hintText: '搜索应用名或包名',
                          prefixIcon: Icon(Icons.search, size: 17, color: c.muted),
                          suffixIcon: f.query.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: '清空搜索',
                                  iconSize: 15,
                                  onPressed: () => setState(f.query.clear),
                                  icon: const Icon(Icons.close),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Gated(
                      reason: g.reason,
                      child: AppButton(
                        label: f.apps != null ? '刷新' : '读取应用列表',
                        icon: Icons.refresh,
                        onPressed: g.disabled ? null : _load,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: c.border),
              if (shown == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: [
                      Icon(Icons.filter_none, size: 28, color: c.muted),
                      const SizedBox(height: 10),
                      Muted(g.hint(tb) ?? '点击「读取应用列表」，应用较多时需要一分钟左右'),
                    ],
                  ),
                )
              else if (shown.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Muted('没有匹配的应用'))
              else
                ValueListenableBuilder(
                  valueListenable: tb.icons,
                  builder: (context, icons, _) => Column(
                    children: [
                      for (var i = 0; i < shown.length; i++) ...[
                        if (i > 0) Divider(height: 1, indent: 66, color: c.border),
                        _AppRow(
                          app: shown[i],
                          icon: icons[shown[i].package],
                          pending: _pending == shown[i].package,
                          onToggle: g.disabled ? null : () => _toggle(shown[i]),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (f.apps != null) const GateHint('ColorOS 桌面在重启后可能不显示分身应用的图标，这是系统桌面的限制，可改用第三方桌面。'),
      ],
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({required this.app, required this.icon, required this.pending, required this.onToggle});

  final AppEntry app;
  final Uint8List? icon;
  final bool pending;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final avatar = icon != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Image.memory(
              icon!,
              width: 36,
              height: 36,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => _letter(c),
            ),
          )
        : _letter(c);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(app.label, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                Text(app.package, style: TextStyle(fontSize: 12, color: c.muted), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (app.cloned) ...[TagChip('已双开', color: c.ok), const SizedBox(width: 12)],
          AppButton(
            label: pending ? '处理中…' : (app.cloned ? '移除' : '双开'),
            kind: app.cloned ? ButtonKind.ghost : ButtonKind.secondary,
            onPressed: onToggle,
          ),
        ],
      ),
    );
  }

  Widget _letter(Palette c) => Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(9)),
        child: Text(
          app.label.characters.first,
          style: TextStyle(color: c.accent, fontWeight: FontWeight.w600),
        ),
      );
}
