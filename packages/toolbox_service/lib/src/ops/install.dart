import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:toolbox_commands/toolbox_commands.dart';
import 'package:toolbox_core/toolbox_core.dart';

import 'context.dart';
import 'root.dart';

/// 安装应用（.apk / .apks / .xapk / .aab）。
///
/// 对应 TS 版 src/main/ops/install.ts。

/// 批量安装：.apk 用 adb install，.apks / .xapk 解开后用 adb install-multiple 装成一个应用；
/// .aab 先用 bundletool 按手机配置转换成分包再安装；.xapk 里带的 OBB 数据包推到 manifest 指定的位置。
/// 所有文件先复制到临时目录再交给 adb，避开中文路径
Future<OperationResult> installApps(List<String> files, OpContext ctx) async {
  if (files.isEmpty) throw const OpException('请先选择要安装的文件');
  final serial = await ctx.requireSystem();
  final abiList = (await ctx.probe.getProps(serial, ctx.cancel))['ro.product.cpu.abilist'] ?? '';
  final dir = workDir(ctx.env);
  final ok = <String>[];
  final failed = <String>[];

  for (var i = 0; i < files.length; i++) {
    final file = files[i];
    final name = p.basename(file);
    final ext = p.extension(file).replaceFirst('.', '').toLowerCase();
    if (!installExtensions.contains(ext) || !File(file).existsSync()) {
      ctx.log(LogLevel.warn, '跳过 $name：不是 APK / APKS / XAPK / AAB 文件');
      failed.add(name);
      continue;
    }
    ctx.step('正在安装 $name（${i + 1}/${files.length}）');

    ExecResult r;
    if (ext == 'apk') {
      final copy = p.join(dir, 'app_$i.apk');
      File(file).copySync(copy);
      r = await ctx.adb.run(serial, ['install', '-r', copy], timeout: const Duration(minutes: 5));
    } else if (ext == 'aab') {
      final out = p.join(dir, 'bundle_$i');
      await _convertAab(file, out, serial, ctx);
      final splits = pickSplits(listFiles(out), abiList);
      if (splits.isEmpty) {
        ctx.log(LogLevel.error, '$name 里没有找到可安装的分包');
        failed.add(name);
        continue;
      }
      ctx.log(LogLevel.info, '$name：${splits.length} 个分包（${[for (final s in splits) p.basename(s)].join('、')}）');
      ctx.log(LogLevel.warn, 'AAB 转换出的分包使用调试密钥签名，无法覆盖从应用商店安装的同一应用');
      r = await ctx.adb.run(
        serial,
        ['install-multiple', '-r', ...splits.map((s) => p.join(out, s))],
        timeout: const Duration(minutes: 10),
      );
    } else {
      final out = p.join(dir, 'bundle_$i');
      Directory(out).createSync(recursive: true);
      final x = await ctx.sevenZip.extract(file, const [], out);
      if (x.code != 0) {
        ctx.log(LogLevel.error, '$name 解压失败，文件可能已损坏或被加密');
        failed.add(name);
        continue;
      }
      final splits = pickSplits(listFiles(out), abiList);
      if (splits.isEmpty) {
        ctx.log(LogLevel.error, '$name 里没有找到 APK');
        failed.add(name);
        continue;
      }
      ctx.log(LogLevel.info, '$name：${splits.length} 个分包（${[for (final s in splits) p.basename(s)].join('、')}）');
      r = await ctx.adb.run(
        serial,
        ['install-multiple', '-r', ...splits.map((s) => p.join(out, s))],
        timeout: const Duration(minutes: 10),
      );
      if (r.code == 0 && r.all.contains('Success') && ext == 'xapk') await _pushObb(serial, out, ctx);
    }

    if (r.code == 0 && r.all.contains('Success')) {
      ok.add(name);
      ctx.log(LogLevel.ok, '$name 安装成功');
    } else {
      failed.add(name);
      ctx.log(LogLevel.error, '$name 安装失败：${failureReason(r.all)}');
    }
  }

  if (failed.isEmpty) {
    return OperationResult(
      ok: true,
      message: ok.length == 1 ? '${ok.first} 安装成功' : '${ok.length} 个应用全部安装成功',
    );
  }
  return OperationResult(
    ok: ok.isNotEmpty,
    message: '成功 ${ok.length} 个，失败 ${failed.length} 个（${failed.join('、')}），失败原因见日志',
  );
}

/// 用 bundletool 把 AAB 按当前手机的配置转换成分包 APK 目录。
/// --connected-device + --device-id 只生成这台手机需要的那几个分包。
/// 电脑上没有调试密钥时用内置的一份签名，否则 bundletool 会输出未签名的 APK，装不上
Future<void> _convertAab(String bundle, String out, String serial, OpContext ctx) async {
  if (!File(ctx.tools.bundletool).existsSync()) {
    throw const OpException('缺少 bundletool，开发环境请先运行 melos run fetch-tools');
  }
  final java = findJava(ctx.tools);
  if (java == null) {
    throw const OpException('没有找到 Java 运行时（工具箱内置的运行时缺失）。请重新安装工具箱；开发环境请先运行 melos run fetch-tools');
  }
  final major = await javaMajor(java, cancel: ctx.cancel);
  if (major != null && major < 11) {
    throw OpException('安装 AAB 需要 Java 11 或更高版本，当前是 Java $major。请升级 Java 后重试');
  }
  final dir = Directory(out);
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  ctx.step('正在把 AAB 转换成分包 APK（文件较大时需要几分钟）');
  final r = await convertAab(
    tools: ctx.tools,
    java: java,
    bundle: bundle,
    out: out,
    serial: serial,
    cancel: ctx.cancel,
    log: ctx.log,
  );
  if (r.code != 0) {
    final lines = r.all.trim().split(RegExp(r'\r?\n')).where((line) => line.trim().isNotEmpty);
    final last = lines.isEmpty ? '未知错误' : lines.last;
    throw OpException('AAB 转换失败：$last');
  }
}

/// XAPK 的 manifest.json 里 expansions 列出 OBB 及其在手机上的位置（如 Android/obb/<包名>/main.1.xxx.obb）
Future<void> _pushObb(String serial, String dir, OpContext ctx) async {
  String? raw;
  try {
    raw = File(p.join(dir, 'manifest.json')).readAsStringSync();
  } catch (_) {
    return;
  }
  for (final e in parseXapkManifest(raw)) {
    final src = p.join(dir, e.file);
    if (!File(src).existsSync()) continue;
    ctx.step('正在推送数据包 ${p.basename(e.installPath)}');
    final r = await ctx.adb.push(serial, src, '/sdcard/${e.installPath}', timeout: const Duration(minutes: 30));
    if (r.code != 0) {
      ctx.log(LogLevel.warn, '数据包 ${p.basename(e.installPath)} 推送失败，应用可能需要自行下载数据');
    }
  }
}
