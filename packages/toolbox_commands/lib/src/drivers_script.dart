import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:toolbox_core/toolbox_core.dart';

import 'exec.dart';

/// 设备管理器里的驱动状态（只读，不需要管理员权限）。
///
/// 对应 TS 版 src/main/ops/drivers.ts。

/// 列出和手机有关的 USB 设备及其驱动状态。
/// 按厂商 ID 认：一加 2A70、OPPO 22D9（一加 13 实测用的是这个）、Google 18D1（fastboot 通用接口）、高通 05C6（9008）；
/// 没装驱动的设备在「其他设备」里，名字常常只是「Android」，所以也按名字兜底。
///
/// ConfigManagerErrorCode 默认格式化成 CM_PROB_NONE 这样的枚举名，脚本里转成数字再输出。
/// 与 TS 版逐字一致，改动前请先对照 src/main/ops/drivers.ts 的 PNP_SCRIPT。
const driverCheckScript = r"$ErrorActionPreference='SilentlyContinue';"
    r"Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match 'VID_(2A70|22D9|18D1|05C6)' -or $_.FriendlyName -match 'Android|ADB|Fastboot|Bootloader|QDLoader|OnePlus' } |"
    r"ForEach-Object { '{0}|{1}|{2}|{3}|{4}' -f $_.FriendlyName, $_.InstanceId, $_.Status, $_.Class, [int]$_.ConfigManagerErrorCode }";

/// PowerShell 一次查询的参数
const driverCheckArgs = ['-NoProfile', '-NonInteractive', '-Command', driverCheckScript];

/// 用绝对路径调用 PowerShell，避免 PATH 被改过时找不到
String powershellPath() {
  final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
  final path = p.join(root, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
  return File(path).existsSync() ? path : 'powershell.exe';
}

/// 查询设备管理器。PowerShell 不可用时按「没有设备」处理，不影响其它功能。
Future<ExecResult> queryPnpDevices({CancelToken? cancel, LogSink? log}) async {
  if (!Platform.isWindows) return const ExecResult(0, '', '', '');
  return exec(
    powershellPath(),
    driverCheckArgs,
    cancel: cancel,
    log: log,
    timeout: const Duration(seconds: 30),
    echoOutput: false,
  );
}

/// 设备管理器错误代码 → 说明
const _problem = <num, String>{
  1: '设备配置不正确',
  10: '设备无法启动',
  18: '需要重新安装驱动',
  22: '设备已被禁用',
  28: '没有安装驱动',
  31: '驱动加载失败',
  39: '驱动损坏或丢失',
  43: '设备报告了问题',
  52: '驱动签名验证失败',
};

/// 根据设备类型给出该装哪个驱动
String _driverHint(String name, String id) {
  final both = '$name $id';
  if (RegExp(r'QDLoader|9008|VID_05C6&PID_9008', caseSensitive: false).hasMatch(both)) {
    return '需要高通 QDLoader 9008 驱动';
  }
  if (RegExp(r'fastboot|bootloader', caseSensitive: false).hasMatch(name)) {
    return '需要 Google USB 驱动里的 Android Bootloader Interface（Fastboot 用）';
  }
  if (RegExp(r'adb|composite', caseSensitive: false).hasMatch(name)) {
    return '需要 Google USB 驱动里的 Android ADB Interface';
  }
  return '安装 Google USB 驱动后，在设备管理器里对它「更新驱动程序」并选择驱动所在的文件夹';
}

/// USB 复合设备的父节点（\USB\VID_xxx&PID_xxx\序列号）没有问题时不显示，避免一台手机出现两三行
final _compositeDevice = RegExp(r'^USB Composite Device$|^USB 复合设备$', caseSensitive: false);

/// `Number(code) || 0`：读不出来或为 0 时都当 0，小数按原样保留（与 TS 一致）
num _problemCode(String? code) {
  final parsed = num.tryParse((code ?? '').trim()) ?? 0;
  if (parsed == 0) return 0;
  return parsed == parsed.roundToDouble() ? parsed.toInt() : parsed;
}

/// 解析 [driverCheckScript] 的输出
List<DriverEntry> parseDrivers(String out) {
  final list = <DriverEntry>[];
  for (final line in out.split(RegExp(r'\r?\n'))) {
    final f = line.split('|');
    final name = f.isNotEmpty ? f[0] : '';
    final instanceId = f.length > 1 ? f[1] : null;
    final status = f.length > 2 ? f[2] : null;
    final cls = f.length > 3 ? f[3] : null;
    final code = f.length > 4 ? f[4] : null;
    if (instanceId == null || instanceId.trim().isEmpty) continue;
    final problem = _problemCode(code);
    if (problem == 0 && _compositeDevice.hasMatch(name.trim())) continue;
    final statusText = status?.trim();
    final ok = problem == 0 && statusText == 'OK';
    final bad = problem != 0 || statusText != 'OK';
    final className = cls?.trim();
    list.add(DriverEntry(
      name: name.trim().isEmpty ? '（无名称）' : name.trim(),
      instanceId: instanceId.trim(),
      ok: ok,
      className: className == null || className.isEmpty ? null : className,
      problem: problem != 0
          ? '${_problem[problem] ?? '设备异常'}（代码 $problem）'
          : statusText != 'OK'
              ? '状态 ${statusText == null || statusText.isEmpty ? '未知' : statusText}'
              : null,
      hint: bad ? _driverHint(name, instanceId) : null,
    ));
  }
  return list;
}
