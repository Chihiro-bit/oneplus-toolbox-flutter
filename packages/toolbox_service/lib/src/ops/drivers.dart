import 'package:toolbox_commands/toolbox_commands.dart';
import 'package:toolbox_core/toolbox_core.dart';

import 'context.dart';

/// 驱动诊断：列出和手机有关的 USB 设备及其驱动状态。
///
/// 对应 TS 版 src/main/ops/drivers.ts。
Future<OperationResult> driverCheck(OpContext ctx) async {
  ctx.step('正在查询设备管理器');
  final r = await queryPnpDevices(cancel: ctx.cancel, log: ctx.log);
  final drivers = parseDrivers(r.all);
  for (final d in drivers) {
    ctx.log(d.ok ? LogLevel.info : LogLevel.warn, '${d.name}  ${d.instanceId}  ${d.problem ?? '正常'}');
  }
  final bad = [
    for (final d in drivers)
      if (!d.ok) d
  ];
  if (drivers.isEmpty) {
    return OperationResult(
      ok: true,
      message: '设备管理器里没有找到手机。请换一根支持数据传输的线、换一个 USB 口，并确认手机已开启 USB 调试',
      drivers: drivers,
    );
  }
  return OperationResult(
    ok: true,
    message: bad.isNotEmpty ? '有 ${bad.length} 个设备的驱动有问题，见下方说明' : '找到了手机，驱动都正常。仍然连不上的话，请检查手机上的 USB 调试授权',
    drivers: drivers,
  );
}
