import 'dart:io';

import 'package:toolbox_core/toolbox_core.dart';

import 'exec.dart';

/// adb devices / fastboot devices / 9008 列出的一台设备
class RawDevice {
  const RawDevice(this.serial, this.mode, {this.edlPort, this.label});

  final String serial;
  final DeviceMode mode;

  /// 仅 edl：QDLoader 9008 的 COM 端口
  final String? edlPort;

  /// 仅 edl：设备管理器里的名称
  final String? label;
}

const _adbStates = {
  'device': DeviceMode.system,
  'recovery': DeviceMode.recovery,
  'sideload': DeviceMode.recovery,
  'rescue': DeviceMode.recovery,
  'unauthorized': DeviceMode.unauthorized,
};

/// 解析 `adb devices` 的输出
List<RawDevice> parseAdbDevices(String out) => [
      for (final m in RegExp(r'^(\S+)\s+(\S+)$', multiLine: true).allMatches(out.replaceAll('\r', '')))
        if (_adbStates[m[2]] case final mode?) RawDevice(m[1]!, mode)
    ];

/// 解析 `adb shell getprop` 的输出，形如 `[ro.product.model]: [CPH2653]`
Map<String, String> parseGetprop(String out) => {
      for (final m in RegExp(r'^\[([^\]]+)\]: \[([^\]]*)\]', multiLine: true).allMatches(out.replaceAll('\r', '')))
        m[1]!: m[2]!
    };

/// adb 命令。[cancel] 和 [log] 作用于这个实例发出的所有命令。
class Adb {
  const Adb(this.exe, {this.cancel, this.log});

  final String exe;
  final CancelToken? cancel;
  final LogSink? log;

  Future<List<RawDevice>> devices() async {
    final r = await exec(exe, ['devices'], cancel: cancel, timeout: const Duration(seconds: 15));
    return parseAdbDevices(r.stdout);
  }

  /// `adb -s <serial> <args>`
  Future<ExecResult> run(
    String serial,
    List<String> args, {
    Duration timeout = const Duration(seconds: 60),
    bool echoOutput = true,
  }) =>
      exec(exe, ['-s', serial, ...args], cancel: cancel, log: log, timeout: timeout, echoOutput: echoOutput);

  /// `adb shell`，参数原样交给手机端 shell；可以是一整段多行脚本
  Future<ExecResult> shell(
    String serial,
    List<String> args, {
    Duration timeout = const Duration(seconds: 60),
    bool echoOutput = true,
  }) =>
      run(serial, ['shell', ...args], timeout: timeout, echoOutput: echoOutput);

  /// 读取全部系统属性（不写日志，输出太长）
  Future<Map<String, String>> getprop(String serial) async {
    final r = await exec(exe, ['-s', serial, 'shell', 'getprop'], cancel: cancel, timeout: const Duration(seconds: 15));
    return parseGetprop(r.stdout);
  }

  Future<ExecResult> push(String serial, String local, String remote,
          {Duration timeout = const Duration(minutes: 5)}) =>
      run(serial, ['push', local, remote], timeout: timeout);

  Future<ExecResult> pull(String serial, String remote, String local,
          {Duration timeout = const Duration(minutes: 5)}) =>
      run(serial, ['pull', remote, local], timeout: timeout);

  /// `adb install -r [-d]`，成功时输出含 Success
  Future<bool> install(String serial, String apk,
      {bool allowDowngrade = false, Duration timeout = const Duration(minutes: 3)}) async {
    final r = await run(serial, ['install', '-r', if (allowDowngrade) '-d', apk], timeout: timeout);
    return r.ok && r.all.contains('Success');
  }

  /// `adb reboot [target]`，target 为 null 时正常重启
  Future<ExecResult> reboot(String serial, [String? target]) => run(serial, ['reboot', if (target != null) target]);

  /// 关闭 adb server，避免退出后残留进程占用 5037 端口
  void killServerSync() {
    try {
      Process.runSync(exe, ['kill-server']);
    } catch (_) {
      // 退出时尽力而为
    }
  }
}
