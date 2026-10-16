import 'package:path/path.dart' as p;
import 'package:toolbox_commands/toolbox_commands.dart';
import 'package:toolbox_core/toolbox_core.dart';

import 'context.dart';

/// Shizuku：免 Root 让其它应用调用系统接口。
///
/// 对应 TS 版 src/main/ops/shizuku.ts。

/// 开机自启时，Shizuku 用自己配对过的密钥连本机的无线调试，这几步只能在手机上做
const _autostartPhoneSteps = '还需要在手机上完成：① 连上常用的 Wi-Fi，在 Shizuku 里用「通过无线调试启动」配对并启动一次（之后开机才连得上无线调试）；'
    '② ColorOS / 氧 OS：设置 → 应用 → Shizuku → 允许自启动';

Future<ShizukuProbe> _probe(String serial, OpContext ctx) async {
  final r = await ctx.adb.shell(
    serial,
    [shizukuProbeScript],
    timeout: const Duration(seconds: 30),
    echoOutput: false,
  );
  return parseShizukuProbe(r.stdout);
}

String _describeState(ShizukuState s) {
  if (!s.installed) return '手机上没有安装 Shizuku';
  return 'Shizuku ${s.version ?? ''} ${s.running ? '正在运行' : '已安装，未运行'}'.replaceAll(RegExp(r'\s+'), ' ');
}

/// 免 Root 开机自启（Shizuku 13.6+，Android 13+）：开机广播里用 WRITE_SECURE_SETTINGS 打开无线调试，
/// 再用 Shizuku 自己配对过的密钥连上去执行启动命令。电脑这边能做的是授予权限、确认开机广播没被关掉
Future<OperationResult> _autostart(String serial, ShizukuState state, OpContext ctx) async {
  if (!state.installed) throw const OpException('手机上还没有安装 Shizuku，请先点「启动 Shizuku」');
  if (state.sdk != null && state.sdk! < 33) {
    throw const OpException('免 Root 开机自启需要 Android 13 及以上。Android 12 及以下每次重启后需要重新启动 Shizuku');
  }

  if (state.secureSettings != true) {
    ctx.step('正在授予 Shizuku「修改安全系统设置」权限');
    await ctx.adb.shell(serial, ['pm', 'grant', shizukuRelease.package, writeSecureSettings]);
  }
  if (state.bootReceiver != true) {
    ctx.step('正在打开 Shizuku 的开机启动');
    await ctx.adb.shell(serial, ['pm', 'enable', '${shizukuRelease.package}/$bootReceiverComponent']);
  }
  final now = await _probe(serial, ctx);
  if (now.secureSettings != true) {
    return OperationResult(ok: false, message: '没能授予 Shizuku「修改安全系统设置」权限，详见日志', shizuku: now);
  }
  if (now.bootReceiver != true) {
    return OperationResult(ok: false, message: '没能打开 Shizuku 的开机启动，可以在 Shizuku 设置里手动打开', shizuku: now);
  }
  return OperationResult(ok: true, message: '电脑这边已准备好。$_autostartPhoneSteps', shizuku: now);
}

String _mb(int bytes) => (bytes / 1048576).toStringAsFixed(1);

/// 装了 Shizuku 时用 adb 把它拉起来；没装就先下载校验再安装
Future<OperationResult> shizuku(ShizukuAction action, OpContext ctx) async {
  final serial = await ctx.requireSystem();
  ctx.step('正在检查 Shizuku 状态');
  var state = await _probe(serial, ctx);
  if (action == ShizukuAction.status) {
    return OperationResult(ok: true, message: _describeState(state), shizuku: state);
  }
  if (action == ShizukuAction.autostart) return _autostart(serial, state, ctx);

  if (state.running) {
    return OperationResult(ok: true, message: '${_describeState(state)}，不需要再启动', shizuku: state);
  }

  if (!state.installed) {
    final label = 'Shizuku ${shizukuRelease.version}';
    var lastPct = -10;
    final String apk;
    try {
      final file = await downloadVerified(
        shizukuRelease.url,
        shizukuRelease.sha256,
        p.join(ctx.env.dataDir, 'apk-cache'),
        cancel: ctx.cancel,
        onStart: () {
          ctx.step('正在下载 $label');
          ctx.log(LogLevel.cmd, 'GET ${shizukuRelease.url}');
        },
        onProgress: (got, total) {
          if (total == null) return;
          final pct = got * 100 ~/ total;
          if (pct < lastPct + 10) return;
          lastPct = pct;
          ctx.step('正在下载 $label（$pct%，${_mb(got)} / ${_mb(total)} MB）');
        },
      );
      ctx.log(LogLevel.ok, file.fromCache ? '使用已缓存的 $label' : '$label 下载完成，sha256 校验通过');
      apk = file.path;
    } on ChecksumMismatchException catch (e) {
      throw OpException('$label 校验失败：期望 sha256 ${e.expected}，实际 ${e.actual}。文件可能被篡改或下载不完整，已丢弃');
    } on HttpStatusException catch (e) {
      throw OpException('下载失败：HTTP ${e.status}');
    }

    ctx.step('正在安装 Shizuku，请留意手机上的安装提示');
    final r = await ctx.adb.run(serial, ['install', '-r', apk], timeout: const Duration(minutes: 3));
    if (r.code != 0 || !r.all.contains('Success')) {
      throw const OpException('Shizuku 安装失败，详见日志。ColorOS 上可能需要在手机弹窗里允许「通过 USB 安装应用」');
    }
    ctx.log(LogLevel.ok, 'Shizuku 已安装');
    state = await _probe(serial, ctx);
  }

  final starter = state.starter;
  if (starter == null) {
    throw const OpException('找不到 Shizuku 的启动程序。请在手机上打开一次 Shizuku 应用，再回来重试');
  }

  ctx.step('正在启动 Shizuku');
  await ctx.adb.shell(serial, starterCommand(starter), timeout: const Duration(seconds: 60));

  // 启动程序退出后服务端才在后台起来，稍等几秒再确认
  for (var i = 0; i < 5 && !state.running; i++) {
    await delay(const Duration(seconds: 1), ctx.cancel);
    state = await _probe(serial, ctx);
  }
  if (!state.running) {
    return OperationResult(ok: false, message: 'Shizuku 没有启动成功，详见日志', shizuku: state);
  }
  return OperationResult(
    ok: true,
    message: 'Shizuku 已启动。在 Shizuku 应用里给需要的应用授权即可；手机重启后需要重新启动，或者设置开机自启',
    shizuku: state,
  );
}
