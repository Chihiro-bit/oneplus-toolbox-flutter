import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:url_launcher/url_launcher.dart';

/// 选择 ROM 包（全量升级包）
Future<String?> pickRom() async {
  final f = await openFile(
    confirmButtonText: '选择',
    acceptedTypeGroups: const [
      XTypeGroup(label: 'ROM 包', extensions: ['zip', 'ozip', 'bin']),
      XTypeGroup(label: '所有文件'),
    ],
  );
  return f?.path;
}

/// 选择 APK
Future<String?> pickApk() async {
  final f = await openFile(
    confirmButtonText: '选择',
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Android 安装包', extensions: ['apk']),
    ],
  );
  return f?.path;
}

/// 用浏览器打开链接，只接受 http(s)
Future<void> openExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// 在资源管理器中显示文件
Future<void> showInFolder(String path) async {
  if (Platform.isWindows) {
    await Process.start('explorer.exe', ['/select,', path]);
  } else {
    await launchUrl(Uri.file(File(path).parent.path));
  }
}
