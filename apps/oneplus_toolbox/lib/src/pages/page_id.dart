import 'package:flutter/material.dart';
import 'package:toolbox_service/toolbox_service.dart';

enum PageId {
  overview('概览', Icons.home_outlined),
  reboot('重启与模式', Icons.power_settings_new),
  bootloader('Bootloader', Icons.lock_outline),
  root('一键 Root', Icons.auto_awesome_outlined),
  diagnose('开机诊断', Icons.monitor_heart_outlined),
  rescue('救援与恢复', Icons.health_and_safety_outlined),
  slot('A/B 槽位', Icons.swap_horiz),
  edl('9008 救砖', Icons.healing_outlined),
  apps('应用管理', Icons.content_copy_outlined),
  tools('系统工具', Icons.build_outlined),
  settings('设置', Icons.settings_outlined);

  const PageId(this.label, this.icon);
  final String label;
  final IconData icon;

  /// 侧边栏里的显示顺序。9008 已停用（[Features.edl] 为 false）时入口隐藏。
  static List<PageId> get navigation => [
        for (final p in values)
          if (p != settings && (p != edl || Features.edl)) p
      ];
}

typedef Navigate = void Function(PageId page);
