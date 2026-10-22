import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:toolbox_service/toolbox_service.dart';

import '../controller.dart';
import '../platform.dart';
import '../theme.dart';

/// 底部可展开的日志面板
class LogPanel extends StatefulWidget {
  const LogPanel(this.tb, {super.key});

  final ToolboxController tb;

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  bool _open = false;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Color _color(Palette c, LogLevel level) => switch (level) {
        LogLevel.cmd => c.info,
        LogLevel.ok => c.ok,
        LogLevel.warn => c.warn,
        LogLevel.error => c.danger,
        LogLevel.step => c.text,
        LogLevel.info => c.muted,
      };

  String _time(DateTime t) => [t.hour, t.minute, t.second].map((v) => '$v'.padLeft(2, '0')).join(':');

  String _text(LogEntry e) => e.level == LogLevel.cmd ? '\$ ${e.text}' : e.text;

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return ValueListenableBuilder(
      valueListenable: widget.tb.logRevision,
      builder: (context, _, __) {
        final logs = widget.tb.logs;
        final last = logs.isEmpty ? null : logs.last;
        if (_open) _scrollToEnd();
        return Container(
          decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () {
                  setState(() => _open = !_open);
                  if (_open) _scrollToEnd();
                },
                child: SizedBox(
                  height: 36,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      children: [
                        AnimatedRotation(
                          turns: _open ? 0.25 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: Icon(Icons.chevron_right, size: 17, color: c.muted),
                        ),
                        const SizedBox(width: 8),
                        const Text('日志', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(width: 14),
                        if (!_open && last != null)
                          Expanded(
                            child: Text(
                              last.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12.5, color: _color(c, last.level)),
                            ),
                          )
                        else
                          const Spacer(),
                        IconButton(
                          tooltip: '打开完整日志文件夹（保留 30 天）',
                          iconSize: 15,
                          onPressed: () => openDir(widget.tb.service.logDir),
                          icon: const Icon(Icons.folder_open_outlined),
                        ),
                        if (_open) ...[
                          IconButton(
                            tooltip: '复制面板日志（最近 2000 条）',
                            iconSize: 15,
                            onPressed: logs.isEmpty
                                ? null
                                : () => Clipboard.setData(
                                    ClipboardData(text: logs.map((e) => '${_time(e.time)}  ${_text(e)}').join('\n'))),
                            icon: const Icon(Icons.copy_outlined),
                          ),
                          IconButton(
                            tooltip: '仅清空面板，保留日志文件',
                            iconSize: 15,
                            onPressed: widget.tb.clearLogs,
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (_open)
                Container(
                  height: 240,
                  color: c.surface2,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                        padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
                        child: Text(
                          '面板显示最近 2000 条日志；完整操作日志保存在日志文件夹中，保留 30 天。',
                          style: TextStyle(fontSize: 12, color: c.muted),
                        )),
                    Expanded(
                        child: logs.isEmpty
                            ? Center(child: Text('暂无日志', style: TextStyle(color: c.muted, fontSize: 12.5)))
                            : SelectionArea(
                                child: ListView.builder(
                                  controller: _scroll,
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                                  itemCount: logs.length,
                                  itemBuilder: (context, i) {
                                    final e = logs[i];
                                    return Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          width: 68,
                                          child: Text(_time(e.time),
                                              style: TextStyle(fontFamily: 'Consolas', fontSize: 12, color: c.muted)),
                                        ),
                                        Expanded(
                                          child: Text(
                                            _text(e),
                                            style: TextStyle(
                                              fontFamily: 'Consolas',
                                              fontFamilyFallback: const ['Microsoft YaHei UI', 'Segoe UI Symbol'],
                                              fontSize: 12,
                                              height: 1.5,
                                              fontWeight:
                                                  e.level == LogLevel.step ? FontWeight.w600 : FontWeight.normal,
                                              color: _color(c, e.level),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              )),
                  ]),
                ),
            ],
          ),
        );
      },
    );
  }
}
