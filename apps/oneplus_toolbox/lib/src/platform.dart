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

XTypeGroup _group(List<String> extensions) =>
    extensions.isEmpty ? const XTypeGroup(label: '所有文件') : XTypeGroup(label: '文件', extensions: extensions);

/// 选单个文件；extensions 为空表示不过滤
Future<String?> pickFile(List<String> extensions) async {
  final f = await openFile(confirmButtonText: '选择', acceptedTypeGroups: [_group(extensions)]);
  return f?.path;
}

/// 选多个文件
Future<List<String>> pickFiles(List<String> extensions) async {
  final files = await openFiles(confirmButtonText: '选择', acceptedTypeGroups: [_group(extensions)]);
  return [for (final f in files) f.path];
}

/// 选择要发送到手机的文件（不确定类型，不过滤）
Future<List<String>> pickAnyFiles() async {
  final files = await openFiles(confirmButtonText: '选择');
  return [for (final f in files) f.path];
}

/// 选目录，取消返回 null
Future<String?> pickDir() => getDirectoryPath(confirmButtonText: '选择');

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

/// 在资源管理器中打开目录（对应 TS 版的 shell.openPath）
Future<void> openDir(String path) async {
  final dir = Directory(path);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  if (Platform.isWindows) {
    await Process.start('explorer.exe', [path]);
  } else {
    await launchUrl(Uri.file(path));
  }
}
