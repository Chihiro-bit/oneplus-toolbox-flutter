import 'package:flutter/material.dart';

enum PageId {
  overview('概览', Icons.home_outlined),
  reboot('重启与模式', Icons.power_settings_new),
  bootloader('Bootloader', Icons.lock_outline),
  root('一键 Root', Icons.auto_awesome_outlined),
  slot('A/B 槽位', Icons.swap_horiz),
  apps('应用双开', Icons.filter_none),
  tools('系统工具', Icons.build_outlined),
  settings('设置', Icons.settings_outlined);

  const PageId(this.label, this.icon);
  final String label;
  final IconData icon;
}

typedef Navigate = void Function(PageId page);
