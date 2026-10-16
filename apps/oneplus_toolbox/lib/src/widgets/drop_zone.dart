import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// 从资源管理器把文件拖进窗口的区域，对应 TS 版各页面里的 `.dropzone`
/// （安装应用、安装 Root 模块、发送文件）。
///
/// 拖入时高亮边框；落下后把文件的磁盘路径交给 [onFiles]。选择和拖拽都走同一个回调，
/// 页面自己决定「这些文件能干什么」。
class DropZone extends StatefulWidget {
  const DropZone({
    super.key,
    required this.child,
    required this.onFiles,
    this.enable = true,
    this.radius = 12,
  });

  final Widget child;

  /// 落下文件后回调，参数是文件在磁盘上的绝对路径
  final void Function(List<String> paths) onFiles;

  /// 操作进行中时传 false：DropTarget 在前方有别的页面时仍然会收到拖拽事件
  final bool enable;
  final double radius;

  @override
  State<DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<DropZone> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return DropTarget(
      enable: widget.enable,
      onDragEntered: (_) => setState(() => _over = true),
      onDragExited: (_) => setState(() => _over = false),
      onDragDone: (detail) {
        setState(() => _over = false);
        final paths = [for (final f in detail.files) f.path];
        if (paths.isNotEmpty) widget.onFiles(paths);
      },
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: _over ? c.accent : c.border,
          radius: widget.radius,
          width: _over ? 1.6 : 1.2,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _over ? c.accentSoft : c.surface,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// 虚线圆角边框（CSS 的 dashed border 在 Flutter 里要自己画）
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius, required this.width});

  final Color color;
  final double radius;
  final double width;

  static const _dash = 5.0;
  static const _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(width / 2, width / 2, size.width - width, size.height - width),
        Radius.circular(radius),
      ));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + _dash), paint);
        d += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color || old.radius != radius || old.width != width;
}
