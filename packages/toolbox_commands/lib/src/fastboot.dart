import 'package:toolbox_core/toolbox_core.dart';

import 'adb.dart';
import 'exec.dart';

/// 解析 `fastboot devices` 的输出
List<RawDevice> parseFastbootDevices(String out) => [
      for (final m in RegExp(r'^(\S+)\s+fastboot\b', multiLine: true).allMatches(out.replaceAll('\r', '')))
        RawDevice(m[1]!, DeviceMode.fastboot)
    ];

/// 从 `fastboot getvar` 的输出中取值，形如 "unlocked: yes"
String? parseGetvar(String out, String name) {
  final m = RegExp('^${RegExp.escape(name)}:[ \\t]*(.*)\$', multiLine: true).firstMatch(out.replaceAll('\r', ''));
  final v = m?[1]?.trim();
  return v == null || v.isEmpty ? null : v;
}

/// 从 `fastboot oem device-info` 或 `getvar unlocked` 的输出判断解锁状态
bool? parseUnlocked({required String deviceInfo, String? getvarUnlocked}) {
  if (RegExp(r'Device unlocked:\s*true', caseSensitive: false).hasMatch(deviceInfo)) return true;
  if (RegExp(r'Device unlocked:\s*false', caseSensitive: false).hasMatch(deviceInfo)) return false;
  return switch (getvarUnlocked) { 'yes' => true, 'no' => false, _ => null };
}

/// fastboot 命令。fastboot 把大部分信息写在 stderr，判断结果时看 [ExecResult.all]。
class Fastboot {
  const Fastboot(this.exe, {this.cancel, this.log});

  final String exe;
  final CancelToken? cancel;
  final LogSink? log;

  Future<List<RawDevice>> devices() async {
    final r = await exec(exe, ['devices'], cancel: cancel, timeout: const Duration(seconds: 10));
    return parseFastbootDevices(r.all);
  }

  /// `fastboot -s <serial> <args>`
  Future<ExecResult> run(String serial, List<String> args, {Duration timeout = const Duration(seconds: 60)}) =>
      exec(exe, ['-s', serial, ...args], cancel: cancel, log: log, timeout: timeout);

  /// 读取变量（不写日志）
  Future<String?> getvar(String serial, String name) async {
    final r = await exec(exe, ['-s', serial, 'getvar', name], cancel: cancel, timeout: const Duration(seconds: 10));
    return parseGetvar(r.all, name);
  }

  /// 读取解锁状态：先 oem device-info，再 getvar unlocked
  Future<bool?> isUnlocked(String serial) async {
    final info =
        await exec(exe, ['-s', serial, 'oem', 'device-info'], cancel: cancel, timeout: const Duration(seconds: 10));
    final fromInfo = parseUnlocked(deviceInfo: info.all);
    if (fromInfo != null) return fromInfo;
    return parseUnlocked(deviceInfo: '', getvarUnlocked: await getvar(serial, 'unlocked'));
  }

  /// `fastboot reboot [target]`，target 为 null 时重启到系统
  Future<ExecResult> reboot(String serial, [String? target]) => run(serial, ['reboot', if (target != null) target]);

  Future<ExecResult> flash(String serial, String partition, String image) =>
      run(serial, ['flash', partition, image], timeout: const Duration(minutes: 5));

  Future<ExecResult> setActiveOther(String serial) => run(serial, ['--set-active=other']);

  /// 解锁 / 上锁：老机型用 oem，新机型用 flashing
  Future<ExecResult> setLock(String serial, {required bool unlock}) async {
    final verb = unlock ? 'unlock' : 'lock';
    final r = await run(serial, ['oem', verb]);
    if (r.ok) return r;
    return run(serial, ['flashing', verb]);
  }
}
