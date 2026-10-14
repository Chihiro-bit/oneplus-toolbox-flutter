import 'package:flutter/material.dart';
import 'package:toolbox_service/toolbox_service.dart';

import '../controller.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';

const _flow = {
  RootFamily.magisk: [
    '读取 ROM 元数据，与手机 ro.build.date.utc 比对',
    '提取 boot.img / init_boot.img',
    '下载 Magisk 并校验 sha256',
    '在手机上运行 Magisk 自带的 boot_patch.sh 修补',
    '安装 Magisk App，进入 Fastboot 刷入',
    '开机后在 Magisk App 中完成「额外的设置」',
  ],
  RootFamily.apatch: [
    '读取 ROM 元数据，与手机 ro.build.date.utc 比对',
    '提取 boot.img（APatch 修补内核）',
    '下载 APatch 并校验 sha256',
    '用你设置的超级密钥运行 APatch 的 boot_patch.sh',
    '安装 APatch，进入 Fastboot 刷入',
    '开机后打开 APatch，输入超级密钥激活',
  ],
  RootFamily.ksu: [
    '读取 ROM 元数据，与手机 ro.build.date.utc 比对',
    '提取 init_boot.img / boot.img',
    '下载管理器并校验 sha256',
    '运行 ksud boot-patch（LKM 模式），失败时自动推算 KMI 重试',
    '安装管理器，进入 Fastboot 刷入',
    '开机后打开管理器，确认显示「工作中」',
  ],
};

/// 一键 Root。页面切走时保留填写的内容，所以状态放在 [RootForm] 里由外层持有
class RootPage extends StatefulWidget {
  const RootPage({super.key, required this.tb, required this.form});

  final ToolboxController tb;
  final RootForm form;

  @override
  State<RootPage> createState() => _RootPageState();
}

/// Root 页面填写的内容
class RootForm {
  String schemeId = 'magisk';
  String customApk = '';
  RootFamily customFamily = RootFamily.magisk;
  final rom = TextEditingController();
  PatchTarget target = PatchTarget.auto;
  final superkey = TextEditingController();
  bool patchOnly = false;
  bool flashOther = true;
  bool uninstallOthers = true;

  void dispose() {
    rom.dispose();
    superkey.dispose();
  }
}

class _RootPageState extends State<RootPage> {
  CatalogState? _catalog;
  bool _refreshing = false;
  bool _showKey = false;

  RootForm get f => widget.form;
  ToolboxController get tb => widget.tb;

  @override
  void initState() {
    super.initState();
    tb.service.catalog().then((c) {
      if (mounted) setState(() => _catalog = c);
    });
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    final c = await tb.service.catalog(refresh: true);
    if (mounted) {
      setState(() {
        _catalog = c;
        _refreshing = false;
      });
    }
  }

  RootScheme? get _scheme => _catalog?.schemes.where((s) => s.id == f.schemeId).firstOrNull;

  bool get _custom => f.schemeId == customSchemeId;

  RootFamily get _family => _custom ? f.customFamily : (_scheme?.family ?? RootFamily.magisk);

  String? get _keyProblem => _family == RootFamily.apatch ? superkeyProblem(f.superkey.text) : null;

  String? get _missing {
    if (f.rom.text.trim().isEmpty) return '请先选择 ROM';
    if (_custom && f.customApk.isEmpty) return '请选择自定义 APK';
    final k = _keyProblem;
    if (k != null) return k == '请设置超级密钥' ? k : '超级密钥$k';
    return null;
  }

  Future<void> _start() async {
    final family = _family;
    final name = _custom ? '自定义 APK（${f.customFamily.label}）' : (_scheme?.name ?? f.schemeId);
    if (!f.patchOnly) {
      final ok = await confirmAction(
        context,
        ConfirmSpec(
          title: '开始 Root（$name）',
          danger: true,
          intro: '修补完成后会安装管理器 App，并自动进入 Fastboot 刷入修补后的镜像。',
          checks: [
            'Bootloader 已经解锁',
            'ROM 与手机当前系统版本完全一致',
            if (family == RootFamily.apatch) '我已记下超级密钥，开机后需要用它激活 APatch',
            '如果以前装过 Root 模块，我知道它们可能被重新启用，不兼容时可能导致无法开机',
          ],
          confirmText: '开始 Root',
        ),
      );
      if (!ok) return;
    }
    await tb.start(
      '$name Root',
      RootRequest(RootOptions(
        rom: f.rom.text.trim(),
        schemeId: f.schemeId,
        customApk: _custom ? f.customApk : null,
        customFamily: _custom ? f.customFamily : null,
        target: f.target,
        superkey: family == RootFamily.apatch ? f.superkey.text : null,
        patchOnly: f.patchOnly,
        flashOther: f.flashOther,
        uninstallOthers: f.uninstallOthers,
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    // APatch 只能修补 boot
    if (_family == RootFamily.apatch && f.target == PatchTarget.initBoot) f.target = PatchTarget.auto;

    final left = Column(children: [_schemeCard(context), const SizedBox(height: 16), _romCard(context)]);
    final right = _flowCard(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader('一键 Root', '从与手机当前系统一致的 ROM 中提取镜像，在手机上用所选方案的官方工具修补后刷入'),
        LayoutBuilder(builder: (context, box) {
          if (box.maxWidth < 860) return Column(children: [left, const SizedBox(height: 16), right]);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: 16),
              SizedBox(width: 300, child: right),
            ],
          );
        }),
      ],
    );
  }

  // ───────────── 1. 选择方案 ─────────────

  Widget _schemeCard(BuildContext context) {
    final c = context.palette;
    final catalog = _catalog;
    final scheme = _scheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: CardTitle('1. 选择方案')),
              if (catalog != null) Muted(catalog.source.label, small: true),
              const SizedBox(width: 4),
              IconButton(
                tooltip: '刷新方案目录',
                iconSize: 15,
                onPressed: _refreshing ? null : _refresh,
                icon: _refreshing
                    ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
          if (catalog?.error != null) Callout(Tone.warn, text: catalog!.error),
          ResponsiveGrid(
            minItemWidth: 170,
            maxColumns: 3,
            gap: 10,
            children: [
              for (final s in catalog?.schemes ?? const <RootScheme>[])
                _SchemeTile(
                  title: s.name,
                  subtitle:
                      '${s.version}${s.apk.size != null ? ' · ${formatSize(s.apk.size)}' : s.apk.bundled ? ' · 离线' : ''}',
                  chip: TagChip(s.family.label, color: _familyColor(c, s.family)),
                  selected: f.schemeId == s.id,
                  tooltip: s.note,
                  onTap: () => setState(() => f.schemeId = s.id),
                ),
              _SchemeTile(
                title: '自定义 APK',
                subtitle: 'Kitsune / Alpha / ReSukiSU 等',
                chip: const TagChip('本地文件'),
                selected: _custom,
                onTap: () => setState(() => f.schemeId = customSchemeId),
              ),
            ],
          ),
          if (scheme?.note != null && !_custom) ...[const SizedBox(height: 12), Muted(scheme!.note!, small: true)],
          if (_custom) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PathField(
                    icon: Icons.upload_file_outlined,
                    hint: '选择管理器 APK（请从项目官方发布页获取）',
                    value: f.customApk,
                    onBrowse: () async {
                      final p = await pickApk();
                      if (p != null) setState(() => f.customApk = p);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Muted('修补方式', small: true),
                      const SizedBox(width: 12),
                      Segmented<RootFamily>(
                        value: f.customFamily,
                        options: [for (final fam in RootFamily.values) (fam, fam.label)],
                        onChanged: (v) => setState(() => f.customFamily = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Muted('Kitsune、Alpha 选「Magisk 系」，ReSukiSU 等 KernelSU 分支选「KernelSU 系」。自定义 APK 无法校验来源。',
                      small: true),
                ],
              ),
            ),
          ],
          if (_family == RootFamily.apatch) ...[
            const SizedBox(height: 16),
            const Text('超级密钥', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: f.superkey,
              obscureText: !_showKey,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 13.5),
              decoration: InputDecoration(
                hintText: '至少 8 位，同时包含字母和数字',
                errorText: f.superkey.text.isNotEmpty ? _keyProblem : null,
                suffixIcon: IconButton(
                  tooltip: _showKey ? '隐藏' : '显示',
                  iconSize: 16,
                  onPressed: () => setState(() => _showKey = !_showKey),
                  icon: Icon(_showKey ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                ),
              ),
            ),
            if (f.superkey.text.isEmpty || _keyProblem == null) ...[
              const SizedBox(height: 6),
              const Muted('开机后要用它激活 APatch，请务必记住。工具箱不会保存或上传', small: true),
            ],
          ],
        ],
      ),
    );
  }

  Color _familyColor(Palette c, RootFamily f) => switch (f) {
        RootFamily.magisk => c.ok,
        RootFamily.apatch => c.warn,
        RootFamily.ksu => c.info,
      };

  // ───────────── 2~4. ROM、目标、选项 ─────────────

  Widget _romCard(BuildContext context) {
    final d = tb.device;
    final g = gate(tb, {DeviceMode.system});
    final missing = _missing;
    final url = isUrl(f.rom.text);
    final apatch = _family == RootFamily.apatch;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardTitle('2. 选择 ROM 包'),
          const Text.rich(
            TextSpan(children: [
              TextSpan(text: '需要与手机'),
              TextSpan(text: '当前系统版本完全一致', style: TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: '的全量包。标准 OTA 包会自动比对版本，不一致时拒绝继续。'),
            ]),
            style: TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          if (d.mode == DeviceMode.system && (d.buildId != null || d.romVersion != null)) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: context.palette.surface2, borderRadius: BorderRadius.circular(9)),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Muted('手机当前版本', small: true),
                  if (d.buildId != null) Code(d.buildId!),
                  if (d.romVersion != null) Code(d.romVersion!),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          PathField(
            icon: url ? Icons.link : Icons.folder_zip_outlined,
            hint: '选择本地文件，或粘贴 ROM 的下载链接',
            controller: f.rom,
            onChanged: (_) => setState(() {}),
            onBrowse: () async {
              final p = await pickRom();
              if (p != null) setState(() => f.rom.text = p);
            },
          ),
          if (url) ...[const SizedBox(height: 6), const Muted('使用链接时只会按需读取所需部分，不会下载整个 ROM 包。', small: true)],
          const CardTitle('3. 修补目标', top: 22),
          Segmented<PatchTarget>(
            value: f.target,
            options: const [(PatchTarget.auto, '自动'), (PatchTarget.initBoot, 'init_boot'), (PatchTarget.boot, 'boot')],
            disabled: (v) => apatch && v == PatchTarget.initBoot,
            onChanged: (v) => setState(() => f.target = v),
          ),
          const SizedBox(height: 8),
          Muted(
            apatch ? 'APatch 修补内核，固定使用 boot.img。' : '自动：ROM 中有 init_boot.img（Android 13 及以后出厂的机型）就修补它，否则修补 boot.img。',
            small: true,
          ),
          const CardTitle('4. 选项', top: 22),
          CheckRow(
            value: f.patchOnly,
            label: '只生成修补后的镜像，不刷入（保存到「文档\\一加工具箱」）',
            onChanged: (v) => setState(() => f.patchOnly = v),
          ),
          CheckRow(
            value: f.flashOther,
            label: '同时刷回 ROM 中原厂的另一个分区，清除之前装过的其它 Root',
            onChanged: f.patchOnly ? null : (v) => setState(() => f.flashOther = v),
          ),
          CheckRow(
            value: f.uninstallOthers,
            label: '卸载其它 Root 管理器（Magisk / APatch / KernelSU 及其分支）',
            onChanged: f.patchOnly ? null : (v) => setState(() => f.uninstallOthers = v),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Gated(
                reason: g.reason ?? missing,
                child: AppButton(
                  label: f.patchOnly ? '开始修补' : '开始 Root',
                  icon: Icons.auto_awesome_outlined,
                  kind: ButtonKind.primary,
                  large: true,
                  onPressed: g.disabled || missing != null ? null : _start,
                ),
              ),
              if (!tb.run.running && (g.reason ?? missing) != null) Muted((g.reason ?? missing)!, small: true),
            ],
          ),
        ],
      ),
    );
  }

  // ───────────── 流程说明 ─────────────

  Widget _flowCard(BuildContext context) {
    final c = context.palette;
    final scheme = _scheme;
    final steps = _flow[_family]!;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardTitle('流程 · ${_family.label}'),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 20,
                    child:
                        Text('${i + 1}.', style: TextStyle(color: c.accent, fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                  Expanded(child: Text(steps[i], style: const TextStyle(fontSize: 13))),
                ],
              ),
            ),
          if (scheme?.homepage != null && !_custom) ...[
            const SizedBox(height: 8),
            LinkButton('${scheme!.name} 项目主页', onTap: () => openExternal(scheme.homepage!)),
          ],
        ],
      ),
    );
  }
}

class _SchemeTile extends StatelessWidget {
  const _SchemeTile({
    required this.title,
    required this.subtitle,
    required this.chip,
    required this.selected,
    required this.onTap,
    this.tooltip,
  });

  final String title;
  final String subtitle;
  final Widget chip;
  final bool selected;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final tile = Material(
      color: selected ? c.accentSoft : c.surface2,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: selected ? c.accent : c.border, width: selected ? 1.5 : 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
                  if (selected) Icon(Icons.check, size: 16, color: c.accent),
                ],
              ),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 12, color: c.muted)),
              const SizedBox(height: 8),
              chip,
            ],
          ),
        ),
      ),
    );
    return tooltip == null ? tile : Tooltip(message: tooltip!, child: tile);
  }
}
