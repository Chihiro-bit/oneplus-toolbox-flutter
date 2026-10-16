import 'package:toolbox_commands/toolbox_commands.dart';
import 'package:toolbox_core/toolbox_core.dart';

import 'context.dart';

/// 无线调试，对应 TS 版 src/main/ops/wireless.ts。

/// 手机 IP / 主机名：IPv4、[IPv6] 或域名
final _host = RegExp(r'^(?:\d{1,3}(?:\.\d{1,3}){3}|\[[0-9a-f:]+\]|[a-z0-9][a-z0-9.-]{0,252})$', caseSensitive: false);
final _port = RegExp(r'^\d{1,5}$');
final _pairCode = RegExp(r'^\d{6}$');
final _paired = RegExp('Successfully paired', caseSensitive: false);
final _connected = RegExp('connected to', caseSensitive: false);
final _notConnected = RegExp('failed|cannot', caseSensitive: false);

/// 校验 IP 和端口，返回 `IP:端口`。地址或端口不合法时抛出 [OpException]
String checkAddress(String host, String port) {
  final h = host.trim();
  final pr = port.trim();
  if (!_host.hasMatch(h)) throw const OpException('IP 地址不正确');
  final n = int.tryParse(pr);
  if (!_port.hasMatch(pr) || n == null || n < 1 || n > 65535) throw const OpException('端口不正确');
  return '$h:$pr';
}

/// 无线调试（Android 11+）：
/// - pair：手机「无线调试 → 使用配对码配对设备」里显示的 IP:端口 和 6 位配对码，每台电脑只需配对一次
/// - connect：无线调试页面上方显示的 IP:端口（和配对用的端口不同）
/// - fromUsb：插着线时一键切到无线（adb tcpip 5555 后连手机的 Wi-Fi IP），适合没有配对界面的老系统
Future<OperationResult> wireless(WirelessRequest req, OpContext ctx) async {
  /// 与 TS 版 `run()` 一致：不传 timeoutMs 时 exec 的默认值是 60 秒
  Future<ExecResult> run(List<String> args, [Duration timeout = const Duration(seconds: 60)]) => exec(
        ctx.tools.adb,
        args,
        cancel: ctx.cancel,
        log: ctx.log,
        timeout: timeout,
      );

  switch (req) {
    case WirelessPairRequest(:final host, :final port, :final code):
      final addr = checkAddress(host, port);
      final pairing = code.trim();
      if (!_pairCode.hasMatch(pairing)) throw const OpException('配对码是 6 位数字');
      ctx.step('正在与 $addr 配对');
      final r = await run(['pair', addr, pairing]);
      if (!_paired.hasMatch(r.all)) {
        return const OperationResult.fail('配对失败：请确认配对码没过期，电脑和手机在同一个 Wi-Fi 下');
      }
      return const OperationResult(ok: true, message: '配对成功。接下来用无线调试页面上方显示的 IP 和端口连接');

    case WirelessConnectRequest(:final host, :final port):
      final addr = checkAddress(host, port);
      ctx.step('正在连接 $addr');
      final r = await run(['connect', addr]);
      if (!_connected.hasMatch(r.all) || _notConnected.hasMatch(r.all)) {
        return const OperationResult.fail('连接失败：请确认手机已打开无线调试、这台电脑已配对过，且端口是无线调试页面上方显示的那个');
      }
      return OperationResult(ok: true, message: '已通过无线连接 $addr，可以拔掉数据线了');

    case WirelessDisconnectRequest():
      await run(['disconnect']);
      return const OperationResult(ok: true, message: '已断开所有无线连接');

    case WirelessFromUsbRequest():
      final serial = await ctx.requireSystem();
      if (serial.contains(':')) throw const OpException('当前已经是无线连接');
      ctx.step('正在读取手机的 Wi-Fi 地址');
      final out = (await ctx.adb.shell(serial, ['ip', '-f', 'inet', 'addr', 'show', 'wlan0'])).stdout;
      final ip = RegExp(r'inet (\d+\.\d+\.\d+\.\d+)').firstMatch(out)?.group(1);
      if (ip == null) throw const OpException('读不到手机的 Wi-Fi 地址，请确认手机已连上 Wi-Fi');
      ctx.step('正在打开 adb 网络调试端口 5555');
      await ctx.adb.shell(serial, ['tcpip', '5555']);
      await delay(const Duration(seconds: 2), ctx.cancel);
      final r = await run(['connect', '$ip:5555']);
      if (!_connected.hasMatch(r.all) || _notConnected.hasMatch(r.all)) {
        return OperationResult.fail('连接 $ip:5555 失败：请确认电脑和手机在同一个 Wi-Fi 下');
      }
      return OperationResult(ok: true, message: '已通过无线连接 $ip:5555，可以拔掉数据线了。手机重启后需要重新用数据线切换');
  }
}
