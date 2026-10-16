import 'package:toolbox_commands/toolbox_commands.dart';
import 'package:toolbox_core/toolbox_core.dart';

import 'known.dart';
import 'ops/op_exception.dart';

/// 管理器包名 → 显示名，只用于「装了 App 但 Root 没生效」的提示
const _managerLabel = <String, String>{
  'com.topjohnwu.magisk': 'Magisk',
  'io.github.huskydg.magisk': 'Kitsune Mask',
  'io.github.vvb2060.magisk': 'Magisk Alpha',
  'me.bmax.apatch': 'APatch',
  'me.weishu.kernelsu': 'KernelSU',
  'com.rifsxd.ksunext': 'KernelSU Next',
  'com.sukisu.ultra': 'SukiSU Ultra',
  'com.resukisu.resukisu': 'ReSukiSU',
};

final _managerPattern = _managerLabel.keys.map(RegExp.escape).join('|');

/// 不需要 Root 授权的探测：`magisk -v` 对 shell 可见；`su -v` 只打印版本、不会弹授权窗
/// （KernelSU / APatch 没给 shell 授权时 su 对 shell 不可见，这时只能靠管理器包名判断）
final _rootProbe = 'echo "M|\$(magisk -v 2>/dev/null)"; echo "S|\$(su -v 2>/dev/null)"; '
    "pm list packages 2>/dev/null | grep -E '$_managerPattern'";

final _magiskLine = RegExp(r'^M\|(.+)$', multiLine: true);
final _suLine = RegExp(r'^S\|(.+)$', multiLine: true);
final _packageLine = RegExp(r'^package:([\w.]+)', multiLine: true);

/// 解析 Root 探测脚本的输出
String parseRootProbe(String out) {
  final clean = out.replaceAll('\r', '');
  final magisk = _magiskLine.firstMatch(clean)?.group(1)?.trim();
  final su = _suLine.firstMatch(clean)?.group(1)?.trim();
  // magisk -v 形如 30.7:MAGISK:R；su -v 在 KernelSU 下形如 3.3.1:KernelSU
  if (magisk != null && magisk.isNotEmpty) return 'Magisk ${magisk.split(':').first}';
  if (su != null && su.isNotEmpty) {
    final parts = su.split(':');
    return parts.length > 1 ? '${parts[1]} ${parts[0]}' : '已 Root（$su）';
  }
  final pkgs = [
    for (final m in _packageLine.allMatches(clean))
      if (_managerLabel[m.group(1)] case final label?) label,
  ];
  return pkgs.isNotEmpty ? '未检测到（装有 ${pkgs.join('、')} App）' : '未 Root';
}

/// 设备探测：判断连接状态、补全详情、等待设备进入指定模式
class DeviceProbe {
  DeviceProbe(this._tools, this._known);

  final ToolPaths _tools;
  final KnownStore _known;

  /// 9008 枚举较慢（一次 Get-PnpDevice 要 1~2 秒），只在 adb / fastboot 都没结果时查，
  /// 且最多每 15 秒一次，避免待机时空耗 CPU。
  static const _edlProbeInterval = Duration(seconds: 15);
  DateTime _edlProbedAt = DateTime.fromMillisecondsSinceEpoch(0);
  List<EdlDevice> _edlCache = const [];

  /// 界面上选中的设备序列号。连了多台时，所有操作都只针对它；没选的话操作直接拒绝，避免刷错手机。
  /// 只连一台时不看这个值。
  String? _selected;

  void selectDevice(String? serial) => _selected = serial;

  String? get selectedSerial => _selected;

  /// adb devices / fastboot devices / 9008 三路探测
  Future<List<RawDevice>> listDevices([CancelToken? cancel]) async {
    final found = <RawDevice>[
      ...await Adb(_tools.adb, cancel: cancel).devices(),
      ...await Fastboot(_tools.fastboot, cancel: cancel).devices(),
    ];
    if (found.isNotEmpty) {
      // fastboot devices 不区分 bootloader 和 fastbootd，只能问 is-userspace
      // （一加 13 实测：bootloader 下 no，fastbootd 下 yes）
      final fb = Fastboot(_tools.fastboot, cancel: cancel);
      for (var i = 0; i < found.length; i++) {
        final d = found[i];
        if (d.mode != DeviceMode.fastboot) continue;
        if (await fb.getvar(d.serial, 'is-userspace') == 'yes') {
          found[i] = RawDevice(d.serial, DeviceMode.fastbootd);
        }
      }
      return found;
    }
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
      found.add(RawDevice(d.port.isNotEmpty ? d.port : d.name, DeviceMode.edl, edlPort: d.port, label: d.name));
    }
    return found;
  }

  DeviceInfo _toInfo(RawDevice d, List<RawDevice> list) {
    // adb / fastboot 下 label 为空，型号由 describe() 补全；edl 下就用设备管理器里的名称
    if (list.length <= 1) {
      return DeviceInfo(mode: d.mode, serial: d.serial, device: d.label, edlPort: d.edlPort);
    }
    return DeviceInfo(
      mode: d.mode,
      serial: d.serial,
      device: d.label,
      edlPort: d.edlPort,
      multiple: true,
      devices: [for (final x in list) DeviceRef(serial: x.serial, mode: x.mode, label: x.label)],
      selected: _selected,
      needsPick: d.serial != _selected,
    );
  }

  Future<DeviceInfo> detect([CancelToken? cancel]) async {
    final list = await listDevices(cancel);
    if (list.isEmpty) return DeviceInfo.disconnected;
    final chosen = list.firstWhere((d) => d.serial == _selected, orElse: () => list.first);
    return _toInfo(chosen, list);
  }

  /// 读取全部系统属性
  Future<Map<String, String>> getProps(String serial, [CancelToken? cancel]) =>
      Adb(_tools.adb, cancel: cancel).getprop(serial);

  /// fastboot getvar all 的原始输出（不写日志，输出很长）
  Future<String> getvarAll(String serial, [CancelToken? cancel]) async {
    final r = await exec(_tools.fastboot, ['-s', serial, 'getvar', 'all'],
        cancel: cancel, timeout: const Duration(seconds: 20));
    return r.all;
  }

  /// Root 状态；只有开机下可读
  Future<String?> rootStatus(String serial, [CancelToken? cancel]) async {
    final r = await Adb(_tools.adb, cancel: cancel)
        .shell(serial, [_rootProbe], timeout: const Duration(seconds: 15), echoOutput: false);
    return r.code == 0 ? parseRootProbe(r.stdout) : null;
  }

  /// 补全设备详情：开机/Recovery 读 getprop，Fastboot / fastbootd 读 getvar
  /// （品牌、型号用之前开机时记下的）
  Future<DeviceInfo> describe(DeviceInfo base, [CancelToken? cancel]) async {
    final serial = base.serial;
    if (serial == null) return base;
    try {
      if (base.mode == DeviceMode.system || base.mode == DeviceMode.recovery) {
        final p = await getProps(serial, cancel);
        String? v(String k) => p[k]?.isNotEmpty == true ? p[k] : null;
        // Recovery 里的 getprop 是 Recovery 自己的，版本信息不可靠，只在开机时记录
        if (base.mode == DeviceMode.system && (v('ro.product.brand') != null || v('ro.product.manufacturer') != null)) {
          _known.remember(
            serial,
            KnownDevice(
              brand: v('ro.product.brand'),
              manufacturer: v('ro.product.manufacturer'),
              model: v('ro.product.marketname') ?? v('ro.vendor.oplus.market.name') ?? v('ro.product.model'),
              buildDateUtc: v('ro.build.date.utc'),
              buildId: v('ro.build.display.id'),
              romVersion: v('ro.build.version.oplusrom') ?? v('ro.rom.version'),
            ),
          );
        }
        return base.copyWith(
          model: v('ro.product.marketname') ?? v('ro.vendor.oplus.market.name') ?? v('ro.product.model'),
          brand: v('ro.product.brand'),
          manufacturer: v('ro.product.manufacturer'),
          device: v('ro.product.device'),
          androidVersion: v('ro.build.version.release'),
          buildId: v('ro.build.display.id'),
          romVersion: v('ro.build.version.oplusrom') ?? v('ro.rom.version'),
          slot: v('ro.boot.slot_suffix')?.replaceFirst(RegExp('^_'), ''),
          root: base.mode == DeviceMode.system ? await rootStatus(serial, cancel) : null,
        );
      }
      if (base.mode == DeviceMode.fastboot || base.mode == DeviceMode.fastbootd) {
        final fb = Fastboot(_tools.fastboot, cancel: cancel);
        final product = await fb.getvar(serial, 'product');
        final slot = await fb.getvar(serial, 'current-slot');
        final unlocked = await fb.isUnlocked(serial);
        final k = _known.get(serial);
        return base.copyWith(
          model: k?.model,
          brand: k?.brand,
          manufacturer: k?.manufacturer,
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

  /// 轮询等待设备进入指定模式。给了 [serial] 时只认这台（连着多台手机时不会等到别的那台）；
  /// 只连着一台时不比对序列号，兼容 adb 和 fastboot 下序列号不一样的机型。
  Future<DeviceInfo> waitForMode(
    Set<DeviceMode> modes, {
    required Duration timeout,
    String? serial,
    CancelToken? cancel,
    LogSink? log,
  }) async {
    final deadline = DateTime.now().add(timeout);
    var warnedUnauthorized = false;
    while (DateTime.now().isBefore(deadline)) {
      final list = await listDevices(cancel);
      final want = serial ?? _selected;
      final raw = list.firstWhere(
        (x) => x.serial == want,
        orElse: () => list.length == 1 ? list.first : const RawDevice('', DeviceMode.none),
      );
      final d = raw.serial.isEmpty ? DeviceInfo.disconnected : _toInfo(raw, list);
      if (raw.serial.isNotEmpty && modes.contains(d.mode)) {
        // fastboot 下序列号变了（少数机型），跟着改选中的设备，后续操作才找得到它
        if (list.length > 1 || _selected != null) _selected = raw.serial;
        return DeviceInfo(
          mode: d.mode,
          serial: d.serial,
          multiple: d.multiple,
          devices: d.devices,
          selected: d.selected,
          device: d.device,
          edlPort: d.edlPort,
        );
      }
      if (d.mode == DeviceMode.unauthorized && !warnedUnauthorized) {
        log?.call(LogLevel.warn, '手机上出现了 USB 调试授权弹窗，请勾选“始终允许”并点击允许');
        warnedUnauthorized = true;
      }
      await delay(const Duration(milliseconds: 1500), cancel);
    }
    throw OpException('等待设备超时（${timeout.inSeconds} 秒）。请检查数据线和驱动');
  }
}
