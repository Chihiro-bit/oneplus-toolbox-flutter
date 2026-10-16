import 'package:toolbox_core/toolbox_core.dart';

import 'patch_script.dart';

/// 联网检测地址和私人 DNS 都是 `settings global` 里的键，不需要 Root，改完重连 Wi-Fi 生效。
///
/// 对应 TS 版 src/main/ops/network.ts 里发到手机上的部分。

/// 一次要读的全部键：联网检测地址 + 私人 DNS
const networkReadKeys = <String>[...captiveKeys, 'private_dns_mode', 'private_dns_specifier'];

/// 一次 adb shell 读完全部键，输出形如 `captive_portal_https_url=https://…`
/// （`settings get` 对没设置过的键输出 null）
///
/// 与 TS 版逐字一致，改动前请先对照 src/main/ops/network.ts 的 READ_KEYS 拼接。
String networkReadScript() => [for (final k in networkReadKeys) 'echo "$k=\$(settings get global $k)"'].join('; ');

/// `settings put global <key> <value>`
List<String> settingsPutArgs(String key, String value) => ['settings', 'put', 'global', key, shq(value)];

/// `settings delete global <key>`
List<String> settingsDeleteArgs(String key) => ['settings', 'delete', 'global', key];
