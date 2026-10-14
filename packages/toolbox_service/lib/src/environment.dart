/// 运行环境：各类目录和版本号，由界面层按平台取得后传入
class ToolboxEnvironment {
  const ToolboxEnvironment({
    required this.binDir,
    required this.dataDir,
    required this.tempDir,
    required this.documentsDir,
    required this.appVersion,
    this.defaultUpdateRepo = '',
  });

  /// 第三方工具所在目录（adb、fastboot 等）
  final String binDir;

  /// 设置、目录缓存、APK 缓存的存放位置
  final String dataDir;

  /// 修补过程中的临时文件
  final String tempDir;

  /// 修补后的镜像另存到「<documentsDir>/一加工具箱」
  final String documentsDir;

  final String appVersion;

  /// 设置里「更新仓库」的默认值
  final String defaultUpdateRepo;
}
