import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:toolbox_service/toolbox_service.dart';

/// 构建时可用 --dart-define 覆盖，与 TS 版的 TOOLBOX_UPDATE_REPO 环境变量对应
const appVersion = String.fromEnvironment('TOOLBOX_VERSION', defaultValue: '1.4.0');
const defaultUpdateRepo = String.fromEnvironment('TOOLBOX_UPDATE_REPO');

/// 按平台取得各类目录，交给业务层
Future<ToolboxEnvironment> resolveEnvironment() async {
  return ToolboxEnvironment(
    binDir: _findBinDir(),
    dataDir: _dataDir(),
    tempDir: Directory.systemTemp.path,
    documentsDir: (await getApplicationDocumentsDirectory()).path,
    appVersion: appVersion,
    defaultUpdateRepo: defaultUpdateRepo,
  );
}

/// 与 Electron 版的 userData（%APPDATA%\一加工具箱）相同，两个版本共用设置、方案目录缓存和 APK 缓存
String _dataDir() {
  final appData = Platform.environment['APPDATA'];
  if (appData != null && appData.isNotEmpty) return p.join(appData, '一加工具箱');
  return p.join(Platform.environment['HOME'] ?? Directory.systemTemp.path, '.oneplus-toolbox');
}

/// 第三方工具目录：
/// 1. 发布版和 `flutter run`：CMake 安装步骤把仓库的 resources/bin 复制到 exe 旁边的 bin/
/// 2. 找不到时，从 exe 所在目录和当前目录逐级向上找仓库根目录的 resources/bin（例如 `flutter test`）
String _findBinDir() {
  bool hasAdb(String dir) => File(p.join(dir, 'platform-tools', 'adb.exe')).existsSync();

  final exeBin = p.join(p.dirname(Platform.resolvedExecutable), 'bin');
  if (hasAdb(exeBin)) return exeBin;

  for (final start in [p.dirname(Platform.resolvedExecutable), Directory.current.path]) {
    var dir = p.normalize(p.absolute(start));
    while (true) {
      final candidate = p.join(dir, 'resources', 'bin');
      if (hasAdb(candidate)) return candidate;
      final parent = p.dirname(dir);
      if (parent == dir) break;
      dir = parent;
    }
  }
  return exeBin;
}
