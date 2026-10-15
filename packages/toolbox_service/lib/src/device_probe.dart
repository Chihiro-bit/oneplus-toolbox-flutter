import 'package:toolbox_commands/toolbox_commands.dart';
import 'package:toolbox_core/toolbox_core.dart';

import 'ops/op_exception.dart';

/// 设备探测：判断连接状态、补全详情、等待设备进入指定模式
class DeviceProbe {
  DeviceProbe(this._tools);

  final ToolPaths _tools;

  /// 开机时读到的品牌与型号，按序列号记住。Fastboot 下读不到品牌，
  /// 如果这台设备之前以开机状态连过，就沿用记下的信息。
  final _identity = <String, ({String? model, String? brand, String? manufacturer})>{};

  /// 9008 枚举较慢（一次 Get-PnpDevice 要 1~2 秒），只在 adb / fastboot 都没结果时查，
  /// 且最多每 15 秒一次，避免待机时空耗 CPU。
  static const _edlProbeInterval = Duration(seconds: 15);
  DateTime _edlProbedAt = DateTime.fromMillisecondsSinceEpoch(0);
  List<EdlDevice> _edlCache = const [];

  /// adb devices / fastboot devices / 9008 三路探测
  Future<DeviceInfo> detect([CancelToken? cancel]) async {
    final list = [
      ...await Adb(_tools.adb, cancel: cancel).devices(),
      ...await Fastboot(_tools.fastboot, cancel: cancel).devices(),
    ];
    if (list.isEmpty) {
      if (DateTime.now().difference(_edlProbedAt) > _edlProbeInterval) {
        _edlProbedAt = DateTime.now();
        try {
          _edlCache = await listEdlDevices(cancel);
        } on CancelledException {
          rethrow;
        } catch (_) {
          _edlCache = const [];
        }
      }
      for (final d in _edlCache) {
        list.add(RawDevice(d.port.isNotEmpty ? d.port : d.name, DeviceMode.edl, edlPort: d.port, label: d.name));
      }
    }
    if (list.isEmpty) return DeviceInfo.disconnected;
    final first = list.first;
    return DeviceInfo(
      mode: first.mode,
      serial: first.serial,
      multiple: list.length > 1,
      // adb / fastboot 下 label 为空，型号由 describe() 补全；edl 下用设备管理器里的名称
      device: first.label,
      edlPort: first.edlPort,
    );
  }

  /// 补全设备详情：开机/Recovery 读 getprop，Fastboot 读 getvar
  Future<DeviceInfo> describe(DeviceInfo base, [CancelToken? cancel]) async {
    final serial = base.serial;
    if (serial == null) return base;
    try {
      if (base.mode == DeviceMode.system || base.mode == DeviceMode.recovery) {
        final p = await Adb(_tools.adb, cancel: cancel).getprop(serial);
        String? v(String k) => p[k]?.isNotEmpty == true ? p[k] : null;
        final id = (
          model: v('ro.product.marketname') ?? v('ro.vendor.oplus.market.name') ?? v('ro.product.model'),
          brand: v('ro.product.brand'),
          manufacturer: v('ro.product.manufacturer'),
        );
        if (id.brand != null || id.manufacturer != null) _identity[serial] = id;
        return base.copyWith(
          model: id.model,
          brand: id.brand,
          manufacturer: id.manufacturer,
          device: v('ro.product.device'),
          androidVersion: v('ro.build.version.release'),
          buildId: v('ro.build.display.id'),
          romVersion: v('ro.build.version.oplusrom') ?? v('ro.rom.version'),
          slot: v('ro.boot.slot_suffix')?.replaceFirst(RegExp('^_'), ''),
        );
      }
      if (base.mode == DeviceMode.fastboot) {
        final fb = Fastboot(_tools.fastboot, cancel: cancel);
        final product = await fb.getvar(serial, 'product');
        final slot = await fb.getvar(serial, 'current-slot');
        final unlocked = await fb.isUnlocked(serial);
        final id = _identity[serial];
        return base.copyWith(
          model: id?.model,
          brand: id?.brand,
          manufacturer: id?.manufacturer,
          device: product,
          slot: slot,
          unlocked: unlocked,
        );
      }
    } on CancelledException {
      rethrow;
    } catch (_) {
      // 读不到详情时只显示连接状态
    }
    return base;
  }

  /// 轮询等待设备进入指定模式
  Future<DeviceInfo> waitForMode(
    Set<DeviceMode> modes, {
    required Duration timeout,
    CancelToken? cancel,
    LogSink? log,
  }) async {
    final deadline = DateTime.now().add(timeout);
    var warnedUnauthorized = false;
    while (DateTime.now().isBefore(deadline)) {
      final d = await detect(cancel);
      if (modes.contains(d.mode)) return d;
      if (d.mode == DeviceMode.unauthorized && !warnedUnauthorized) {
        log?.call(LogLevel.warn, '手机上出现了 USB 调试授权弹窗，请勾选“始终允许”并点击允许');
        warnedUnauthorized = true;
      }
      await delay(const Duration(milliseconds: 1500), cancel);
    }
    throw OpException('等待设备超时（${timeout.inSeconds} 秒）。请检查数据线和驱动');
  }
}
