import 'package:toolbox_commands/toolbox_commands.dart';
import 'package:toolbox_core/toolbox_core.dart';

import '../device_probe.dart';
import '../environment.dart';
import '../history.dart';
import '../logfile.dart';
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
    required this.env,
    required this.history,
    required this.logFile,
  });

  final CancelToken cancel;
  final LogSink log;

  /// 更新界面上「正在做什么」的提示
  final void Function(String text) step;

  /// 操作过程中设备状态变化时通知界面
  final void Function(DeviceInfo d) device;
  final ToolPaths tools;
  final DeviceProbe probe;

  /// 各类目录与版本号
  final ToolboxEnvironment env;

  /// 刷写记录与备份
  final FlashHistory history;

  /// 落盘日志（文档\一加工具箱\logs）
  final LogFile logFile;

  late final adb = Adb(tools.adb, cancel: cancel, log: log);
  late final fastboot = Fastboot(tools.fastboot, cancel: cancel, log: log);
  late final payloadDumper = PayloadDumper(tools.payloadDumper, cancel: cancel, log: log);
  late final sevenZip = SevenZip(tools.sevenZip, cancel: cancel, log: log);
  late final qdl = Qdl(tools.qdl, cancel: cancel, log: log);

  /// 恰好连接了一台可用设备，返回它
  Future<DeviceInfo> requireDevice() async {
    final d = await probe.detect(cancel);
    switch (d.mode) {
      case DeviceMode.none:
        throw const OpException('未检测到设备，请连接手机并开启 USB 调试');
      case DeviceMode.unauthorized:
        throw const OpException('设备未授权，请在手机弹窗中允许 USB 调试');
      case _ when d.needsPick:
        throw const OpException('连接了多台设备，请先在左下角选择要操作的那一台');
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

  /// 等手机连上 adb（卡开机时 adb 往往只在开机过程中出现几秒），最多 3 分钟，返回序列号。
  /// 连着别的设备时只等选中的那台，否则 wait-for-device 会被别的设备立即满足
  Future<String?> waitForAdb() async {
    final now = await probe.detect(cancel);
    final target = (now.multiple || now.mode != DeviceMode.none) ? probe.selectedSerial : null;
    if (now.multiple && target == null) {
      throw const OpException('连接了多台设备，请先在左下角选择要操作的那一台');
    }
    final r = await exec(
      tools.adb,
      [
        if (target != null) ...['-s', target],
        'wait-for-device'
      ],
      cancel: cancel,
      log: log,
      timeout: const Duration(minutes: 3),
    );
    if (r.code != 0) return null;
    final d = await probe.detect(cancel);
    if (d.serial == null || d.needsPick) return null;
    return (d.mode == DeviceMode.system || d.mode == DeviceMode.recovery) ? d.serial : null;
  }

  /// 进入 Bootloader 里的 Fastboot（已在则直接返回；在 fastbootd 时切回 bootloader）
  Future<String> ensureFastboot() async {
    final d = await requireDevice();
    if (d.mode == DeviceMode.fastboot) return d.serial!;
    step('正在重启到 Fastboot 模式');
    if (d.mode == DeviceMode.fastbootd) {
      await fastboot.reboot(d.serial!, 'bootloader');
    } else {
      await adb.reboot(d.serial!, 'bootloader');
    }
    final fb = await probe.waitForMode(
      {DeviceMode.fastboot},
      timeout: const Duration(seconds: 90),
      serial: d.serial,
      cancel: cancel,
      log: log,
    );
    device(fb);
    log(LogLevel.ok, '已连接 Fastboot 模式');
    return fb.serial!;
  }

  /// 进入 fastbootd（用户空间 Fastboot）：刷逻辑分区、取消 / 继续合并系统更新时用
  Future<String> ensureFastbootd() async {
    final d = await requireDevice();
    if (d.mode == DeviceMode.fastbootd) return d.serial!;
    step('正在重启到 fastbootd');
    if (d.mode == DeviceMode.fastboot) {
      await fastboot.run(d.serial!, ['reboot', 'fastboot']);
    } else {
      await adb.reboot(d.serial!, 'fastboot');
    }
    final fd = await probe.waitForMode(
      {DeviceMode.fastbootd},
      timeout: const Duration(seconds: 90),
      serial: d.serial,
      cancel: cancel,
      log: log,
    );
    device(fd);
    log(LogLevel.ok, '已连接 fastbootd');
    return fd.serial!;
  }
}
