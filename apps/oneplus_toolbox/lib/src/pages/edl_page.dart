import 'package:flutter/material.dart';
import 'package:toolbox_service/toolbox_service.dart';

import '../controller.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';

const _storages = EdlStorage.values;

const _flow = [
  '确认 9008 驱动已装好，手机进入 EDL 后这边能检测到端口',
  '把自备的设备编程器、签名摘要和深刷散包填进来',
  '先点「预检」：读芯片信息 + 离线校验文件集，全程不写设备',
  '通过后再「开始刷写」，qdl 先跑一次 --dry-run 才真正写分区',
  '刷完自动重启；如果卡在 9008，用「退出 9008」发重启指令',
];

/// 9008 页面填写的内容。页面切走时保留，所以由外层持有。
class EdlForm {
  String programmer = '';
  String vipDir = '';
  String imagesDir = '';
  List<String> xmls = const [];
  EdlStorage storage = EdlStorage.ufs;
  bool protectLun5 = true;
  bool allowMissing = false;
  bool skipReset = false;
  bool dryRunOnly = false;

  void dispose() {}

  EdlProfile toProfile() => EdlProfile(
        programmer: programmer,
        vipDir: vipDir.trim().isEmpty ? null : vipDir.trim(),
        xmls: xmls,
        imagesDir: imagesDir,
        storage: storage,
        protectLun5: protectLun5,
        allowMissing: allowMissing,
        skipReset: skipReset,
        dryRunOnly: dryRunOnly,
      );
}

class EdlPage extends StatefulWidget {
  const EdlPage({super.key, required this.tb, required this.form});

  final ToolboxController tb;
  final EdlForm form;

  @override
  State<EdlPage> createState() => _EdlPageState();
}

class _EdlPageState extends State<EdlPage> {
  EdlForm get f => widget.form;
  ToolboxController get tb => widget.tb;

  bool get _running => tb.run.running;

  List<EdlDevice> get _ports {
    final edl = tb.run.result?.edl;
    if (edl != null && edl.ports.isNotEmpty) return edl.ports;
    final d = tb.device;
    if (d.mode == DeviceMode.edl) {
      return [EdlDevice(port: d.edlPort ?? '', name: d.device ?? 'QDLoader 9008')];
    }
    return const [];
  }

  String? get _missing {
    if (f.programmer.isEmpty) return '请选择设备编程器（devprg*.mbn）';
    if (f.imagesDir.isEmpty) return '请选择散包目录';
    if (f.xmls.isEmpty) return '请选择 rawprogram / patch XML';
    return null;
  }

  Future<void> _reset() async {
    final ok = await confirmAction(
      context,
      const ConfirmSpec(
        title: '让设备退出 9008',
        intro: '会通过 Sahara 向设备发送重启指令。如果没反应，可以长按电源键 10 秒以上强制重启。',
        checks: ['我确认现在可以让设备重启'],
        confirmText: '发送重启',
      ),
    );
    if (ok) await tb.start('退出 9008', const EdlResetRequest());
  }

  Future<void> _flash() async {
    final dry = f.dryRunOnly;
    final ok = await confirmAction(
      context,
      ConfirmSpec(
        title: dry ? '开始 9008 预检' : '开始 9008 刷写',
        danger: !dry,
        intro: dry ? '只做离线预检，不接触设备、不写入任何分区。' : '会按散包里的分区表覆盖手机上的对应分区。写错分区或机型不匹配，可能无法恢复。',
        checks: dry
            ? const ['我了解这一步不会刷入任何数据']
            : const [
                '我确认散包与这台手机的型号、存储类型完全对应',
                '我知道刷写会覆盖分区，刷错可能无法恢复',
                '我确认了要跳过哪些分区（默认已保护 LUN5），并知道 persist / OCDT 写错的后果',
                '刷写期间我不会拔线、断电或让电脑休眠',
              ],
        confirmText: dry ? '开始预检' : '开始刷写',
      ),
    );
    if (ok) await tb.start(dry ? '9008 预检（只读）' : '9008 刷写', EdlFlashRequest(f.toProfile()));
  }

  @override
  Widget build(BuildContext context) {
    final edl = tb.run.result?.edl;
    final ports = _ports;
    final connected = ports.isNotEmpty;
    final blocked = _missing ?? (!connected ? '先点「检测设备」，确认手机已经在 9008 模式' : null);

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _connectCard(edl, ports, connected),
        const SizedBox(height: 14),
        _filesCard(),
        const SizedBox(height: 14),
        _executeCard(edl, connected, blocked),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader('9008 救砖', '高通 EDL 深刷。工具箱只负责检测、校验、排序和日志，刷写由 qdl 完成，所有专有文件由你自备'),
        const Callout(
          Tone.danger,
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '先看熔断这件事。', style: TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: '一加 13 / 13T 自 ColorOS '),
            TextSpan(text: '16.0.3.501', style: TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: ' 起提高了 xbl_config 的反回滚值并换掉了 EDL 证书签名，'),
            TextSpan(text: '免授权 9008 已永久不可逆失效', style: TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(
                text: '（16.0.8.xxx 同样如此），降级也救不回来。如果你的手机更新过这些版本，这里会连 9008 都进不去或直接卡在 Sahara，'
                    '请改用 Fastboot（A/B 槽位、刷回原厂 boot）或送售后。本工具不提供、也不下载任何编程器、签名摘要和刷机包。'),
          ])),
        ),
        LayoutBuilder(builder: (context, box) {
          if (box.maxWidth < 860) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [left, const SizedBox(height: 14), _flowCard()],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: 14),
              SizedBox(width: 300, child: _flowCard()),
            ],
          );
        }),
      ],
    );
  }

  // 1. 连接 9008 设备
  Widget _connectCard(EdlState? edl, List<EdlDevice> ports, bool connected) {
    final c = context.palette;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('1. 连接 9008 设备', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
              if (connected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(color: c.okSoft, borderRadius: BorderRadius.circular(99)),
                  child: Text('已连接', style: TextStyle(color: c.ok, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Muted(
              '需要先装好高通 9008（QDLoader）驱动。手机完全关机后，同时按住关机键 + 音量加 + 音量减进入 EDL，'
              '设备管理器里会出现「Qualcomm HS-USB QDLoader 9008」。',
              small: true),
          const SizedBox(height: 12),
          if (ports.isNotEmpty)
            for (final port in ports)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.usb, size: 15, color: c.muted),
                    const SizedBox(width: 8),
                    Expanded(child: Text(port.name, style: const TextStyle(fontSize: 13))),
                    if (port.port.isNotEmpty) ...[const SizedBox(width: 8), TagChip(port.port)],
                  ],
                ),
              )
          else
            const Muted('还没有检测到 9008 设备。', small: true),
          if (edl?.chipInfo != null && edl!.chipInfo!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(edl.saharaOk ? '芯片信息' : 'Sahara 输出', style: TextStyle(fontSize: 12, color: c.muted)),
            const SizedBox(height: 4),
            Code(edl.chipInfo!.split(RegExp(r'\r?\n')).first),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              AppButton(
                label: '检测设备',
                icon: Icons.usb,
                onPressed: _running ? null : () => tb.start('查找 9008 设备', const EdlDetectRequest()),
              ),
              Gated(
                reason: connected ? null : '先检测到 9008 设备',
                child: AppButton(
                  label: '退出 9008',
                  icon: Icons.power_off_outlined,
                  kind: ButtonKind.ghost,
                  onPressed: (_running || !connected) ? null : _reset,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 2. 准备文件 + 3. 存储与选项
  Widget _filesCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('2. 准备文件（全部由你自备）', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Muted('编程器要按处理器选（例如 8Gen3 用 8Gen3 的引导文件），散包要按机型选。用错机型的散包会直接写坏分区。', small: true),
          const SizedBox(height: 14),
          const _FieldLabel('设备编程器（devprg*.mbn / prog_firehose_ddr.elf）'),
          PathField(
            icon: Icons.bolt_outlined,
            hint: '选择本机处理器对应的编程器文件',
            value: f.programmer,
            onBrowse: _running
                ? () {}
                : () async {
                    final p = await pickFile(['mbn', 'elf', 'bin']);
                    if (p != null) setState(() => f.programmer = p);
                  },
          ),
          const SizedBox(height: 12),
          const _FieldLabel('签名摘要表目录（可选，安全启动设备必填）'),
          PathField(
            icon: Icons.verified_outlined,
            hint: '留空表示这台设备不校验签名摘要',
            value: f.vipDir,
            onBrowse: _running
                ? () {}
                : () async {
                    final p = await pickDir();
                    if (p != null) setState(() => f.vipDir = p);
                  },
          ),
          const SizedBox(height: 12),
          const _FieldLabel('散包目录（深刷镜像所在文件夹）'),
          PathField(
            icon: Icons.folder_open_outlined,
            hint: '选择解压后的深刷散包目录',
            value: f.imagesDir,
            onBrowse: _running
                ? () {}
                : () async {
                    final p = await pickDir();
                    if (p != null) setState(() => f.imagesDir = p);
                  },
          ),
          const SizedBox(height: 12),
          const _FieldLabel('rawprogram / patch XML'),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              AppButton(
                label: '选择 XML',
                icon: Icons.code,
                onPressed: _running
                    ? null
                    : () async {
                        final picked = await pickFiles(['xml']);
                        if (picked.isNotEmpty) setState(() => f.xmls = picked);
                      },
              ),
              if (f.xmls.isNotEmpty)
                AppButton(
                    label: '清空',
                    kind: ButtonKind.ghost,
                    onPressed: _running ? null : () => setState(() => f.xmls = const [])),
            ],
          ),
          if (f.xmls.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final x in f.xmls)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(Icons.code, size: 14, color: context.palette.muted),
                    const SizedBox(width: 8),
                    Expanded(child: Text(x.split(RegExp(r'[\\/]')).last, style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            const Muted('会按 rawprogram* → patch* 的顺序发送；标了「保护 LUN5」时 rawprogram5 / patch5 会被跳过。', small: true),
          ],
          const SizedBox(height: 18),
          const Text('3. 目标存储与选项', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Segmented<EdlStorage>(
            value: f.storage,
            options: [for (final s in _storages) (s, s.name)],
            onChanged: _running ? (_) {} : (v) => setState(() => f.storage = v),
          ),
          const SizedBox(height: 8),
          const Muted('一加手机的 UFS 一般是 ufs；只有明确知道是 eMMC 机型时才改。', small: true),
          const SizedBox(height: 8),
          CheckRow(
            value: f.protectLun5,
            label: '保护 LUN5：跳过 rawprogram5 / patch5（强烈建议保持勾选）',
            onChanged: _running ? null : (v) => setState(() => f.protectLun5 = v),
          ),
          CheckRow(
            value: f.dryRunOnly,
            label: '只做预检，不刷入（可随时先跑这一步确认文件集）',
            onChanged: _running ? null : (v) => setState(() => f.dryRunOnly = v),
          ),
          CheckRow(
            value: f.skipReset,
            label: '刷完不重启，把设备留在 9008（qdl --skip-reset）',
            onChanged: _running ? null : (v) => setState(() => f.skipReset = v),
          ),
          CheckRow(
            value: f.allowMissing,
            label: '散包缺少镜像时跳过而不中止（qdl --allow-missing，会让刷入的分区变少）',
            onChanged: _running ? null : (v) => setState(() => f.allowMissing = v),
          ),
        ],
      ),
    );
  }

  // 4. 执行
  Widget _executeCard(EdlState? edl, bool connected, String? blocked) {
    final c = context.palette;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('4. 执行', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Muted('「预检」只读芯片信息并离线校验文件集，不写任何数据；「开始刷写」会先自动跑一遍同样的预检，通过后才写分区。', small: true),
          if (edl?.command != null && edl!.command!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.terminal, size: 15, color: c.muted),
                const SizedBox(width: 8),
                Expanded(child: Code(edl.command!)),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Gated(
                reason: connected ? null : '先检测到 9008 设备',
                child: AppButton(
                  label: '预检',
                  icon: Icons.play_circle_outline,
                  onPressed:
                      (_running || !connected) ? null : () => tb.start('9008 预检（只读）', EdlProbeRequest(f.toProfile())),
                ),
              ),
              Gated(
                reason: blocked,
                child: AppButton(
                  label: f.dryRunOnly ? '开始预检' : '开始刷写',
                  icon: Icons.warning_amber_rounded,
                  kind: ButtonKind.danger,
                  large: true,
                  onPressed: (_running || blocked != null) ? null : _flash,
                ),
              ),
            ],
          ),
          if (blocked != null && !_running) GateHint(blocked),
        ],
      ),
    );
  }

  Widget _flowCard() {
    final c = context.palette;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('流程', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          for (var i = 0; i < _flow.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 20,
                    child: Text('${i + 1}.', style: TextStyle(color: c.accent, fontWeight: FontWeight.w600)),
                  ),
                  Expanded(child: Muted(_flow[i], small: true)),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10)),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('这个功能不做的事', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                SizedBox(height: 6),
                Muted('• 不提供编程器、签名摘要、散包或驱动', small: true),
                Muted('• 不做 super 分片合并与 OFP / OPS 解密', small: true),
                Muted('• 不修 OCDT，不刷 persist', small: true),
                SizedBox(height: 6),
                Muted('需要这些的话，请用能处理欧加真专有格式的外部工具，工具箱只做检测、校验和调度。', small: true),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.shield_outlined, size: 14, color: c.muted),
              const SizedBox(width: 8),
              const Expanded(
                child: Muted('进 EDL 后手机会一直黑屏；退出方式是长按 音量上 + 电源键（老机型长按电源键）。', small: true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: TextStyle(fontSize: 12.5, color: context.palette.muted, fontWeight: FontWeight.w600)),
    );
  }
}
