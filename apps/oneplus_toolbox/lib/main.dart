import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:toolbox_service/toolbox_service.dart';

import 'src/app.dart';
import 'src/controller.dart';
import 'src/environment.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final service = ToolboxService(await resolveEnvironment());
  final controller = ToolboxController(service);

  // 关闭窗口时关闭 adb server，避免残留进程占用 5037 端口
  AppLifecycleListener(
    onExitRequested: () async {
      service.dispose();
      return AppExitResponse.exit;
    },
  );

  runApp(ToolboxApp(controller: controller));
}
