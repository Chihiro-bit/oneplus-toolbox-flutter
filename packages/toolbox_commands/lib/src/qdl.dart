import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:toolbox_core/toolbox_core.dart';

import 'exec.dart';

// ───────────── 9008（高通 EDL）检测 ─────────────
//
// 9008 既不归 adb 也不归 fastboot 管，只能靠 PnP 枚举（只读，不需要管理员权限）。

final _edlName = RegExp(r'QDLoader|(?<!\d)900[8E](?!\d)', caseSensitive: false);

const _pnpScript = r"$ErrorActionPreference='SilentlyContinue';"
    r"Get-PnpDevice -PresentOnly | Where-Object { $_.FriendlyName -match 'QDLoader|9008|900E' } |"
    r"ForEach-Object { '{0}|{1}' -f $_.FriendlyName, $_.InstanceId }";

/// 解析 PowerShell 输出，得到在线的 9008 设备。PowerShell 侧已按名称粗筛，这里再精确判定。
List<EdlDevice> parseEdlDevices(String out) {
  final devices = <EdlDevice>[];
  for (final line in out.replaceAll('\r', '').split('\n')) {
    final name = line.split('|').first;
    if (!_edlName.hasMatch(name)) continue;
    devices.add(EdlDevice(
      port: RegExp(r'\((COM\d+)\)', caseSensitive: false).firstMatch(name)?[1]?.toUpperCase() ?? '',
      name: name.trim(),
    ));
  }
  return devices;
}

/// 用绝对路径调用 PowerShell，避免 PATH 被改过时找不到
String _powershellPath() {
  final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
  final path = p.join(root, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
  return File(path).existsSync() ? path : 'powershell.exe';
}

/// 列出当前在线的 9008 设备。PowerShell 不可用时按「没有设备」处理，不影响其它功能。
Future<List<EdlDevice>> listEdlDevices([CancelToken? cancel]) async {
  if (!Platform.isWindows) return const [];
  final r = await exec(
    _powershellPath(),
    ['-NoProfile', '-NonInteractive', '-Command', _pnpScript],
    cancel: cancel,
    timeout: const Duration(seconds: 20),
    echoOutput: false,
  );
  return parseEdlDevices(r.all);
}

// ───────────── qdl 命令 ─────────────

/// 高通 9008 / EDL 刷写工具 qdl。
///
/// qdl 把正常信息写 stdout、错误写 stderr，exec 里都按 info 记录；这里按关键字
/// 把失败原因提升为 error，日志面板里一眼能看见。
class Qdl {
  const Qdl(this.exe, {this.cancel, this.log});

  final String exe;
  final CancelToken? cancel;
  final LogSink? log;

  static final _errorWords = RegExp(r'failed|error|unable|invalid|refus|reject|not found', caseSensitive: false);

  LogSink? get _log {
    final sink = log;
    if (sink == null) return null;
    return (level, text) =>
        sink(level == LogLevel.info && _errorWords.hasMatch(text) ? LogLevel.error : level, text);
  }

  Future<ExecResult> run(List<String> args, {required Duration timeout}) =>
      exec(exe, args, cancel: cancel, log: _log, timeout: timeout);

  /// 把参数拼成便于用户核对的命令行
  static String asCommand(List<String> args) => 'qdl ${args.join(' ')}';
}
