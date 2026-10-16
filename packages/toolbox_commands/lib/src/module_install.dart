/// 安装 Root 模块（Magisk / KernelSU / APatch 的模块格式相同）。
///
/// 对应 TS 版 src/main/ops/modules.ts 里发到手机上的部分。
library;

final _moduleProp = RegExp(r'\s(?:\./)?module\.prop\s*$', multiLine: true);

/// `7z l` 的输出里根目录有 module.prop，才是 Magisk / KernelSU / APatch 模块（防止误把卡刷包当模块装）
bool isModuleListing(String out) => _moduleProp.hasMatch(out);

/// 按当前的 Root 方案调用它自己的安装命令，三家的模块格式相同。
/// ksud / apd 在 /data/adb 下、只有 Root 能看到，所以整段在 su 里判断。
///
/// 与 TS 版逐字一致，改动前请先对照 src/main/ops/modules.ts 的 installScript。
String installScript(String zip) => [
      'Z=$zip',
      r'if [ -x /data/adb/ksud ]; then /data/adb/ksud module install "$Z"',
      r'elif [ -x /data/adb/apd ]; then /data/adb/apd module install "$Z"',
      r'elif command -v magisk >/dev/null 2>&1; then magisk --install-module "$Z"',
      r'else echo NO_TOOL; exit 0; fi',
      r'echo "EXIT|$?"',
    ].join('\n');

/// 没找到 Magisk / KernelSU / APatch 的命令行工具
const noModuleToolMarker = 'NO_TOOL';

class ModuleInstallOutcome {
  const ModuleInstallOutcome({required this.noTool, this.code});

  /// 手机上有 Root，但 /data/adb 下没有三家的命令行工具
  final bool noTool;

  /// 安装脚本的退出码；为 null 表示 [installScript] 的 `EXIT|` 那行没出现（没拿到 Root 授权）
  final String? code;
}

final _exitCode = RegExp(r'^EXIT\|(\d+)', multiLine: true);

/// 解析 `su -c` 里跑完 [installScript] 的输出
ModuleInstallOutcome parseModuleInstall(String out) => ModuleInstallOutcome(
      noTool: out.contains(noModuleToolMarker),
      code: _exitCode.firstMatch(out)?.group(1),
    );
