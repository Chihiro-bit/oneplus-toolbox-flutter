import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:toolbox_service/toolbox_service.dart';

import 'src/app.dart';
import 'src/controller.dart';
import 'src/environment.dart';
import 'src/window_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final service = ToolboxService(await resolveEnvironment());
  final controller = ToolboxController(service);
  final navigatorKey = GlobalKey<NavigatorState>();

  // 拦截关闭按钮：询问收起到系统托盘还是退出（界面里的 CloseDialog）
  final window = WindowShell(navigatorKey: navigatorKey, service: service);
  await window.init();

  // 系统注销 / 关机等不经过窗口关闭按钮的退出，关闭时也要清掉 adb server，避免残留进程占用 5037 端口
  AppLifecycleListener(
    onExitRequested: () async {
      service.dispose();
      return AppExitResponse.exit;
    },
  );

  runApp(ToolboxApp(controller: controller, navigatorKey: navigatorKey));
}
