import 'package:toolbox_commands/toolbox_commands.dart';
import 'package:toolbox_core/toolbox_core.dart';

import '../device_probe.dart';
import 'op_exception.dart';

export 'op_exception.dart';

/// 一次操作的上下文：取消、日志、步骤提示、设备状态回传，以及绑定了这些的命令对象
class OpContext {
  OpContext({
    required this.cancel,
    required this.log,
    required this.step,
    required this.device,
    required this.tools,
    required this.probe,
  });

  final CancelToken cancel;
  final LogSink log;

  /// 更新界面上「正在做什么」的提示
  final void Function(String text) step;

  /// 操作过程中设备状态变化时通知界面
  final void Function(DeviceInfo d) device;
  final ToolPaths tools;
  final DeviceProbe probe;

  late final adb = Adb(tools.adb, cancel: cancel, log: log);
  late final fastboot = Fastboot(tools.fastboot, cancel: cancel, log: log);
  late final payloadDumper = PayloadDumper(tools.payloadDumper, cancel: cancel, log: log);
  late final sevenZip = SevenZip(tools.sevenZip, cancel: cancel, log: log);

  /// 恰好连接了一台可用设备，返回它
  Future<DeviceInfo> requireDevice() async {
    final d = await probe.detect(cancel);
    switch (d.mode) {
      case DeviceMode.none:
        throw const OpException('未检测到设备，请连接手机并开启 USB 调试');
      case DeviceMode.unauthorized:
        throw const OpException('设备未授权，请在手机弹窗中允许 USB 调试');
      case _ when d.multiple:
        throw const OpException('检测到多台设备，请只保留一台');
      case _:
        return d;
    }
  }

  /// 设备处于开机状态，返回序列号
  Future<String> requireSystem() async {
    final d = await requireDevice();
    if (d.mode != DeviceMode.system) throw const OpException('请让手机正常开机并开启 USB 调试后再使用本功能');
    return d.serial!;
  }

  /// 进入 Fastboot（已在 Fastboot 则直接返回），返回序列号
  Future<String> ensureFastboot() async {
    final d = await requireDevice();
    if (d.mode == DeviceMode.fastboot) return d.serial!;
    step('正在重启到 Fastboot 模式');
    await adb.reboot(d.serial!, 'bootloader');
    final fb =
        await probe.waitForMode({DeviceMode.fastboot}, timeout: const Duration(seconds: 90), cancel: cancel, log: log);
    device(fb);
    log(LogLevel.ok, '已连接 Fastboot 模式');
    return fb.serial!;
  }
}
