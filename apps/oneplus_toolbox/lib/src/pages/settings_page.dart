import 'package:flutter/material.dart';
import 'package:toolbox_service/toolbox_service.dart';

import '../controller.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.tb});

  final ToolboxController tb;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final _catalogUrl = TextEditingController();
  late final _updateRepo = TextEditingController();
  CatalogState? _catalog;
  (bool ok, String text)? _saveMsg;
  UpdateInfo? _update;
  bool _checking = false;
  bool _saving = false;

  ToolboxService get service => widget.tb.service;

  @override
  void initState() {
    super.initState();
    final s = service.settings;
    _catalogUrl.text = s.catalogUrl;
    _updateRepo.text = s.updateRepo;
    service.catalog().then((c) {
      if (mounted) setState(() => _catalog = c);
    });
    // 配置了更新仓库时，从侧栏的「新版本」进来就直接显示结果
    if (s.updateRepo.isNotEmpty) {
      service.checkUpdate().then((u) {
        if (mounted) setState(() => _update = u);
      });
    }
  }

  @override
  void dispose() {
    _catalogUrl.dispose();
    _updateRepo.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final s = await service.saveSettings(Settings(catalogUrl: _catalogUrl.text, updateRepo: _updateRepo.text));
      final c = await service.catalog();
      _catalogUrl.text = s.catalogUrl;
      _updateRepo.text = s.updateRepo;
      _catalog = c;
      _saveMsg = c.error != null ? (false, c.error!) : (true, '已保存');
    } on SettingsException catch (e) {
      _saveMsg = (false, e.message);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final u = await service.checkUpdate();
    if (mounted) {
      setState(() {
        _update = u;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final catalog = _catalog;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader('设置', '方案目录、版本更新、日志与诊断'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CardTitle('Root 方案目录'),
              const Muted(
                '留空时只使用内置目录。可以填一个自己维护的 catalog.json 地址（例如 GitHub 上的 raw 链接），用来更新各方案的 APK 版本。'
                '目录只包含下载地址和 sha256，不会下发任何脚本；每个 APK 下载后都会强制校验哈希。',
                small: true,
              ),
              const SizedBox(height: 12),
              _label('目录地址'),
              TextField(
                controller: _catalogUrl,
                style: const TextStyle(fontSize: 13.5),
                decoration: const InputDecoration(
                  hintText: 'https://raw.githubusercontent.com/<owner>/<repo>/main/catalog/catalog.json',
                ),
              ),
              if (catalog != null) ...[
                const SizedBox(height: 6),
                Muted(
                  '当前：${catalog.source == CatalogSource.cache ? '远程目录（离线缓存）' : catalog.source.label}，共 ${catalog.schemes.length} 个方案',
                  small: true,
                ),
              ],
              const CardTitle('检查更新', top: 24),
              const Muted('填写发布本工具的 GitHub 仓库，会读取该仓库最新的 Release 版本号。', small: true),
              const SizedBox(height: 12),
              _label('GitHub 仓库'),
              TextField(
                controller: _updateRepo,
                style: const TextStyle(fontSize: 13.5),
                decoration: const InputDecoration(hintText: 'owner/repo'),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AppButton(
                      label: '保存',
                      icon: Icons.save_outlined,
                      kind: ButtonKind.primary,
                      onPressed: _saving ? null : _save),
                  AppButton(
                    label: _checking ? '检查中…' : '检查更新',
                    icon: Icons.download_outlined,
                    onPressed: _checking ? null : _check,
                  ),
                  if (_saveMsg case (final ok, final text))
                    Text(text, style: TextStyle(fontSize: 12.5, color: ok ? c.ok : c.danger)),
                ],
              ),
              if (_update case final u?) ...[
                const SizedBox(height: 16),
                if (u.error != null)
                  Callout(Tone.warn, text: '当前版本 ${u.current}。${u.error}')
                else if (u.hasUpdate)
                  Callout(
                    Tone.info,
                    child: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('发现新版本 ${u.latest}（当前 ${u.current}）。'),
                        // 免安装发布包（对应 TS 版的便携版）不能自动替换，只能去发布页下载
                        if (u.url != null) LinkButton('前往下载', onTap: () => openExternal(u.url!)),
                      ],
                    ),
                  )
                else
                  Muted('已是最新版本（${u.current}）', small: true),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CardTitle('日志与诊断'),
              const Muted(
                '每次操作的日志都会保存到「文档\\一加工具箱\\logs」，保留 30 天。提交问题反馈时，请导出诊断信息并附上：里面有工具箱版本、'
                '设备状态（开机时读取与刷机相关的系统属性，Fastboot 下读取 getvar all）和最近两天的日志。序列号会被打码，'
                '不包含 IMEI、账号等信息。',
                small: true,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  AppButton(
                    label: '导出诊断信息',
                    icon: Icons.description_outlined,
                    kind: ButtonKind.primary,
                    onPressed: widget.tb.run.running
                        ? null
                        : () => widget.tb.start('导出诊断信息', const ExportDiagnosticsRequest()),
                  ),
                  AppButton(
                    label: '打开日志文件夹',
                    icon: Icons.folder_open_outlined,
                    onPressed: () => openDir(service.logDir),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      );
}
