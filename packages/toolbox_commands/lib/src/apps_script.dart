/// 应用管理相关的手机端脚本与 adb 命令参数。
///
/// 这里只负责「发到手机上的是什么」，业务判断（保护名单、Root 检查、失败提示）在 toolbox_service 里。
/// 对应 TS 版的 src/main/ops/apps.ts（应用列表脚本本身见 app_list.dart）与 src/main/ops/permissions.ts。
library;

/// 应用列表里标记「已双开」的标记名
const clonedMark = 'CLONED';

/// 预装应用列表里标记「已对当前用户安装」的标记名
const installedMark = 'INSTALLED';

/// 预装应用 / 第三方应用列表里标记「已停用（冻结）」的标记名
const disabledMark = 'DISABLED';

/// 列出双开空间（用户 999）里已安装的包名：`pm list packages -3 --user 999`。
/// 输出「CLONED|包名」行，与其它标记行格式一致，一次解析即可。
List<String> listClonedPackagesScript(String user) =>
    ['for p in \$(pm list packages -3 --user $user | sed "s/package://"); do echo "$clonedMark|\$p"; done'];

/// 列出预装应用里已对当前用户安装的包名：`pm list packages -s --user 0`
List<String> listInstalledSystemPackagesScript() =>
    ['for p in \$(pm list packages -s --user 0 | sed "s/package://"); do echo "$installedMark|\$p"; done'];

/// 列出预装应用里已停用的包名：`pm list packages -s -d --user 0`
List<String> listDisabledSystemPackagesScript() =>
    ['for p in \$(pm list packages -s -d --user 0 | sed "s/package://"); do echo "$disabledMark|\$p"; done'];

/// 列出第三方应用里已停用的包名：`pm list packages -3 -d --user 0`
List<String> listDisabledUserPackagesScript() =>
    ['for p in \$(pm list packages -3 -d --user 0 | sed "s/package://"); do echo "$disabledMark|\$p"; done'];

/// 卸载预装应用：只对当前用户卸载，系统分区里的 APK 还在
List<String> debloatRemoveArgs(String pkg) => ['pm', 'uninstall', '-k', '--user', '0', pkg];

/// 恢复被卸载的预装应用
List<String> debloatRestoreArgs(String pkg) => ['pm', 'install-existing', '--user', '0', pkg];

/// 冻结（停用）应用：应用和数据都还在，只是不能运行、图标从桌面消失
List<String> freezeAppArgs(String pkg) => ['pm', 'disable-user', '--user', '0', pkg];

/// 解冻应用
List<String> unfreezeAppArgs(String pkg) => ['pm', 'enable', '--user', '0', pkg];

/// 读取应用申请的权限：`dumpsys package <包名>`
List<String> appPermissionsArgs(String pkg) => ['dumpsys', 'package', pkg];

/// 授予 / 撤销权限
List<String> grantPermissionArgs(String pkg, String permission, {required bool grant}) =>
    ['pm', grant ? 'grant' : 'revoke', pkg, permission];

/// 读当前默认输入法（冻结输入法前检查）
List<String> defaultInputMethodArgs() => ['settings', 'get', 'secure', 'default_input_method'];

/// 读当前桌面（冻结桌面前检查）
List<String> homeActivityArgs() => [
      'cmd',
      'package',
      'resolve-activity',
      '--brief',
      '-a',
      'android.intent.action.MAIN',
      '-c',
      'android.intent.category.HOME',
    ];

/// `settings get secure default_input_method` 的输出形如 `com.baidu.input/.ImeService`（或 `null`），取出包名
String? componentPackage(String out) {
  final first = out.trim().split(RegExp(r'\r?\n')).first.trim();
  final pkg = first.split('/').first.trim();
  return pkg.isEmpty || pkg == 'null' ? null : pkg;
}

/// `cmd package resolve-activity --brief` 的输出最后一行形如 `com.android.launcher/.Launcher`，取出包名
String? resolvedActivityPackage(String out) {
  final lines = out.trim().split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
  if (lines.isEmpty) return null;
  final pkg = lines.last.trim().split('/').first.trim();
  return pkg.isEmpty || pkg == 'null' ? null : pkg;
}
