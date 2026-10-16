import 'package:flutter/material.dart';
import 'package:toolbox_service/toolbox_service.dart';

import '../controller.dart';
import '../mirror_actions.dart';
import '../platform.dart';
import '../theme.dart';
import 'common.dart';
import 'drop_zone.dart';

/// 对应 TS 版 src/renderer/src/media.tsx 的三个卡片：
/// 投屏与截图（[MirrorCard]）、无线调试（[WirelessCard]）、文件传输（[FilesCard]）。

/// 手机上可以浏览的根目录
const _remoteRoot = '/sdcard';

/// 文件大小，与 TS 版 media.tsx 的 size() 一致
String _size(int n) {
  if (n < 1024) return '$n B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
  if (n < 1024 * 1024 * 1024) return '${(n / 1048576).toStringAsFixed(1)} MB';
  return '${(n / 1073741824).toStringAsFixed(2)} GB';
}

String _fileName(String p) {
  final parts = p.split(RegExp(r'[\\/]'));
  return parts.isEmpty ? p : parts.last;
}

/// 上一层目录；已经在根目录时停在根目录
String _parent(String path) {
  if (path == _remoteRoot) return _remoteRoot;
  final i = path.lastIndexOf('/');
  return i <= 0 ? _remoteRoot : path.substring(0, i);
}

// ───────────── 投屏与截图 ─────────────

/// 投屏与截图卡片，对应 TS 版的 MirrorCard
class MirrorCard extends StatefulWidget {
  const MirrorCard({super.key, required this.tb, this.gate});

  final ToolboxController tb;

  /// 按钮不可用的原因；不传时由设备状态推出
  final Gate? gate;

  @override
  State<MirrorCard> createState() => _MirrorCardState();
}

class _MirrorCardState extends State<MirrorCard> {
  bool _separate = false;
  bool _turnScreenOff = false;
  bool _stayAwake = true;
  List<AppEntry>? _apps;
  String _app = '';
  DisplaySize _size = DisplaySize.fullHd;
  bool _keepApp = false;
  bool _audioOnPhone = false;
  OperationResult? _msg;

  /// 投屏窗口是否由本卡片打开。业务层的 mirrorRunning 不带通知，这里跟着自己的动作更新
  bool _mirrorOpen = false;

  ToolboxController get tb => widget.tb;

  Gate get _gate => widget.gate ?? gate(tb, {DeviceMode.system});

  /// 投屏不占用操作队列，有操作在进行时也可以打开
  String? get _mirrorBlocked {
    final d = tb.device;
    if (d.mode != DeviceMode.system) return '需要手机开机并开启 USB 调试';
    if (d.needsPick) return '请先在左下角选择要操作的设备';
    return null;
  }

  Future<void> _loadApps() async {
    final r = await tb.start('读取应用列表', const ListUserAppsRequest());
    if (!mounted || !r.ok || r.apps == null) return;
    setState(() => _apps = [
          for (final a in r.apps!)
            if (!a.disabled) a
        ]);
  }

  Future<void> _start() async {
    final r = await tb.startMirror(MirrorOptions(
      turnScreenOff: _turnScreenOff,
      stayAwake: _stayAwake,
      display: _separate
          ? MirrorDisplayOptions(
              app: _app.isEmpty ? null : _app,
              size: _size,
              keepApp: _keepApp,
              audioOnPhone: _audioOnPhone,
            )
          : null,
    ));
    if (mounted) {
      setState(() {
        _msg = r;
        if (r.ok) _mirrorOpen = true;
      });
    }
  }

  void _stop() {
    tb.stopMirror();
    setState(() => _mirrorOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final g = _gate;
    final blocked = _mirrorBlocked;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ActionIcon(Icons.screen_share_outlined, tone: Tone.info),
          const SizedBox(height: 14),
          const Text('投屏与截图', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Segmented<bool>(
            value: _separate,
            options: const [(false, '镜像手机屏幕'), (true, '独立屏幕')],
            onChanged: (v) => setState(() => _separate = v),
          ),
          const SizedBox(height: 12),
          if (!_separate) ...[
            const Muted(
              '用 scrcpy 把手机画面投到电脑上，可以用鼠标键盘直接操作，拖文件进窗口就能发送到手机。',
              small: true,
            ),
            const SizedBox(height: 8),
            CheckRow(
              value: _stayAwake,
              label: '投屏期间手机保持亮屏',
              onChanged: (v) => setState(() => _stayAwake = v),
            ),
            CheckRow(
              value: _turnScreenOff,
              label: '关闭手机屏幕（只在电脑上显示，更省电）',
              onChanged: (v) => setState(() => _turnScreenOff = v),
            ),
          ] else ...[
            const Muted(
              '在手机上新建一块虚拟屏幕投到电脑上：电脑上用一个应用，手机上照常用别的，互不影响，手机锁屏后电脑上也能继续用。'
              '同一个应用不能同时在两边打开；银行、支付类应用在电脑上会黑屏。',
              small: true,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _app,
                    isExpanded: true,
                    style: TextStyle(fontSize: 13.5, color: c.text),
                    decoration: const InputDecoration(hintText: '副屏桌面（在电脑上自己选应用）'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('副屏桌面（在电脑上自己选应用）')),
                      for (final a in _apps ?? const <AppEntry>[])
                        DropdownMenuItem(value: a.package, child: Text(a.label, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => _app = v ?? ''),
                  ),
                ),
                const SizedBox(width: 8),
                Gated(
                  reason: g.reason,
                  child: AppButton(
                    label: _apps != null ? '刷新' : '读取应用',
                    icon: Icons.refresh,
                    onPressed: g.disabled ? null : _loadApps,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<DisplaySize>(
              value: _size,
              isExpanded: true,
              style: TextStyle(fontSize: 13.5, color: c.text),
              items: [
                for (final s in DisplaySize.values) DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: (v) => setState(() => _size = v ?? DisplaySize.auto),
            ),
            CheckRow(
              value: _audioOnPhone,
              label: '声音留在手机上（不勾时所有应用的声音都转到电脑）',
              onChanged: (v) => setState(() => _audioOnPhone = v),
            ),
            CheckRow(
              value: _keepApp,
              label: '关掉窗口后把应用移回手机（会跳到手机屏幕前台）',
              onChanged: (v) => setState(() => _keepApp = v),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              Gated(
                reason: blocked,
                child: AppButton(
                  label: _separate ? '打开独立屏幕' : '开始投屏',
                  icon: Icons.screen_share_outlined,
                  kind: ButtonKind.primary,
                  onPressed: blocked != null ? null : _start,
                ),
              ),
              Gated(
                reason: g.reason,
                child: AppButton(
                  label: '截图',
                  icon: Icons.photo_camera_outlined,
                  onPressed: g.disabled ? null : () => tb.start('截图', const ScreenshotRequest()),
                ),
              ),
              if (_mirrorOpen || tb.service.mirrorRunning)
                AppButton(label: '关闭投屏', kind: ButtonKind.ghost, onPressed: _stop),
            ],
          ),
          if (_msg != null) ...[
            const SizedBox(height: 10),
            Text(
              _msg!.message,
              style: TextStyle(fontSize: 12.5, color: _msg!.ok ? c.muted : c.danger, height: 1.55),
            ),
          ],
        ],
      ),
    );
  }
}

// ───────────── 无线调试 ─────────────

/// 无线调试卡片，对应 TS 版的 WirelessCard
class WirelessCard extends StatefulWidget {
  const WirelessCard({super.key, required this.tb});

  final ToolboxController tb;

  @override
  State<WirelessCard> createState() => _WirelessCardState();
}

class _WirelessCardState extends State<WirelessCard> {
  final _host = TextEditingController();
  final _pairPort = TextEditingController();
  final _code = TextEditingController();
  final _port = TextEditingController();

  ToolboxController get tb => widget.tb;

  @override
  void dispose() {
    _host.dispose();
    _pairPort.dispose();
    _code.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _wireless(WirelessRequest request) => tb.start('无线调试', WirelessOpRequest(request));

  @override
  Widget build(BuildContext context) {
    final d = tb.device;
    final busy = tb.run.running;
    final usbReady = d.mode == DeviceMode.system && !d.needsPick && !(d.serial?.contains(':') ?? false);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: CardTitle('无线调试')),
              AppButton(
                label: '断开无线连接',
                kind: ButtonKind.ghost,
                onPressed: busy ? null : () => _wireless(const WirelessDisconnectRequest()),
              ),
            ],
          ),
          const Muted(
            '电脑和手机连同一个 Wi-Fi。Android 11 及以上：在手机「开发者选项 → 无线调试」里打开开关，'
            '第一次使用先点「使用配对码配对设备」配对，之后只需要连接。',
            small: true,
          ),
          const SizedBox(height: 14),
          _field(
            label: '手机 IP',
            child: TextField(
              controller: _host,
              style: const TextStyle(fontSize: 13.5),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: '192.168.1.23'),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _field(
                  label: '配对',
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _pairPort,
                          style: const TextStyle(fontSize: 13.5),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(hintText: '配对端口'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _code,
                          style: const TextStyle(fontSize: 13.5),
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(hintText: '6 位配对码', counterText: ''),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              AppButton(
                label: '配对',
                onPressed:
                    busy || _host.text.trim().isEmpty || _pairPort.text.trim().isEmpty || _code.text.trim().length != 6
                        ? null
                        : () => _wireless(WirelessPairRequest(
                              host: _host.text,
                              port: _pairPort.text,
                              code: _code.text,
                            )),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _field(
                  label: '连接',
                  child: TextField(
                    controller: _port,
                    style: const TextStyle(fontSize: 13.5),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(hintText: '无线调试页面上方显示的端口'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              AppButton(
                label: '连接',
                kind: ButtonKind.primary,
                onPressed: busy || _host.text.trim().isEmpty || _port.text.trim().isEmpty
                    ? null
                    : () => _wireless(WirelessConnectRequest(host: _host.text, port: _port.text)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Gated(
                reason: usbReady ? null : '需要手机开机、用数据线连接',
                child: AppButton(
                  label: '从数据线切换到无线',
                  onPressed: busy || !usbReady ? null : () => _wireless(const WirelessFromUsbRequest()),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Muted(
                  '插着数据线时一键切换（adb tcpip 5555），适合没有「无线调试」选项的老系统；手机重启后失效',
                  small: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field({required String label, required Widget child}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12.5, color: context.palette.muted)),
          const SizedBox(height: 4),
          child,
        ],
      );
}

// ───────────── 文件传输 ─────────────

/// 文件传输卡片，对应 TS 版的 FilesCard
class FilesCard extends StatefulWidget {
  const FilesCard({super.key, required this.tb, this.gate});

  final ToolboxController tb;

  /// 按钮不可用的原因；不传时由设备状态推出
  final Gate? gate;

  @override
  State<FilesCard> createState() => _FilesCardState();
}

class _FilesCardState extends State<FilesCard> {
  String _path = _remoteRoot;
  List<RemoteEntry>? _entries;

  ToolboxController get tb => widget.tb;

  Gate get _gate => widget.gate ?? gate(tb, {DeviceMode.system});

  Future<void> _open(String p) async {
    final r = await tb.start('浏览 $p', ListRemoteRequest(p));
    if (!mounted || !r.ok || r.remote == null) return;
    setState(() {
      _path = r.remote!.path;
      _entries = r.remote!.entries;
    });
  }

  Future<void> _send(List<String> files) async {
    if (files.isEmpty || _gate.disabled) return;
    final r = await tb.start(
      files.length == 1 ? '发送 ${_fileName(files.first)}' : '发送 ${files.length} 个文件',
      PushFilesRequest(files: files, to: _path),
    );
    if (r.ok && _entries != null) await _open(_path);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final g = _gate;
    final crumbs = _path.split('/').where((s) => s.isNotEmpty).toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: CardTitle('文件传输')),
              AppButton(
                label: '发送文件…',
                icon: Icons.upload_outlined,
                onPressed: g.disabled ? null : () async => _send(await pickAnyFiles()),
              ),
              const SizedBox(width: 8),
              Gated(
                reason: g.reason,
                child: AppButton(
                  label: _entries != null ? '刷新' : '浏览手机存储',
                  icon: Icons.refresh,
                  kind: ButtonKind.ghost,
                  onPressed: g.disabled ? null : () => _open(_path),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DropZone(
            enable: !tb.run.running,
            radius: 10,
            onFiles: _send,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (var i = 0; i < crumbs.length; i++) ...[
                        if (i > 0) Icon(Icons.chevron_right, size: 13, color: c.muted),
                        TextButton(
                          onPressed: g.disabled ? null : () => _open('/${crumbs.sublist(0, i + 1).join('/')}'),
                          child: Text(i == 0 ? '内置存储' : crumbs[i], style: const TextStyle(fontSize: 12.5)),
                        ),
                      ],
                      const SizedBox(width: 8),
                      const Muted('　把文件拖到这里，发送到当前文件夹', small: true),
                    ],
                  ),
                  if (_entries != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: c.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          if (_path != _remoteRoot)
                            _row(
                              icon: Icons.drive_file_move_outline,
                              name: '上一级',
                              onTap: g.disabled ? null : () => _open(_parent(_path)),
                            ),
                          if (_entries!.isEmpty)
                            const Padding(padding: EdgeInsets.all(16), child: Muted('空文件夹', small: true)),
                          for (final e in _entries!)
                            _row(
                              icon: e.dir ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
                              name: e.name,
                              size: e.dir ? null : _size(e.size),
                              onTap: e.dir && !g.disabled ? () => _open('$_path/${e.name}') : null,
                              onPull: e.dir || g.disabled
                                  ? null
                                  : () => tb.start('接收 ${e.name}', PullFileRequest('$_path/${e.name}')),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Muted('从手机接收的文件保存在「文档\\一加工具箱\\传输」。', small: true),
        ],
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String name,
    String? size,
    VoidCallback? onTap,
    VoidCallback? onPull,
  }) {
    final c = context.palette;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Icon(icon, size: 15, color: c.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Tooltip(
                message: name,
                child: Text(name, style: const TextStyle(fontSize: 13.5), overflow: TextOverflow.ellipsis),
              ),
            ),
            if (size != null) ...[Muted(size, small: true), const SizedBox(width: 10)],
            if (onPull != null)
              IconButton(
                tooltip: '保存到电脑',
                iconSize: 15,
                visualDensity: VisualDensity.compact,
                onPressed: onPull,
                icon: const Icon(Icons.download_outlined),
              ),
          ],
        ),
      ),
    );
  }
}
