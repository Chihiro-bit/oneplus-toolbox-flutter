import 'package:flutter/material.dart';

import '../controller.dart';
import '../platform.dart';
import '../theme.dart';
import 'common.dart';

/// 页面顶部的运行状态：进行中显示步骤和取消按钮，结束后显示结果
class RunBanner extends StatelessWidget {
  const RunBanner(this.tb, {super.key});

  final ToolboxController tb;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final run = tb.run;
    if (!run.running && run.result == null) return const SizedBox.shrink();

    if (run.running) {
      return _frame(
        context,
        bg: c.surface,
        border: c.border,
        leading: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: c.accent)),
        title: run.title ?? '',
        body: run.step ?? '',
        actions: [AppButton(label: '取消', kind: ButtonKind.ghost, onPressed: tb.cancel)],
        bottom: LinearProgressIndicator(minHeight: 2, color: c.accent, backgroundColor: Colors.transparent),
      );
    }

    final r = run.result!;
    final fg = r.ok ? c.ok : c.danger;
    return _frame(
      context,
      bg: r.ok ? c.okSoft : c.dangerSoft,
      border: fg.withOpacity(0.35),
      leading: Icon(r.ok ? Icons.check_circle_outline : Icons.highlight_off, size: 19, color: fg),
      title: '${run.title} · ${r.ok ? '完成' : '失败'}',
      body: r.message,
      actions: [
        if (r.outputPath != null)
          AppButton(
            label: '打开文件位置',
            icon: Icons.folder_open_outlined,
            kind: ButtonKind.ghost,
            onPressed: () => showInFolder(r.outputPath!),
          ),
        IconButton(onPressed: tb.dismiss, icon: const Icon(Icons.close, size: 17), tooltip: '关闭'),
      ],
    );
  }

  Widget _frame(
    BuildContext context, {
    required Color bg,
    required Color border,
    required Widget leading,
    required String title,
    required String body,
    required List<Widget> actions,
    Widget? bottom,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      SelectableText(body,
                          style: TextStyle(fontSize: 13, color: context.palette.text.withOpacity(0.85))),
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
          ),
          if (bottom != null) bottom,
        ],
      ),
    );
  }
}
