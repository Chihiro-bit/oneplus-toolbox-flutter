import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:toolbox_service/toolbox_service.dart';

import '../controller.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';

/// 四个标签页，对应 TS 版 apps.tsx 的 Tab
enum AppsTab {
  clone('应用双开', '读取应用列表', Icons.copy_all_outlined),
  user('冻结与权限', '读取应用列表', Icons.ac_unit_outlined),
  backup('备份与恢复', '读取应用列表', Icons.archive_outlined),
  system('预装应用', '读取系统应用列表', Icons.inventory_2_outlined);

  const AppsTab(this.label, this.loadTitle, this.icon);

  final String label;

  /// 读取这一页列表时显示的标题
  final String loadTitle;
  final IconData icon;
}

/// 每个标签页各自的列表和搜索词，页面切走时保留
class AppsForm {
  AppsTab tab = AppsTab.clone;

  /// 各标签页的应用列表，null 表示还没读取过
  final lists = <AppsTab, List<AppEntry>>{};

  final query = TextEditingController();

  /// 备份页：同时备份应用数据
  bool withData = false;

  List<AppEntry>? get apps => lists[tab];

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
  /// 正在处理的应用包名（按钮显示「处理中…」）
  String? _pending;

  /// 「冻结与权限」页展开的权限面板
  ({String pkg, List<AppPermission> list})? _perms;

  ToolboxController get tb => widget.tb;
  AppsForm get f => widget.form;

  bool get _rooted => isRooted(tb.device.root);

  // ───────────── 列表与搜索 ─────────────

  Future<void> _load() async {
    final tab = f.tab;
    final r = await tb.start(
        tab.loadTitle,
        switch (tab) {
          AppsTab.clone => const ListAppsRequest(),
          AppsTab.user || AppsTab.backup => const ListUserAppsRequest(),
          AppsTab.system => const ListSystemAppsRequest(),
        });
    if (!mounted || r.apps == null) return;
    setState(() {
      f.lists[tab] = r.apps!;
      _perms = null;
    });
  }

  void _patch(String pkg, AppEntry Function(AppEntry app) change) {
    final apps = f.apps;
    if (apps == null) return;
    f.lists[f.tab] = [for (final a in apps) a.package == pkg ? change(a) : a];
  }

  List<AppEntry>? get _shown {
    final apps = f.apps;
    final q = f.query.text.trim().toLowerCase();
    if (apps == null || q.isEmpty) return apps;
    return [
      for (final a in apps)
        if (a.label.toLowerCase().contains(q) || a.package.toLowerCase().contains(q)) a,
    ];
  }

  // ───────────── 双开 ─────────────

  Future<void> _toggleClone(AppEntry a) async {
    setState(() => _pending = a.package);
    final r = await tb.start(
      a.cloned ? '移除双开：${a.label}' : '双开：${a.label}',
      CloneAppRequest(a.package, enable: !a.cloned),
    );
    if (!mounted) return;
    setState(() {
      _pending = null;
      if (r.ok) _patch(a.package, (x) => x.withCloned(!a.cloned));
    });
  }

  // ───────────── 预装应用：卸载 / 恢复 ─────────────

  Future<void> _toggleSystem(AppEntry a) async {
    Future<void> run() async {
      setState(() => _pending = a.package);
      final r = await tb.start(
        a.removed ? '恢复：${a.label}' : '卸载：${a.label}',
        DebloatRequest(a.package, remove: !a.removed),
      );
      if (!mounted) return;
      setState(() {
        _pending = null;
        if (r.ok) _patch(a.package, (x) => x.copyWith(removed: !a.removed));
      });
    }

    if (a.removed) return run();
    final ok = await confirmAction(
      context,
      ConfirmSpec(
        title: '卸载 ${a.label}',
        intro: '对当前用户卸载 ${a.package}（pm uninstall --user 0）。'
            'APK 仍保留在系统分区，随时可以在这里恢复，恢复出厂设置也会让它回来。'
            '卸掉其它应用依赖的组件，可能导致相关功能失灵甚至反复崩溃。',
        checks: ['我确认知道这个应用是做什么的，卸载它不会影响我需要的功能'],
        confirmText: '卸载',
      ),
    );
    if (ok) await run();
  }

  // ───────────── 冻结 / 解冻 ─────────────

  Future<void> _toggleFreeze(AppEntry a) async {
    Future<void> run() async {
      setState(() => _pending = a.package);
      final r = await tb.start(
        a.disabled ? '解冻：${a.label}' : '冻结：${a.label}',
        FreezeAppRequest(a.package, freeze: !a.disabled),
      );
      if (!mounted) return;
      setState(() {
        _pending = null;
        if (r.ok) _patch(a.package, (x) => x.copyWith(disabled: !a.disabled));
      });
    }

    // 第三方应用冻结了也不影响系统；预装应用可能被别的功能依赖，先确认
    if (a.disabled || !a.system) return run();
    final ok = await confirmAction(
      context,
      ConfirmSpec(
        title: '冻结 ${a.label}',
        intro: '停用 ${a.package}（pm disable-user），应用和数据都保留，随时可以在这里解冻。'
            '冻结其它功能依赖的预装组件，可能导致相关功能失灵。',
        checks: ['我确认知道这个应用是做什么的，冻结它不会影响我需要的功能'],
        confirmText: '冻结',
      ),
    );
    if (ok) await run();
  }

  // ───────────── 权限 ─────────────

  Future<void> _togglePerms(AppEntry a) async {
    if (_perms?.pkg == a.package) {
      setState(() => _perms = null);
      return;
    }
    final r = await tb.start('读取 ${a.label} 的权限', AppPermissionsRequest(a.package));
    if (!mounted || r.permissions == null) return;
    setState(() => _perms = (pkg: a.package, list: r.permissions!));
  }

  Future<void> _grant(String pkg, AppPermission p) async {
    final r = await tb.start(
      '${p.granted ? '撤销' : '授予'}「${p.label}」',
      GrantPermissionRequest(pkg, permission: p.name, grant: !p.granted),
    );
    if (!mounted || r.permissions == null) return;
    setState(() => _perms = (pkg: pkg, list: r.permissions!));
  }

  // ───────────── 备份 / 恢复 ─────────────

  Future<void> _backup(AppEntry a) async {
    setState(() => _pending = a.package);
    await tb.start(
      '备份：${a.label}',
      BackupAppRequest(package: a.package, label: a.label, withData: f.withData && _rooted),
    );
    if (mounted) setState(() => _pending = null);
  }

  Future<void> _restore() async {
    final dir = await pickDir();
    if (!mounted || dir == null) return;
    final ok = await confirmAction(
      context,
      const ConfirmSpec(
        title: '从备份恢复应用',
        intro: '先安装备份里的安装包；备份里有应用数据、手机也已 Root 时，会清空这个应用在手机上现有的数据，换成备份里的。'
            '只恢复工具箱备份出来的文件夹。',
        checks: ['我知道手机上这个应用现有的数据会被备份覆盖'],
        confirmText: '恢复',
      ),
    );
    if (ok) await tb.start('恢复应用', RestoreAppRequest(dir));
  }

  // ───────────── 界面 ─────────────

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final g = gate(tb, {DeviceMode.system});
    final shown = _shown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader('应用管理', '应用双开、冻结不常用的应用、一键授予 adb 权限、备份应用（Root 后可含数据），或者卸载用不到的预装应用'),
        _tabs(),
        ..._callouts(),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _toolbar(g),
              if (f.tab == AppsTab.backup) _backupBar(g),
              Divider(height: 1, color: c.border),
              if (shown == null)
                _empty(g)
              else if (shown.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Muted('没有匹配的应用'))
              else
                ValueListenableBuilder(
                  valueListenable: tb.icons,
                  builder: (context, icons, _) => Column(
                    children: [
                      for (var i = 0; i < shown.length; i++) ...[
                        if (i > 0) Divider(height: 1, indent: 66, color: c.border),
                        _appRow(shown[i], icons[shown[i].package], g),
                        if (f.tab == AppsTab.user && _perms?.pkg == shown[i].package) _permPanel(_perms!, g),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (f.tab == AppsTab.clone && shown != null)
          const GateHint('ColorOS 桌面在重启后可能不显示分身应用的图标，这是系统桌面的限制，可改用第三方桌面。')
        else
          GateHint(g.hint(tb)),
      ],
    );
  }

  Widget _tabs() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SizedBox(
        width: double.infinity,
        child: Segmented<AppsTab>(
          value: f.tab,
          options: [for (final t in AppsTab.values) (t, t.label)],
          onChanged: (t) => setState(() {
            f.tab = t;
            _perms = null;
          }),
        ),
      ),
    );
  }

  Widget _toolbar(Gate g) {
    final c = context.palette;
    return Padding(
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
    );
  }

  Widget _backupBar(Gate g) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: _rooted ? '' : '需要 Root，这台手机当前是「${tb.device.root ?? '未知'}」',
              child: CheckRow(
                value: f.withData && _rooted,
                label: '同时备份应用数据${_rooted ? '（备份前会先停止应用）' : '（需要 Root）'}',
                onChanged: _rooted ? (v) => setState(() => f.withData = v) : null,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Gated(
            reason: g.reason,
            child: AppButton(
              label: '从备份恢复…',
              icon: Icons.settings_backup_restore,
              onPressed: g.disabled ? null : _restore,
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(Gate g) {
    final c = context.palette;
    // 有操作在进行时只显示提示语：横幅已经说明「正在做什么」，再显示原因会重复
    final message = g.disabled && !tb.run.running
        ? g.reason
        : f.tab == AppsTab.system
            ? '点击「读取应用列表」，系统应用有几百个，需要一两分钟'
            : '点击「读取应用列表」，应用较多时需要一分钟左右';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(f.tab.icon, size: 28, color: c.muted),
          const SizedBox(height: 10),
          Muted(message!),
        ],
      ),
    );
  }

  Widget _appRow(AppEntry a, Uint8List? icon, Gate g) {
    final c = context.palette;
    final pending = _pending == a.package;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _avatar(a, icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.label, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                Text(a.package, style: TextStyle(fontSize: 12, color: c.muted), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          ..._chips(a),
          ..._actions(a, g, pending),
        ],
      ),
    );
  }

  List<Widget> _chips(AppEntry a) => switch (f.tab) {
        AppsTab.clone => [if (a.cloned) TagChip('已双开', color: context.palette.ok)],
        AppsTab.user || AppsTab.backup => [if (a.disabled && !a.removed) const TagChip('已冻结')],
        AppsTab.system => [
            if (a.removed) const TagChip('已卸载'),
            if (a.protected) const TagChip('系统必需'),
          ],
      };

  List<Widget> _actions(AppEntry a, Gate g, bool pending) {
    final disabled = g.disabled;
    final freeze = Gated(
      reason: a.protected && !a.disabled ? '系统运行必需的组件，不允许冻结' : g.reason,
      child: AppButton(
        label: pending ? '处理中…' : (a.disabled ? '解冻' : '冻结'),
        kind: a.disabled ? ButtonKind.secondary : ButtonKind.ghost,
        onPressed: disabled || (a.protected && !a.disabled) ? null : () => _toggleFreeze(a),
      ),
    );
    return switch (f.tab) {
      AppsTab.clone => [
          const SizedBox(width: 12),
          AppButton(
            label: pending ? '处理中…' : (a.cloned ? '移除' : '双开'),
            kind: a.cloned ? ButtonKind.ghost : ButtonKind.secondary,
            onPressed: disabled ? null : () => _toggleClone(a),
          ),
        ],
      AppsTab.user => [
          const SizedBox(width: 12),
          AppButton(
            label: '权限',
            icon: Icons.key_outlined,
            kind: _perms?.pkg == a.package ? ButtonKind.secondary : ButtonKind.ghost,
            onPressed: disabled ? null : () => _togglePerms(a),
          ),
          const SizedBox(width: 8),
          freeze,
        ],
      AppsTab.backup => [
          const SizedBox(width: 12),
          AppButton(
            label: pending ? '备份中…' : '备份',
            icon: Icons.archive_outlined,
            onPressed: disabled ? null : () => _backup(a),
          ),
        ],
      AppsTab.system => [
          const SizedBox(width: 12),
          if (!a.removed) freeze,
          if (!a.removed) const SizedBox(width: 8),
          Gated(
            reason: a.protected && !a.removed ? '系统运行必需的组件，不允许卸载' : g.reason,
            child: AppButton(
              label: pending ? '处理中…' : (a.removed ? '恢复' : '卸载'),
              kind: a.removed ? ButtonKind.secondary : ButtonKind.ghost,
              onPressed: disabled || (a.protected && !a.removed) ? null : () => _toggleSystem(a),
            ),
          ),
        ],
    };
  }

  Widget _avatar(AppEntry a, Uint8List? icon) {
    final c = context.palette;
    if (icon != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Image.memory(
          icon,
          width: 36,
          height: 36,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _letter(c, a),
        ),
      );
    }
    return _letter(c, a);
  }

  Widget _letter(Palette c, AppEntry a) => Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(9)),
        child: Text(
          a.label.characters.first,
          style: TextStyle(color: c.accent, fontWeight: FontWeight.w600),
        ),
      );

  Widget _permPanel(({String pkg, List<AppPermission> list}) perms, Gate g) {
    final c = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(66, 4, 16, 14),
      color: c.surface2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (perms.list.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Muted('这个应用没有申请需要用 adb 授予的权限。它要的如果是悬浮窗、无障碍、通知使用权等，请在手机设置里打开。', small: true),
            ),
          for (final p in perms.list)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Tooltip(
                          message: p.name,
                          child: Muted(p.desc, small: true),
                        ),
                      ],
                    ),
                  ),
                  if (p.granted) ...[TagChip('已授予', color: c.ok), const SizedBox(width: 10)],
                  Gated(
                    reason: g.reason,
                    child: AppButton(
                      label: p.granted ? '撤销' : '授予',
                      kind: p.granted ? ButtonKind.ghost : ButtonKind.primary,
                      onPressed: g.disabled ? null : () => _grant(perms.pkg, p),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _callouts() => switch (f.tab) {
        AppsTab.clone => const [
            Callout(Tone.info,
                text: '利用 ColorOS / 氧 OS 自带的分身空间（用户 999）。'
                    '首次使用前，需要先在手机「设置 → 应用 → 应用分身」中任意双开一个应用，系统才会创建分身空间。'),
          ],
        AppsTab.user => const [
            Callout(Tone.info,
                text: '冻结：应用和数据都保留，只是不能运行、图标从桌面消失，随时可以解冻。'
                    '权限：自动化、按键映射、手势类应用常要求「用电脑执行 adb 命令授权」，点「权限」就能看到它申请了哪些、一键授予。'),
          ],
        AppsTab.backup => const [
            Callout(Tone.info,
                text: '把应用的安装包备份到「文档\\一加工具箱\\应用备份」，有分包时打成 .apks，也能直接拖进「系统工具 → 安装应用」装回去。'
                    '手机已 Root 时可以连同应用数据（聊天记录、设置、存档等，不含缓存和 Android/data 里的文件）一起备份。'
                    '换手机恢复后，部分应用的登录状态会失效，需要重新登录。'),
          ],
        AppsTab.system => const [
            Callout(Tone.warn,
                text: '卸载和冻结都只针对当前用户，不需要 Root，随时可以恢复。'
                    '但工具箱不知道哪些预装应用停掉后会影响其它功能，请只处理你确认用不到的。'
                    '开机、解锁、权限管理等必需组件已被锁定，不能卸载或冻结。'),
          ],
      };
}
