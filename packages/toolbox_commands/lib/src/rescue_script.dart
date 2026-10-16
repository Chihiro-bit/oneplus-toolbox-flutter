/// 「救援与恢复」里发到手机上的脚本（模块禁用 / 启用 / 删除）。
///
/// 对应 TS 版的 src/main/ops/rescue.ts 中的 MODULES_DIR / SU_SCRIPT / SAFE_MODE_TIP，
/// 以及删除模块用的 `magisk --remove-modules` 命令。这里的字符串必须与 TS 版逐字一致。
library;

import 'package:toolbox_core/toolbox_core.dart';

/// 手机上模块所在目录
const modulesDir = '/data/adb/modules';

/// KernelSU / APatch / Magisk 的安全模式说明（禁用模块失败时给用户看的备用办法）
const safeModeTip = 'KernelSU / APatch 可以进安全模式（所有模块临时失效）：开机过程中出现第一屏后连续按几次音量下键；Magisk 的安全模式是开机时一直按住音量下键';

/// 删除全部 Magisk 模块：手机上没有 Magisk 时输出 [noMagiskMarker]
const removeModulesCommand = 'command -v magisk >/dev/null && magisk --remove-modules || echo NO_MAGISK';

/// 手机上找不到 Magisk 时的标记
const noMagiskMarker = 'NO_MAGISK';

/// 给每个模块写入 disable 标记（可恢复）
final _disableScript =
    'n=0; for m in $modulesDir/*; do [ -d "\$m" ] || continue; touch "\$m/disable" && n=\$((n+1)) && echo "MOD|\${m##*/}"; done; echo "RESULT|\$n"';

/// 删掉每个模块的 disable 标记
final _enableScript =
    'n=0; for m in $modulesDir/*; do [ -f "\$m/disable" ] || continue; rm -f "\$m/disable" && n=\$((n+1)) && echo "MOD|\${m##*/}"; done; echo "RESULT|\$n"';

/// disable / enable 在 su 里执行的脚本；remove 不经过 su，返回 null。
/// 输出里 `MOD|<模块名>` 表示处理了哪个模块，最后一行 `RESULT|<个数>`。
String? modulesSuScript(ModuleAction action) => switch (action) {
      ModuleAction.disable => _disableScript,
      ModuleAction.enable => _enableScript,
      ModuleAction.remove => null,
    };

/// 完整的 adb shell 命令：`timeout 30 su -c '<脚本>' 2>&1`。
/// timeout 是必需的：没有管理器能弹授权窗（例如卡开机）时，Magisk 默认 10 秒后拒绝。
String? modulesShellCommand(ModuleAction action) {
  final script = modulesSuScript(action);
  return script == null ? null : "timeout 30 su -c '$script' 2>&1";
}

final _modulesResult = RegExp(r'^RESULT\|(\d+)', multiLine: true);

/// 从脚本输出里取 `RESULT|<个数>`；没拿到 Root 授权时输出里不会有它
int? parseModulesResult(String out) {
  final m = _modulesResult.firstMatch(out.replaceAll('\r', ''));
  return m == null ? null : int.parse(m[1]!);
}
