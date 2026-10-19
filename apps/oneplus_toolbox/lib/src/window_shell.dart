import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:toolbox_service/toolbox_service.dart';
import 'package:window_manager/window_manager.dart';

import 'widgets/dialogs.dart';

/// 窗口与系统托盘：点关闭按钮时先问「收起到系统托盘，还是关闭程序」。
/// 对应 TS 版 src/main/index.ts 的托盘与关闭确认逻辑。
///
/// 关闭确认由界面里的 [CloseDialog] 弹出（和项目其它对话框一致）；
/// 选择收起后窗口隐藏、程序继续在后台运行，托盘菜单可以重新打开或退出。
class WindowShell with WindowListener, TrayListener {
  WindowShell({required this.navigatorKey, required this.service});

  final GlobalKey<NavigatorState> navigatorKey;
  final ToolboxService service;

  bool _trayReady = false;
  bool _dialogOpen = false;
  bool _quitting = false;

  /// 在 runApp 之前初始化：拦截原生关闭按钮，并挂上托盘事件
  Future<void> init() async {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    trayManager.addListener(this);
  }

  @override
  void onWindowClose() {
    if (_quitting) return;
    unawaited(_requestClose());
  }

  @override
  void onTrayIconMouseDown() => unawaited(_showWindow());

  @override
  void onTrayIconRightMouseDown() => unawaited(trayManager.popUpContextMenu());

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show') {
      unawaited(_showWindow());
    } else if (menuItem.key == 'quit') {
      unawaited(quit());
    }
  }

  /// 弹出关闭确认框。界面还没加载好时直接退出（与 TS 版 rendererReady 的处理一致）
  Future<void> _requestClose() async {
    await _showWindow();
    if (_dialogOpen) return;
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) {
      await quit();
      return;
    }
    _dialogOpen = true;
    final action = await showDialog<CloseAction>(context: context, builder: (_) => const CloseDialog());
    _dialogOpen = false;
    await resolveClose(action ?? CloseAction.cancel);
  }

  /// 界面里的关闭确认框给出选择后调用
  Future<void> resolveClose(CloseAction action) => switch (action) {
        CloseAction.cancel => Future<void>.value(),
        CloseAction.tray => _hideToTray(),
        CloseAction.quit => quit(),
      };

  Future<void> _showWindow() async {
    try {
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {
      // 退出过程中窗口可能已经销毁，忽略
    }
  }

  /// 收起到系统托盘；没有图标可用时退回最小化，免得窗口消失后找不回来
  Future<void> _hideToTray() async {
    if (!await _initTray()) {
      await windowManager.minimize();
      return;
    }
    await windowManager.hide();
  }

  Future<bool> _initTray() async {
    if (_trayReady) return true;
    try {
      await trayManager.setIcon('assets/tray.ico');
    } catch (_) {
      return false;
    }
    _trayReady = true;
    try {
      await trayManager.setToolTip('一加工具箱');
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show', label: '显示主界面'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: '退出'),
      ]));
    } catch (_) {
      // 菜单不可用时仍然可以隐藏窗口，点击托盘图标可以恢复
    }
    return true;
  }

  /// 真正退出：停止轮询、关闭 adb server，再结束进程
  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    service.dispose();
    try {
      await trayManager.destroy();
    } catch (_) {
      // 托盘可能还没创建
    }
    await windowManager.destroy();
  }
}
