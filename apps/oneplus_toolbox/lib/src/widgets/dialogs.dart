import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:toolbox_service/toolbox_service.dart';

import '../theme.dart';
import 'common.dart';

// ───────────── 危险操作确认对话框 ─────────────

class ConfirmSpec {
  const ConfirmSpec({
    required this.title,
    required this.checks,
    required this.confirmText,
    this.intro,
    this.danger = false,
    this.confirmationPhrase,
    this.waitSeconds = 0,
  });

  final String title;

  /// 危险操作：除了勾选全部条目，还要输入随机确认码
  final bool danger;
  final String? intro;
  final List<String> checks;
  final String confirmText;
  final String? confirmationPhrase;
  final int waitSeconds;
}

/// 弹出确认对话框，全部勾选（危险操作还需输入确认码）并点击确认时返回 true
Future<bool> confirmAction(BuildContext context, ConfirmSpec spec) async {
  final ok = await showDialog<bool>(context: context, builder: (_) => _ConfirmDialog(spec));
  return ok ?? false;
}

class _ConfirmDialog extends StatefulWidget {
  const _ConfirmDialog(this.spec);

  final ConfirmSpec spec;

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  late final List<bool> _checked = List.filled(widget.spec.checks.length, false);
  final _code = randomCode();
  String _input = '';
  String _phrase = '';
  late int _left;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _left = widget.spec.waitSeconds;
    if (_left > 0) {
      _timer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
        setState(() => _left = (widget.spec.waitSeconds - timer.tick ~/ 5).clamp(0, widget.spec.waitSeconds));
        if (_left == 0) timer.cancel();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _ready =>
      _left == 0 &&
      _checked.every((v) => v) &&
      (!widget.spec.danger || _input.trim().toUpperCase() == _code) &&
      (widget.spec.confirmationPhrase == null || _phrase == widget.spec.confirmationPhrase);

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final spec = widget.spec;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(spec.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
                  IconButton(
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close, size: 17),
                    tooltip: '关闭',
                  ),
                ],
              ),
              if (spec.intro != null) ...[
                const SizedBox(height: 4),
                Muted(spec.intro!),
              ],
              const SizedBox(height: 14),
              for (var i = 0; i < spec.checks.length; i++)
                CheckRow(
                  value: _checked[i],
                  label: spec.checks[i],
                  onChanged: (v) => setState(() => _checked[i] = v),
                ),
              if (spec.danger) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: c.dangerSoft, borderRadius: BorderRadius.circular(9)),
                  child: Row(
                    children: [
                      const Text('请输入确认码 ', style: TextStyle(fontSize: 13.5)),
                      Text(
                        _code,
                        style: TextStyle(
                          fontFamily: 'Consolas',
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                          color: c.danger,
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: 110,
                        child: TextField(
                          autofocus: true,
                          maxLength: _code.length,
                          textAlign: TextAlign.center,
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]'))],
                          style: const TextStyle(fontFamily: 'Consolas', letterSpacing: 2),
                          decoration: const InputDecoration(counterText: ''),
                          onChanged: (v) => setState(() => _input = v),
                          onSubmitted: (_) {
                            if (_ready) Navigator.pop(context, true);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (spec.confirmationPhrase case final phrase?) ...[
                const SizedBox(height: 14),
                Text('请输入「$phrase」', style: const TextStyle(fontSize: 13.5)),
                const SizedBox(height: 8),
                TextField(
                  enableSuggestions: false,
                  autocorrect: false,
                  onChanged: (v) => setState(() => _phrase = v),
                  onSubmitted: (_) {
                    if (_ready) Navigator.pop(context, true);
                  },
                ),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(label: '取消', kind: ButtonKind.ghost, onPressed: () => Navigator.pop(context, false)),
                  const SizedBox(width: 8),
                  AppButton(
                    label: _left > 0 ? '请阅读风险提示（$_left 秒）' : spec.confirmText,
                    kind: spec.danger ? ButtonKind.danger : ButtonKind.primary,
                    onPressed: _ready ? () => Navigator.pop(context, true) : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────── 关闭确认 ─────────────

/// 关闭窗口时用户的选择：收起到系统托盘 / 直接退出 / 取消
enum CloseAction { tray, quit, cancel }

class CloseChoice {
  const CloseChoice(this.action, {this.remember = false});
  final CloseAction action;
  final bool remember;
}

/// 点关闭按钮时由窗口层弹出，样式与项目里的其它对话框一致
class CloseDialog extends StatefulWidget {
  const CloseDialog({super.key, this.onRemember});
  final void Function(CloseBehavior)? onRemember;

  @override
  State<CloseDialog> createState() => _CloseDialogState();
}

class _CloseDialogState extends State<CloseDialog> {
  bool _remember = false;
  String? _error;

  void _choose(CloseAction action) {
    try {
      if (_remember && action != CloseAction.cancel) {
        widget.onRemember?.call(action == CloseAction.tray ? CloseBehavior.tray : CloseBehavior.quit);
      }
      Navigator.pop(context, CloseChoice(action, remember: _remember && action != CloseAction.cancel));
    } catch (_) {
      setState(() => _error = '无法保存关闭设置，请重试或取消勾选“记住本次操作”。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(16)),
                child: Icon(Icons.power_settings_new, size: 24, color: c.accent),
              ),
              const SizedBox(height: 14),
              const Text('要关闭一加工具箱吗？', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10)),
                child: const Text(
                  '选择「收起到系统托盘」后，程序会继续在后台运行，投屏和正在进行的操作都不会中断；'
                  '点击屏幕右下角托盘里的图标即可重新打开。',
                  style: TextStyle(fontSize: 13.5, height: 1.6),
                ),
              ),
              const SizedBox(height: 14),
              CheckRow(value: _remember, label: '记住本次操作（可在设置中更改）', onChanged: (v) => setState(() => _remember = v)),
              if (_error != null) Text(_error!, style: TextStyle(color: c.danger, fontSize: 12.5)),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppButton(
                    label: '取消',
                    kind: ButtonKind.ghost,
                    onPressed: () => _choose(CloseAction.cancel),
                  ),
                  AppButton(
                    label: '关闭程序',
                    onPressed: () => _choose(CloseAction.quit),
                  ),
                  AppButton(
                    label: '收起到系统托盘',
                    icon: Icons.minimize,
                    kind: ButtonKind.primary,
                    onPressed: () => _choose(CloseAction.tray),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────── 非一加设备警告 ─────────────

const brandWarningSeconds = 15;

/// 检测到非一加设备时弹出；倒计时结束前不能关闭（不响应遮罩点击和 Esc）
Future<void> showBrandWarning(BuildContext context, DeviceInfo device) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(canPop: false, child: _BrandWarning(device)),
  );
}

class _BrandWarning extends StatefulWidget {
  const _BrandWarning(this.device);

  final DeviceInfo device;

  @override
  State<_BrandWarning> createState() => _BrandWarningState();
}

class _BrandWarningState extends State<_BrandWarning> {
  int _left = brandWarningSeconds;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _left = _left > 0 ? _left - 1 : 0);
      if (_left == 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final d = widget.device;
    final brand = d.brand ?? d.manufacturer ?? '';
    final model = d.model;
    // 型号里通常已带品牌（如 Xiaomi 15），避免显示成「Xiaomi Xiaomi 15」
    final name = model != null && model.toLowerCase().startsWith(brand.toLowerCase())
        ? model
        : [brand, model].whereType<String>().where((s) => s.isNotEmpty).join(' ');

    Widget bullet(InlineSpan span) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('•  '),
              Expanded(child: Text.rich(span)),
            ],
          ),
        );

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 24, 26, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: c.dangerSoft, shape: BoxShape.circle),
                child: Icon(Icons.gpp_maybe_outlined, size: 28, color: c.danger),
              ),
              const SizedBox(height: 12),
              const Text('检测到非一加设备', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(name.isEmpty ? '未知设备' : name, style: TextStyle(color: c.muted)),
              const SizedBox(height: 16),
              DefaultTextStyle.merge(
                style: const TextStyle(fontSize: 13.5, height: 1.6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('本工具只针对一加手机开发和测试，在其它品牌上从未验证过。'),
                    const SizedBox(height: 8),
                    bullet(const TextSpan(text: '各品牌的解锁方式、分区结构和刷机包格式都不同，这里的命令可能不适用')),
                    bullet(const TextSpan(children: [
                      TextSpan(text: '在其它品牌上执行解锁、Root、刷写等操作，可能导致数据丢失或'),
                      TextSpan(text: '无法开机（变砖）', style: TextStyle(fontWeight: FontWeight.w700)),
                    ])),
                    bullet(const TextSpan(text: 'OPPO、realme 虽然系统相近，但解锁和刷机流程与一加不同，同样未经验证')),
                    const SizedBox(height: 4),
                    const Text('继续使用产生的一切后果需要你自行承担。'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  label: _left > 0 ? '请阅读以上内容（$_left 秒）' : '我已了解风险，继续使用',
                  kind: ButtonKind.danger,
                  onPressed: _left > 0 ? null : () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
