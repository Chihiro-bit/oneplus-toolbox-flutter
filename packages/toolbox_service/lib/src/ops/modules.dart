import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:toolbox_commands/toolbox_commands.dart';
import 'package:toolbox_core/toolbox_core.dart';

import 'context.dart';
import 'root.dart';

/// 安装 Root 模块。
///
/// 对应 TS 版 src/main/ops/modules.ts。

/// 推到手机临时目录后逐个安装；全部装完才需要重启一次
Future<OperationResult> installModules(List<String> files, OpContext ctx) async {
  if (files.isEmpty) throw const OpException('请先选择模块的 .zip 文件');
  final serial = await ctx.requireSystem();
  final root = await ctx.probe.rootStatus(serial, ctx.cancel);
  if (!isRooted(root)) throw OpException('安装模块需要 Root，这台手机当前是「${root ?? '未知'}」');

  final dir = workDir(ctx.env);
  await ctx.adb.shell(serial, ['mkdir', '-p', remoteDir]);
  final ok = <String>[];
  final failed = <String>[];
  for (var i = 0; i < files.length; i++) {
    final file = files[i];
    final name = p.basename(file);
    if (p.extension(file).toLowerCase() != '.zip' || !File(file).existsSync()) {
      ctx.log(LogLevel.warn, '跳过 $name：不是 .zip 文件');
      failed.add(name);
      continue;
    }
    final listing = await ctx.sevenZip.list(file);
    if (!isModuleListing(listing)) {
      ctx.log(LogLevel.error, '$name 里没有 module.prop，不是 Root 模块（卡刷包、ROM 不能用这个功能安装）');
      failed.add(name);
      continue;
    }

    ctx.step('正在安装 $name（${i + 1}/${files.length}），手机上弹出 Root 授权时请点允许');
    final local = p.join(dir, 'module_$i.zip');
    File(file).copySync(local);
    final remote = '$remoteDir/module_$i.zip';
    final pushed = await ctx.adb.push(serial, local, remote, timeout: const Duration(minutes: 10));
    if (pushed.code != 0) {
      ctx.log(LogLevel.error, '$name 推送失败');
      failed.add(name);
      continue;
    }
    final r = await ctx.adb.shell(
      serial,
      ['timeout 300 su -c ${shq(installScript(remote))} 2>&1'],
      timeout: const Duration(seconds: 320),
    );
    await ctx.adb.shell(serial, ['rm', '-f', remote]);
    final outcome = parseModuleInstall(r.stdout);
    if (outcome.noTool) {
      throw const OpException('拿到了 Root，但没找到 Magisk / KernelSU / APatch 的命令行工具，请在 Root 管理器里安装');
    }
    final code = outcome.code;
    if (code == null) {
      throw const OpException('没有拿到 Root 授权。请在 Root 管理器里允许 Shell 的超级用户权限后再试');
    }
    if (code == '0') {
      ok.add(name);
      ctx.log(LogLevel.ok, '$name 安装成功');
    } else {
      failed.add(name);
      ctx.log(LogLevel.error, '$name 安装失败（退出码 $code），模块自带的安装脚本输出见上方日志');
    }
  }

  const tail = '重启手机后生效。万一重启后卡开机，可以在「救援与恢复」里禁用全部模块';
  if (failed.isEmpty) {
    return OperationResult(ok: true, message: '${ok.length == 1 ? ok.first : '${ok.length} 个模块'}已安装，$tail');
  }
  return OperationResult(
    ok: ok.isNotEmpty,
    message: '成功 ${ok.length} 个，失败 ${failed.length} 个（${failed.join('、')}），失败原因见日志${ok.isNotEmpty ? '。$tail' : ''}',
  );
}
