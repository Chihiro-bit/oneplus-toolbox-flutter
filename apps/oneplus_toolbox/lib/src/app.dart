import 'package:flutter/material.dart';
import 'package:toolbox_service/toolbox_service.dart';

import 'controller.dart';
import 'pages/apps_page.dart';
import 'pages/device_pages.dart';
import 'pages/edl_page.dart';
import 'pages/overview_page.dart';
import 'pages/page_id.dart';
import 'pages/root_page.dart';
import 'pages/settings_page.dart';
import 'pages/tools_page.dart';
import 'platform.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/dialogs.dart';
import 'widgets/log_panel.dart';
import 'widgets/run_banner.dart';

class ToolboxApp extends StatelessWidget {
  const ToolboxApp({super.key, required this.controller});

  final ToolboxController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '一加工具箱',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: Shell(tb: controller),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key, required this.tb});

  final ToolboxController tb;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  PageId _page = PageId.overview;
  UpdateInfo? _update;
  final _rootForm = RootForm();
  final _appsForm = AppsForm();
  final _edlForm = EdlForm();
  final _scroll = ScrollController();
  bool _warning = false;

  ToolboxController get tb => widget.tb;

  @override
  void initState() {
    super.initState();
    tb.addListener(_onChange);
    // 配置了更新仓库时，启动后静默检查一次
    if (tb.service.settings.updateRepo.isNotEmpty) {
      tb.service.checkUpdate().then((u) {
        if (u.hasUpdate && mounted) setState(() => _update = u);
      });
    }
  }

  @override
  void dispose() {
    tb.removeListener(_onChange);
    _rootForm.dispose();
    _appsForm.dispose();
    _edlForm.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChange() {
    setState(() {});
    _maybeWarnBrand();
  }

  /// 检测到非一加设备时弹出警告；本次运行中每台设备只警告一次
  Future<void> _maybeWarnBrand() async {
    final d = tb.device;
    final serial = d.serial;
    if (_warning || serial == null || d.isOnePlus != false || tb.acknowledged.contains(serial)) return;
    _warning = true;
    await showBrandWarning(context, d);
    _warning = false;
    tb.acknowledge(serial);
  }

  void _go(PageId page) {
    setState(() => _page = page);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Widget _content() => switch (_page) {
        PageId.overview => OverviewPage(tb: tb, go: _go),
        PageId.reboot => RebootPage(tb: tb),
        PageId.bootloader => BootloaderPage(tb: tb),
        PageId.root => RootPage(tb: tb, form: _rootForm),
        PageId.slot => SlotPage(tb: tb),
        PageId.apps => AppsPage(tb: tb, form: _appsForm),
        PageId.tools => ToolsPage(tb: tb),
        PageId.edl => EdlPage(tb: tb, form: _edlForm),
        PageId.settings => SettingsPage(tb: tb),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Scaffold(
      body: Row(
        children: [
          _Sidebar(page: _page, device: tb.device, update: _update, go: _go),
          VerticalDivider(width: 1, color: c.border),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Scrollbar(
                    controller: _scroll,
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(36, 28, 36, 36),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1080),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              RunBanner(tb),
                              KeyedSubtree(key: ValueKey(_page), child: _content()),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                LogPanel(tb),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.page, required this.device, required this.update, required this.go});

  final PageId page;
  final DeviceInfo device;
  final UpdateInfo? update;
  final Navigate go;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Container(
      width: 232,
      color: c.sidebar,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 18),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.memory, size: 16, color: Colors.white),
                ),
                const SizedBox(width: 10),
                const Text('一加工具箱', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          for (final p in PageId.values.where((p) => p != PageId.settings))
            _NavItem(p, selected: page == p, onTap: () => go(p)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Divider(height: 1, color: c.border),
          ),
          _NavItem(PageId.settings, selected: page == PageId.settings, onTap: () => go(PageId.settings)),
          const Spacer(),
          if (update != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: c.accentSoft,
                borderRadius: BorderRadius.circular(99),
                child: InkWell(
                  borderRadius: BorderRadius.circular(99),
                  onTap: () => openExternal(update!.url!),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.arrow_circle_up_outlined, size: 15, color: c.accent),
                        const SizedBox(width: 6),
                        Text('新版本 ${update!.latest}',
                            style: TextStyle(color: c.accent, fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Material(
            color: c.surface,
            shape: RoundedRectangleBorder(side: BorderSide(color: c.border), borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => go(PageId.overview),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.smartphone, size: 18, color: c.text),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            device.model ?? (device.mode == DeviceMode.none ? '无设备' : device.device ?? '设备'),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(device.mode.label, style: TextStyle(fontSize: 12, color: c.muted)),
                        ],
                      ),
                    ),
                    ModeBadge(device.mode, dotOnly: true),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem(this.page, {required this.selected, required this.onTap});

  final PageId page;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? c.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        elevation: selected ? 0.5 : 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Row(
                  children: [
                    Icon(page.icon, size: 17, color: selected ? c.text : c.muted),
                    const SizedBox(width: 10),
                    Text(
                      page.label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                        color: selected ? c.text : c.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Positioned(
                  left: 0,
                  top: 10,
                  bottom: 10,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
