import 'package:flutter/material.dart';
import 'package:toolbox_service/toolbox_service.dart';

import '../controller.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/drop_zone.dart';
import '../widgets/media_cards.dart';

/// 系统工具页。对应 TS 版 src/renderer/src/tools.tsx：
/// 安装应用（拖拽 / 批量）、安装 Play 商店、禁用 / 恢复系统更新、Shizuku、联网修复与私人 DNS、安装 Root 模块，
/// 以及投屏截图、文件传输、无线调试三个卡片（在 widgets/media_cards.dart 里）。
const _installExtensions = ['apk', 'apks', 'xapk', 'aab'];

bool _isInstallable(String path) => _installExtensions.contains(path.split('.').last.toLowerCase());

/// 只显示文件名，完整路径放在 title 里
String _fileName(String path) => path.split(RegExp(r'[\\/]')).last;

/// 私人 DNS 模式的中文名
String _dnsModeLabel(PrivateDnsMode mode) => switch (mode) {
      PrivateDnsMode.off => '已关闭',
      PrivateDnsMode.opportunistic => '自动',
      PrivateDnsMode.hostname => '指定服务器',
    };

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key, required this.tb});

  final ToolboxController tb;

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  final _installFiles = <String>[];
  final _moduleFiles = <String>[];

  /// 上一次添加文件时被忽略的数量（后缀不支持）
  int _skipped = 0;
  String _playApk = '';

  ToolboxController get tb => widget.tb;

  void _addInstallFiles(List<String> paths) {
    final ok = [
      for (final p in paths)
        if (_isInstallable(p)) p
    ];
    setState(() {
      _skipped = paths.length - ok.length;
      for (final p in ok) {
        if (!_installFiles.contains(p)) _installFiles.add(p);
      }
    });
  }

  void _addModuleFiles(List<String> paths) {
    setState(() {
      for (final p in paths) {
        if (p.toLowerCase().endsWith('.zip') && !_moduleFiles.contains(p)) _moduleFiles.add(p);
      }
    });
  }

  Future<void> _install() async {
    final r = await tb.start(
      _installFiles.length == 1 ? '安装 ${_fileName(_installFiles.first)}' : '安装 ${_installFiles.length} 个应用',
      InstallAppsRequest(List.of(_installFiles)),
    );
    if (r.ok && mounted) setState(_installFiles.clear);
  }

  Future<void> _installModules() async {
    final r = await tb.start(
      _moduleFiles.length == 1 ? '安装模块 ${_fileName(_moduleFiles.first)}' : '安装 ${_moduleFiles.length} 个模块',
      InstallModulesRequest(List.of(_moduleFiles)),
    );
    if (r.ok && mounted) setState(_moduleFiles.clear);
  }

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
    final c = context.palette;
    final g = gate(tb, {DeviceMode.system});
    final installReason = g.reason ?? (_installFiles.isEmpty ? '请先添加文件' : null);
    final playReason = g.reason ?? (_playApk.isEmpty ? '请先选择 APK' : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader('系统工具', '安装应用和 Root 模块、投屏截图、文件传输、联网修复等常用调整，需要手机开机并开启 USB 调试'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('安装应用', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                  if (_installFiles.isNotEmpty)
                    AppButton(
                      label: '清空',
                      kind: ButtonKind.ghost,
                      onPressed: tb.run.running ? null : () => setState(_installFiles.clear),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              DropZone(
                enable: !tb.run.running,
                onFiles: _addInstallFiles,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
                  child: Column(
                    children: [
                      Icon(Icons.library_add_outlined, size: 26, color: c.muted),
                      const SizedBox(height: 10),
                      Text.rich(
                        TextSpan(children: [
                          const TextSpan(text: '把 '),
                          TextSpan(text: '.apk', style: _codeStyle(c)),
                          const TextSpan(text: ' / '),
                          TextSpan(text: '.apks', style: _codeStyle(c)),
                          const TextSpan(text: ' / '),
                          TextSpan(text: '.xapk', style: _codeStyle(c)),
                          const TextSpan(text: ' / '),
                          TextSpan(text: '.aab', style: _codeStyle(c)),
                          const TextSpan(text: ' 拖到这里，可以一次拖多个'),
                        ]),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13.5, color: c.muted),
                      ),
                      const SizedBox(height: 14),
                      AppButton(
                        label: '选择文件…',
                        onPressed: () async => _addInstallFiles(await pickFiles(_installExtensions)),
                      ),
                    ],
                  ),
                ),
              ),
              if (_skipped > 0) ...[
                const SizedBox(height: 10),
                Text('已忽略 $_skipped 个不支持的文件', style: TextStyle(fontSize: 12.5, color: c.danger)),
              ],
              if (_installFiles.isNotEmpty) ...[
                const SizedBox(height: 12),
                _FileList(
                  files: _installFiles,
                  icon: Icons.inventory_2_outlined,
                  busy: tb.run.running,
                  withSplitChip: true,
                  onRemove: (f) => setState(() => _installFiles.remove(f)),
                ),
              ],
              const SizedBox(height: 12),
              const Muted(
                '.aab 会按当前手机的配置转换成分包 APK（使用内置 Java 运行时，无需自己安装）；'
                '转换后使用调试密钥签名，不能覆盖从应用商店安装的同一应用。',
                small: true,
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Gated(
                    reason: installReason,
                    child: AppButton(
                      label: '安装${_installFiles.length > 1 ? '（${_installFiles.length} 个）' : ''}',
                      icon: Icons.library_add_outlined,
                      kind: ButtonKind.primary,
                      onPressed: installReason != null ? null : _install,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Muted('覆盖安装时保留应用数据。分包会按手机的 CPU 架构挑选需要的部分，用 adb install-multiple 装成一个应用', small: true),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ResponsiveGrid(
          minItemWidth: 320,
          maxColumns: 2,
          children: [
            MirrorCard(tb: tb, gate: g),
            _ShizukuCard(tb: tb, gate: g),
            _NetworkCard(tb: tb, gate: g),
            _ModuleCard(
              tb: tb,
              gate: g,
              files: _moduleFiles,
              onFiles: _addModuleFiles,
              onRemove: (f) => setState(() => _moduleFiles.remove(f)),
              onInstall: _installModules,
            ),
            _ActionCard(
              icon: Icons.shopping_bag_outlined,
              tone: Tone.info,
              title: '安装 Play 商店',
              children: [
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
                  reason: playReason,
                  child: AppButton(
                    label: '安装',
                    kind: ButtonKind.primary,
                    onPressed: playReason != null ? null : () => tb.start('安装 Play 商店', InstallPlayRequest(_playApk)),
                  ),
                ),
              ],
            ),
            _ActionCard(
              icon: Icons.notifications_off_outlined,
              tone: Tone.danger,
              title: '禁用 / 恢复系统更新',
              children: [
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
          ],
        ),
        const SizedBox(height: 14),
        FilesCard(tb: tb, gate: g),
        const SizedBox(height: 14),
        WirelessCard(tb: tb),
        GateHint(g.hint(tb)),
      ],
    );
  }
}

TextStyle _codeStyle(Palette c) => TextStyle(fontFamily: 'Consolas', fontSize: 12.5, color: c.text);

/// 操作卡片：图标、标题、说明、按钮（与 device_pages.dart 里的同名控件一致）
class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.icon, required this.title, required this.children, this.tone, this.chip});

  final IconData icon;
  final Tone? tone;
  final String title;
  final Widget? chip;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ActionIcon(icon, tone: tone),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
              if (chip != null) chip!,
            ],
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}

/// 已选文件列表
class _FileList extends StatelessWidget {
  const _FileList({
    required this.files,
    required this.icon,
    required this.busy,
    required this.onRemove,
    this.withSplitChip = false,
  });

  final List<String> files;
  final IconData icon;
  final bool busy;
  final ValueChanged<String> onRemove;

  /// 不是单个 .apk 时标出「分包」（.apks / .xapk）或「AAB」
  final bool withSplitChip;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Column(
      children: [
        for (final f in files)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(icon, size: 14, color: c.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Tooltip(
                    message: f,
                    child: Text(_fileName(f), style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                  ),
                ),
                if (withSplitChip && !f.toLowerCase().endsWith('.apk')) ...[
                  const SizedBox(width: 8),
                  TagChip(f.toLowerCase().endsWith('.aab') ? 'AAB' : '分包'),
                ],
                IconButton(
                  tooltip: '移除',
                  iconSize: 13,
                  icon: const Icon(Icons.close),
                  onPressed: busy ? null : () => onRemove(f),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ───────────── Shizuku ─────────────

class _ShizukuCard extends StatefulWidget {
  const _ShizukuCard({required this.tb, required this.gate});

  final ToolboxController tb;
  final Gate gate;

  @override
  State<_ShizukuCard> createState() => _ShizukuCardState();
}

class _ShizukuCardState extends State<_ShizukuCard> {
  ShizukuState? _state;

  Future<void> _run(ShizukuAction action) async {
    final r = await widget.tb.start(
      action == ShizukuAction.start ? '启动 Shizuku' : '检查 Shizuku 状态',
      ShizukuRequest(action),
    );
    if (r.shizuku != null && mounted) setState(() => _state = r.shizuku);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final g = widget.gate;
    final s = _state;
    final autostartReason = g.reason ?? (s?.installed == false ? '请先安装并启动 Shizuku' : null);
    final chipText = s == null
        ? null
        : '${!s.installed ? '未安装' : s.running ? '运行中' : '未运行'}${s.installed && s.version != null ? ' · ${s.version}' : ''}';

    return _ActionCard(
      icon: Icons.bolt_outlined,
      tone: Tone.info,
      title: 'Shizuku',
      chip: chipText == null ? null : TagChip(chipText, color: s!.running ? c.ok : null),
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Muted('让其它应用免 Root 调用系统接口（如冰箱、App Ops、黑阈）。手机上没装时会先从', small: true),
            LinkButton('官方发布页', onTap: () => openExternal(shizuku.homepage)),
            Muted('下载 ${shizuku.version} 并校验 sha256。免 Root 启动在手机重启后会失效，需要重新启动一次。', small: true),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            Gated(
              reason: g.reason,
              child: AppButton(
                label: s != null && !s.installed ? '安装并启动' : '启动 Shizuku',
                icon: Icons.bolt_outlined,
                kind: ButtonKind.primary,
                onPressed: g.disabled ? null : () => _run(ShizukuAction.start),
              ),
            ),
            Gated(
              reason: g.reason,
              child: AppButton(
                label: '检查状态',
                icon: Icons.refresh,
                onPressed: g.disabled ? null : () => _run(ShizukuAction.status),
              ),
            ),
            Gated(
              reason: autostartReason,
              child: AppButton(
                label: '开机自启',
                icon: Icons.power_settings_new,
                onPressed: autostartReason != null ? null : () => _run(ShizukuAction.autostart),
              ),
            ),
          ],
        ),
        if (s != null && s.installed && s.sdk != null) ...[
          const SizedBox(height: 12),
          _Req(ok: s.sdk! >= 33, text: 'Android 13 及以上（免 Root 开机自启的前提）'),
          _Req(ok: s.secureSettings == true, text: '已授予「修改安全系统设置」'),
          _Req(ok: s.bootReceiver == true, text: '开机启动没有被关掉'),
          const SizedBox(height: 6),
          const Muted('另外需要在手机上：用 Shizuku 的「通过无线调试启动」配对并启动一次；在系统设置里允许 Shizuku 自启动', small: true),
        ],
      ],
    );
  }
}

class _Req extends StatelessWidget {
  const _Req({required this.ok, required this.text});

  final bool ok;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ok ? Icons.check : Icons.close, size: 13, color: ok ? c.ok : c.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12.5, color: ok ? c.ok : c.muted, height: 1.5)),
          ),
        ],
      ),
    );
  }
}

// ───────────── 联网修复与私人 DNS ─────────────

class _NetworkCard extends StatefulWidget {
  const _NetworkCard({required this.tb, required this.gate});

  final ToolboxController tb;
  final Gate gate;

  @override
  State<_NetworkCard> createState() => _NetworkCardState();
}

class _NetworkCardState extends State<_NetworkCard> {
  NetworkState? _state;
  final _host = TextEditingController(text: dnsPresets.first.host);

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  Future<void> _run(String title, NetworkRequest request) async {
    final r = await widget.tb.start(title, NetworkOpRequest(request));
    if (r.network != null && mounted) setState(() => _state = r.network);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final g = widget.gate;
    final s = _state;
    final host = _host.text.trim();
    final hostOk = validDnsHost(host);
    final dnsText = s == null ? '' : '：${_dnsModeLabel(s.dnsMode)}${s.dnsHost != null ? '（${s.dnsHost}）' : ''}';

    return _ActionCard(
      icon: Icons.wifi_outlined,
      tone: Tone.info,
      title: '联网修复与私人 DNS',
      chip: s == null
          ? null
          : TagChip(
              s.captive == CaptiveState.cn
                  ? '检测地址已修复'
                  : s.captive == CaptiveState.custom
                      ? '检测地址已自定义'
                      : '默认检测地址',
              color: s.captive == CaptiveState.cn ? c.ok : null,
            ),
      children: [
        const Muted('Wi-Fi 显示感叹号、提示「已连接但无法访问互联网」，通常是系统的联网检测访问不到 Google。改成国内地址后重连 Wi-Fi 即可，不需要 Root。', small: true),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            Gated(
              reason: g.reason,
              child: AppButton(
                label: '修复感叹号',
                icon: Icons.wifi_outlined,
                kind: ButtonKind.primary,
                onPressed: g.disabled ? null : () => _run('修复联网检测', const NetworkCaptiveRequest(fix: true)),
              ),
            ),
            Gated(
              reason: g.reason,
              child: AppButton(
                label: '恢复默认',
                onPressed: g.disabled ? null : () => _run('恢复默认联网检测', const NetworkCaptiveRequest(fix: false)),
              ),
            ),
            Gated(
              reason: g.reason,
              child: AppButton(
                label: '读取',
                icon: Icons.refresh,
                kind: ButtonKind.ghost,
                onPressed: g.disabled ? null : () => _run('读取网络设置', const NetworkStatusRequest()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Muted('私人 DNS$dnsText', small: true),
        const SizedBox(height: 8),
        TextField(
          controller: _host,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: 13.5),
          decoration: InputDecoration(
            hintText: 'DNS 服务器主机名',
            prefixIcon: Icon(Icons.public, size: 17, color: c.muted),
            prefixIconConstraints: const BoxConstraints(minWidth: 38),
            errorText: host.isNotEmpty && !hostOk ? '请填写主机名，例如 dns.alidns.com' : null,
          ),
        ),
        const SizedBox(height: 6),
        // TS 版是 input 的 datalist，Flutter 里用几个预设按钮代替
        Wrap(
          spacing: 4,
          children: [
            for (final p in dnsPresets)
              TextButton(
                onPressed: () => setState(() => _host.text = p.host),
                child: Text('${p.label}（${p.host}）', style: const TextStyle(fontSize: 12)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            Gated(
              reason: g.reason ?? (!hostOk ? '请填写主机名，例如 dns.alidns.com' : null),
              child: AppButton(
                label: '使用这个服务器',
                onPressed: g.disabled || !hostOk
                    ? null
                    : () => _run('设置私人 DNS：$host', NetworkDnsRequest(mode: PrivateDnsMode.hostname, host: host)),
              ),
            ),
            Gated(
              reason: g.reason,
              child: AppButton(
                label: '改回自动',
                kind: ButtonKind.ghost,
                onPressed: g.disabled
                    ? null
                    : () => _run('私人 DNS 改回自动', const NetworkDnsRequest(mode: PrivateDnsMode.opportunistic)),
              ),
            ),
            Gated(
              reason: g.reason,
              child: AppButton(
                label: '关闭',
                kind: ButtonKind.ghost,
                onPressed:
                    g.disabled ? null : () => _run('关闭私人 DNS', const NetworkDnsRequest(mode: PrivateDnsMode.off)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ───────────── 安装 Root 模块 ─────────────

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.tb,
    required this.gate,
    required this.files,
    required this.onFiles,
    required this.onRemove,
    required this.onInstall,
  });

  final ToolboxController tb;
  final Gate gate;
  final List<String> files;
  final ValueChanged<List<String>> onFiles;
  final ValueChanged<String> onRemove;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final rooted = isRooted(tb.device.root);
    final reason = gate.reason ??
        (!rooted
            ? '需要 Root，这台手机当前是「${tb.device.root ?? '未知'}」'
            : files.isEmpty
                ? '请先添加模块'
                : null);

    return _ActionCard(
      icon: Icons.extension_outlined,
      tone: Tone.info,
      title: '安装 Root 模块',
      children: [
        const Muted('把模块 .zip 拖到这里，按手机上的 Root 方案调用 Magisk / KernelSU / APatch 自己的安装命令，不用先传到手机上。装完重启生效。', small: true),
        const SizedBox(height: 14),
        DropZone(
          enable: !tb.run.running,
          radius: 10,
          onFiles: onFiles,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Center(
              child: AppButton(label: '选择模块…', onPressed: () async => onFiles(await pickFiles(['zip']))),
            ),
          ),
        ),
        if (files.isNotEmpty) ...[
          const SizedBox(height: 12),
          _FileList(
            files: files,
            icon: Icons.extension_outlined,
            busy: tb.run.running,
            onRemove: onRemove,
          ),
        ],
        const Spacer(),
        const SizedBox(height: 14),
        Gated(
          reason: reason,
          child: AppButton(
            label: '安装${files.length > 1 ? '（${files.length} 个）' : ''}',
            icon: Icons.extension_outlined,
            kind: ButtonKind.primary,
            onPressed: reason != null ? null : onInstall,
          ),
        ),
      ],
    );
  }
}
