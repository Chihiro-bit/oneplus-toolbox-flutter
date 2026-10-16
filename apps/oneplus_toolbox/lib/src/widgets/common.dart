import 'package:flutter/material.dart';
import 'package:toolbox_service/toolbox_service.dart';

import '../controller.dart';
import '../theme.dart';

// ───────────── 按设备状态决定按钮是否可用 ─────────────

class Gate {
  const Gate(this.reason);

  /// 不可用的原因，可用时为 null
  final String? reason;

  bool get disabled => reason != null;

  /// 操作进行中时不显示原因提示（横幅已经说明了）
  String? hint(ToolboxController tb) => tb.run.running ? null : reason;
}

Gate gate(ToolboxController tb, Set<DeviceMode> allowed) {
  final d = tb.device;
  if (tb.run.running) return const Gate('有操作正在进行');
  if (d.mode == DeviceMode.none) return const Gate('未连接设备');
  // 连着多台但没选中当前这台时一律拒绝，避免刷错手机
  if (d.needsPick) return const Gate('连接了多台设备，请先在左下角选择要操作的那一台');
  if (!allowed.contains(d.mode)) {
    return Gate('需要在 ${allowed.map((m) => m.label).join(' / ')} 模式下使用');
  }
  return const Gate(null);
}

// ───────────── 左下角的多设备选择框 ─────────────

/// 连着多台设备时，先在这里选定要操作的那一台（对应 TS 版 App.tsx 的 device-picker）
class DevicePicker extends StatelessWidget {
  const DevicePicker({super.key, required this.device, required this.onSelected, this.enabled = true});

  final DeviceInfo device;

  /// 选中设备的序列号，接到 ToolboxService.selectDevice()
  final ValueChanged<String?> onSelected;

  /// 有操作进行中时不允许切换（对应 TS 版的 disabled={tb.run.running}）
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    if (device.devices.isEmpty) return const SizedBox.shrink();
    final selected = device.selected;
    // 选中的设备可能不在线（例如正卡在开机），列表里补一项占位，否则下拉框的 value 找不到对应项
    final offline = selected != null && !device.devices.any((x) => x.serial == selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text('连接了 ${device.devices.length} 台设备，操作哪一台？', style: TextStyle(fontSize: 12.5, color: c.muted)),
        ),
        DropdownButtonFormField<String?>(
          value: selected,
          isDense: true,
          isExpanded: true,
          style: TextStyle(fontSize: 13, color: c.text),
          onChanged: enabled ? onSelected : null,
          items: [
            if (selected == null) const DropdownMenuItem<String?>(value: null, child: Text('请选择…')),
            if (offline)
              DropdownMenuItem<String?>(
                  value: selected, child: Text('$selected（不在线）', overflow: TextOverflow.ellipsis)),
            for (final x in device.devices)
              DropdownMenuItem<String?>(
                value: x.serial,
                child: Text('${x.label ?? x.serial} · ${x.mode.label}', overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
      ],
    );
  }
}

// ───────────── 页面骨架 ─────────────

class PageHeader extends StatelessWidget {
  const PageHeader(this.title, this.desc, {super.key});

  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(desc, style: TextStyle(color: context.palette.muted, fontSize: 13.5)),
        ],
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(20)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x0F101828), blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: child,
    );
  }
}

enum Tone { info, warn, danger }

class Callout extends StatelessWidget {
  const Callout(this.tone, {super.key, this.text, this.child}) : assert(text != null || child != null);

  final Tone tone;
  final String? text;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final (fg, bg) = switch (tone) {
      Tone.info => (c.info, c.infoSoft),
      Tone.warn => (c.warn, c.warnSoft),
      Tone.danger => (c.danger, c.dangerSoft),
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.warning_amber_rounded, size: 17, color: fg),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DefaultTextStyle.merge(
              style: TextStyle(color: c.text, fontSize: 13.5, height: 1.55),
              child: child ?? Text(text!),
            ),
          ),
        ],
      ),
    );
  }
}

class ModeBadge extends StatelessWidget {
  const ModeBadge(this.mode, {super.key, this.dotOnly = false});

  final DeviceMode mode;

  /// 只显示圆点（侧边栏）
  final bool dotOnly;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final (fg, bg) = switch (mode) {
      DeviceMode.system => (c.ok, c.okSoft),
      DeviceMode.fastboot || DeviceMode.fastbootd => (c.info, c.infoSoft),
      DeviceMode.recovery || DeviceMode.unauthorized => (c.warn, c.warnSoft),
      DeviceMode.edl => (c.danger, c.dangerSoft),
      DeviceMode.none => (c.muted, c.surface2),
    };
    final dot = Container(width: 7, height: 7, decoration: BoxDecoration(color: fg, shape: BoxShape.circle));
    if (dotOnly) return dot;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          dot,
          const SizedBox(width: 6),
          Text(mode.label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// 小圆角标签，例如方案的修补方式
class TagChip extends StatelessWidget {
  const TagChip(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? context.palette.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: fg.withOpacity(0.45)),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(text, style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }
}

/// 卡片顶部的方形图标
class ActionIcon extends StatelessWidget {
  const ActionIcon(this.icon, {super.key, this.tone});

  final IconData icon;

  /// null=中性，info=强调色，danger=危险色
  final Tone? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final (fg, bg) = switch (tone) {
      Tone.info => (c.accent, c.accentSoft),
      Tone.danger => (c.danger, c.dangerSoft),
      _ => (c.text, c.surface2),
    };
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, size: 20, color: fg),
    );
  }
}

class CardTitle extends StatelessWidget {
  const CardTitle(this.text, {super.key, this.top = 0});

  final String text;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: 10),
      child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
    );
  }
}

/// 次要说明文字
class Muted extends StatelessWidget {
  const Muted(this.text, {super.key, this.small = false, this.color});

  final String text;
  final bool small;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(color: color ?? context.palette.muted, fontSize: small ? 12.5 : 13.5, height: 1.55),
    );
  }
}

/// 按钮不可用的原因
class GateHint extends StatelessWidget {
  const GateHint(this.text, {super.key});

  final String? text;

  @override
  Widget build(BuildContext context) {
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(text!, style: TextStyle(color: context.palette.muted, fontSize: 12.5)),
    );
  }
}

/// 带不可用原因提示的按钮包装
class Gated extends StatelessWidget {
  const Gated({super.key, required this.reason, required this.child});

  final String? reason;
  final Widget child;

  @override
  Widget build(BuildContext context) => reason == null ? child : Tooltip(message: reason!, child: child);
}

enum ButtonKind { primary, secondary, danger, ghost }

/// 统一样式的按钮。onPressed 为 null 时不可用
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = ButtonKind.secondary,
    this.icon,
    this.large = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final ButtonKind kind;
  final IconData? icon;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
        Text(label),
      ],
    );
    final padding = large ? const EdgeInsets.symmetric(horizontal: 20, vertical: 15) : null;
    return switch (kind) {
      ButtonKind.primary => FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(backgroundColor: c.accent, foregroundColor: Colors.white, padding: padding),
          child: child,
        ),
      ButtonKind.danger => FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(backgroundColor: c.danger, foregroundColor: Colors.white, padding: padding),
          child: child,
        ),
      ButtonKind.secondary =>
        OutlinedButton(onPressed: onPressed, style: OutlinedButton.styleFrom(padding: padding), child: child),
      ButtonKind.ghost => TextButton(onPressed: onPressed, child: child),
    };
  }
}

/// 复选框 + 文字
class CheckRow extends StatelessWidget {
  const CheckRow({super.key, required this.value, required this.label, required this.onChanged});

  final bool value;
  final String label;

  /// null 时不可用
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: enabled ? () => onChanged!(!value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              height: 24,
              child: Checkbox(value: value, onChanged: enabled ? (v) => onChanged!(v ?? false) : null),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  label,
                  style: TextStyle(fontSize: 13.5, color: enabled ? null : context.palette.muted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 分段选择
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.value, required this.options, required this.onChanged, this.disabled});

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final bool Function(T)? disabled;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration:
          BoxDecoration(color: c.surface2, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(9)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (v, label) in options)
            _segment(context, label,
                selected: v == value, enabled: !(disabled?.call(v) ?? false), onTap: () => onChanged(v)),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, String label,
      {required bool selected, required bool enabled, required VoidCallback onTap}) {
    final c = context.palette;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? c.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            boxShadow:
                selected ? const [BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1))] : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: enabled ? (selected ? c.text : c.muted) : c.muted.withOpacity(0.5),
            ),
          ),
        ),
      ),
    );
  }
}

/// 文件路径输入框 + 「浏览…」按钮
class PathField extends StatelessWidget {
  const PathField({
    super.key,
    required this.icon,
    required this.hint,
    required this.onBrowse,
    this.controller,
    this.value,
    this.onChanged,
  });

  final IconData icon;
  final String hint;
  final VoidCallback onBrowse;

  /// 可编辑时传 controller，只读时传 value
  final TextEditingController? controller;
  final String? value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final decoration = InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 17, color: c.muted),
      prefixIconConstraints: const BoxConstraints(minWidth: 38),
    );
    final empty = value == null || value!.isEmpty;
    return Row(
      children: [
        Expanded(
          child: controller != null
              ? TextField(
                  controller: controller,
                  onChanged: onChanged,
                  style: const TextStyle(fontSize: 13.5),
                  decoration: decoration,
                )
              : InputDecorator(
                  decoration: decoration,
                  isEmpty: empty,
                  child: Text(empty ? '' : value!,
                      style: const TextStyle(fontSize: 13.5), overflow: TextOverflow.ellipsis),
                ),
        ),
        const SizedBox(width: 8),
        AppButton(label: '浏览…', onPressed: onBrowse),
      ],
    );
  }
}

/// 可选中复制的等宽文字
class Code extends StatelessWidget {
  const Code(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration:
          BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(5)),
      child: SelectableText(text, style: const TextStyle(fontFamily: 'Consolas', fontSize: 12.5)),
    );
  }
}

/// 链接样式的文字按钮
class LinkButton extends StatelessWidget {
  const LinkButton(this.label, {super.key, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: c.accent, fontSize: 13)),
          const SizedBox(width: 3),
          Icon(Icons.arrow_forward, size: 13, color: c.accent),
        ],
      ),
    );
  }
}

/// 自适应网格：按最小宽度排列等宽的子项，每行高度取该行最高者
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid(
      {super.key, required this.children, this.minItemWidth = 220, this.maxColumns = 4, this.gap = 14});

  final List<Widget> children;
  final double minItemWidth;
  final int maxColumns;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final cols = ((box.maxWidth + gap) ~/ (minItemWidth + gap)).clamp(1, maxColumns);
      final rows = <Widget>[];
      for (var i = 0; i < children.length; i += cols) {
        final row = children.sublist(i, (i + cols).clamp(0, children.length));
        rows.add(IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < cols; j++) ...[
                if (j > 0) SizedBox(width: gap),
                Expanded(child: j < row.length ? row[j] : const SizedBox.shrink()),
              ],
            ],
          ),
        ));
      }
      return Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[if (i > 0) SizedBox(height: gap), rows[i]],
        ],
      );
    });
  }
}
