import 'package:toolbox_commands/toolbox_commands.dart';
import 'package:toolbox_core/toolbox_core.dart';

import 'context.dart';

/// 联网修复与私人 DNS。
///
/// 对应 TS 版 src/main/ops/network.ts。

Future<NetworkState> _readState(String serial, OpContext ctx) async {
  final r = await ctx.adb.shell(
    serial,
    [networkReadScript()],
    timeout: const Duration(seconds: 15),
    echoOutput: false,
  );
  if (r.code != 0) throw const OpException('读取网络设置失败，详见日志');
  return parseNetworkState(r.stdout);
}

/// 联网检测地址和私人 DNS，都是 settings global 里的键，不需要 Root，改完重连 Wi-Fi 生效
Future<OperationResult> network(NetworkRequest req, OpContext ctx) async {
  final serial = await ctx.requireSystem();
  Future<void> put(String k, String v) =>
      ctx.adb.shell(serial, settingsPutArgs(k, v), timeout: const Duration(seconds: 15));
  Future<void> del(String k) => ctx.adb.shell(serial, settingsDeleteArgs(k), timeout: const Duration(seconds: 15));
  var message = '';

  switch (req) {
    case NetworkStatusRequest():
      ctx.step('正在读取网络设置');
      message = '已读取网络设置';
    case NetworkCaptiveRequest(:final fix):
      ctx.step(fix ? '正在把联网检测地址改成国内地址' : '正在恢复系统默认的联网检测地址');
      for (final k in captiveKeys) {
        if (fix) {
          final v = captiveCn[k];
          if (v != null) await put(k, v);
        } else {
          await del(k);
        }
      }
      message = fix ? '已改成国内的联网检测地址。请关掉 Wi-Fi 再打开（或重新连接一次），感叹号就会消失' : '已恢复系统默认的联网检测地址，重新连接 Wi-Fi 后生效';
    case NetworkDnsRequest(:final mode, :final host):
      final target = host?.trim().toLowerCase();
      if (mode == PrivateDnsMode.hostname && (target == null || !validDnsHost(target))) {
        throw const OpException('请填写私人 DNS 服务器的主机名，例如 dns.alidns.com（不要带 https:// 或端口）');
      }
      ctx.step('正在设置私人 DNS');
      if (mode == PrivateDnsMode.hostname) await put('private_dns_specifier', target!);
      await put('private_dns_mode', mode.name);
      message = mode == PrivateDnsMode.hostname
          ? '私人 DNS 已设为 $target。如果设置后打不开网页，说明当前网络连不上这个服务器，换一个或改回「自动」'
          : mode == PrivateDnsMode.off
              ? '已关闭私人 DNS'
              : '私人 DNS 已改回自动（系统默认）';
  }

  final state = await _readState(serial, ctx);
  if (req is NetworkCaptiveRequest && (state.captive == CaptiveState.cn) != req.fix) {
    return OperationResult(ok: false, message: '设置没有生效，详见日志', network: state);
  }
  if (req is NetworkDnsRequest && state.dnsMode != req.mode) {
    return OperationResult(ok: false, message: '设置没有生效，详见日志', network: state);
  }
  return OperationResult(ok: true, message: message, network: state);
}
