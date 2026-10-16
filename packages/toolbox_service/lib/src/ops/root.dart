import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:toolbox_commands/toolbox_commands.dart';
import 'package:toolbox_core/toolbox_core.dart';

import '../catalog_repository.dart';
import '../environment.dart';
import 'context.dart';

/// 可修补的分区
enum Partition {
  boot('boot'),
  initBoot('init_boot');

  const Partition(this.id);

  /// fastboot 中的分区名
  final String id;

  String get image => '$id.img';

  Partition get other => this == boot ? initBoot : boot;
}

/// 决定修补哪个分区：APatch 修补内核，只能用 boot；其它方式在 Android 13 及以后出厂的机型上修补 init_boot
Partition choosePartition(RootFamily family, PatchTarget target, {required bool hasInitBoot}) {
  if (family == RootFamily.apatch) {
    if (target == PatchTarget.initBoot) throw const OpException('APatch 只能修补 boot.img');
    return Partition.boot;
  }
  return switch (target) {
    PatchTarget.auto => hasInitBoot ? Partition.initBoot : Partition.boot,
    PatchTarget.boot => Partition.boot,
    PatchTarget.initBoot => Partition.initBoot,
  };
}

/// 修补后镜像的文件名，形如 `Magisk_patched_init_boot_OP5D0DL1_20261014120000.img`
String patchedFileName(String schemeName, Partition partition, String device, DateTime now) {
  final stamp = now.toIso8601String().replaceAll(RegExp(r'[-:T]'), '').substring(0, 14);
  final tag = schemeName.replaceAll(RegExp(r'[^\w.-]+'), '_');
  return '${tag}_patched_${partition.id}_${device}_$stamp.img';
}

// ───────────── 工作目录 ─────────────

/// 每次操作前重建的临时工作目录（对应 TS 版 ops/root.ts 的 workDir()，各 op 共用一份）
String workDir(ToolboxEnvironment env) {
  final dir = Directory(p.join(env.tempDir, 'oneplus-toolbox', 'work'));
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  return dir.path;
}

/// 「文档\一加工具箱」：修补后的镜像、截图、备份都放在这里
String outputDir(ToolboxEnvironment env) {
  final dir = Directory(p.join(env.documentsDir, '一加工具箱'))..createSync(recursive: true);
  return dir.path;
}

/// 在目录中递归查找指定文件名（跳过空文件）
String? findFile(String dir, String name) {
  for (final e in Directory(dir).listSync(recursive: true)) {
    if (e is File && p.basename(e.path) == name && e.lengthSync() > 0) return e.path;
  }
  return null;
}

// ───────────── 从 ROM 提取镜像 ─────────────

/// 从 ROM 中取出 boot.img / init_boot.img。
/// 1. 标准 OTA（payload.bin，本地 zip 或 URL）：先比对 ROM 的构建时间与手机 ro.build.date.utc，不一致则拒绝
/// 2. 镜像直接放在 zip 根目录（线刷包）：用 7-Zip 提取，无法校验版本，只给警告
Future<void> _extractImages(String rom, String? deviceTimestamp, String dir, OpContext ctx) async {
  final url = isUrl(rom);
  ctx.step(url ? '正在从链接读取 ROM 信息（只读取需要的部分）' : '正在读取 ROM 信息');
  final romTs = await ctx.payloadDumper.maxTimestamp(rom, dir);
  if (romTs != null) {
    ctx.log(LogLevel.info, 'ROM 构建时间 = $romTs，手机 ro.build.date.utc = ${deviceTimestamp ?? '未知'}');
    if (deviceTimestamp == null) throw const OpException('无法读取手机的系统版本信息，可能是连接不稳定');
    if (romTs != deviceTimestamp) {
      throw const OpException('ROM 与手机当前系统版本不一致，继续操作可能导致无法开机。为了安全，已停止操作');
    }
    ctx.log(LogLevel.ok, 'ROM 与手机系统版本一致');
    ctx.step(url ? '正在从链接提取镜像（只下载 boot / init_boot 所需的数据）' : '正在从 payload 中提取镜像');
    if (!await ctx.payloadDumper.extract(rom, [Partition.boot.id, Partition.initBoot.id], dir)) {
      throw const OpException('从 ROM 中提取镜像失败，详见日志');
    }
    return;
  }

  if (url) throw const OpException('无法从这个链接读取 ROM。链接需要直接指向完整的 OTA 包（.zip），并且服务器支持分段下载');

  ctx.step('正在用 7-Zip 查找镜像');
  final listing = await ctx.sevenZip.list(rom);
  if (!SevenZip.listContains(listing, Partition.boot.image) &&
      !SevenZip.listContains(listing, Partition.initBoot.image)) {
    throw const OpException('这个文件既不是标准 OTA 包，也没有在根目录找到 boot.img / init_boot.img，请确认选择的是完整的全量包');
  }
  await ctx.sevenZip.extract(rom, [Partition.boot.image, Partition.initBoot.image], dir);
  ctx.log(LogLevel.warn, '此 ROM 不含版本元数据，无法自动校验是否与手机系统一致，请自行确认');
}

// ───────────── 方案与 APK ─────────────

class _ResolvedScheme {
  const _ResolvedScheme({required this.name, required this.family, required this.apk, this.package});

  final String name;
  final RootFamily family;
  final String? package;

  /// 本地 APK 路径
  final String apk;
}

Future<_ResolvedScheme> _resolveScheme(
  RootOptions opts,
  OpContext ctx,
  CatalogRepository catalog,
  ToolboxEnvironment env,
) async {
  if (opts.schemeId == customSchemeId) {
    final apk = opts.customApk;
    if (apk == null || !File(apk).existsSync()) throw const OpException('请选择要使用的 APK 文件');
    final family = opts.customFamily;
    if (family == null) throw const OpException('请选择 APK 对应的修补方式');
    ctx.log(LogLevel.warn, '使用自定义 APK：无法校验来源，请确认文件来自项目官方发布页');
    return _ResolvedScheme(name: '自定义（${family.label}）', family: family, apk: apk);
  }

  final scheme = await catalog.find(opts.schemeId);
  if (scheme == null) throw const OpException('找不到所选的 Root 方案，请刷新方案列表');
  if (scheme.apk.bundled) {
    return _ResolvedScheme(name: scheme.name, family: scheme.family, package: scheme.package, apk: ctx.tools.magiskApk);
  }
  final url = scheme.apk.url;
  final sha = scheme.apk.sha256;
  if (url == null || sha == null) throw OpException('${scheme.name} 缺少下载地址或校验值');

  final label = '${scheme.name} ${scheme.version}';
  var lastPct = -10;
  try {
    final file = await downloadVerified(
      url,
      sha,
      p.join(env.dataDir, 'apk-cache'),
      cancel: ctx.cancel,
      onStart: () {
        ctx.step('正在下载 $label');
        ctx.log(LogLevel.cmd, 'GET $url');
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
    return _ResolvedScheme(name: scheme.name, family: scheme.family, package: scheme.package, apk: file.path);
  } on ChecksumMismatchException catch (e) {
    throw OpException('$label 校验失败：期望 sha256 ${e.expected}，实际 ${e.actual}。文件可能被篡改或下载不完整，已丢弃');
  } on HttpStatusException catch (e) {
    throw OpException('下载失败：HTTP ${e.status}');
  }
}

String _mb(int bytes) => (bytes / 1048576).toStringAsFixed(1);

const _afterRoot = {
  RootFamily.magisk: '开机后打开 Magisk App，按提示完成「额外的设置」即可',
  RootFamily.apatch: '开机后打开 APatch，输入刚才设置的超级密钥完成激活',
  RootFamily.ksu: '开机后打开 KernelSU 管理器，确认显示「工作中」即可',
};

// ───────────── 主流程 ─────────────

Future<OperationResult> root(
  RootOptions opts,
  OpContext ctx, {
  required CatalogRepository catalog,
  required ToolboxEnvironment env,
}) async {
  final serial = await ctx.requireSystem();

  ctx.step('正在读取手机信息');
  final props = await ctx.adb.getprop(serial);
  final abi = props['ro.product.cpu.abi'] ?? '';
  if (!abi.contains('arm64')) throw OpException('当前仅支持 arm64 设备（检测到 ${abi.isEmpty ? '未知架构' : abi}）');
  final echo = await ctx.adb.shell(serial, ['echo', 'hello']);
  if (!echo.stdout.contains('hello')) throw const OpException('adb shell 连接失败，可能连接不稳定');

  final scheme = await _resolveScheme(opts, ctx, catalog, env);
  if (scheme.family == RootFamily.apatch) {
    final problem = superkeyProblem(opts.superkey);
    if (problem != null) throw OpException(problem == '请设置超级密钥' ? problem : '超级密钥$problem');
  }
  ctx.log(LogLevel.ok, 'Root 方案：${scheme.name}（${scheme.family.label}）');

  final dir = workDir(env);
  await _extractImages(opts.rom.trim(), props['ro.build.date.utc'], dir, ctx);
  final images = {for (final part in Partition.values) part: findFile(dir, part.image)};
  ctx.log(LogLevel.info,
      '提取结果：boot.img ${images[Partition.boot] != null ? '✓' : '✗'}  init_boot.img ${images[Partition.initBoot] != null ? '✓' : '✗'}');

  final partition = choosePartition(scheme.family, opts.target, hasInitBoot: images[Partition.initBoot] != null);
  final source = images[partition];
  if (source == null) throw OpException('未能从 ROM 中提取出 ${partition.image}，请确认选择的是完整的全量包');
  ctx.log(LogLevel.ok, '将修补 ${partition.image}');

  ctx.step('正在手机上修补 ${partition.image}');
  await ctx.adb.shell(serial, ['rm', '-rf', remoteDir]);
  await ctx.adb.shell(serial, ['mkdir', '-p', remoteDir]);
  final pushApk = await ctx.adb.push(serial, scheme.apk, '$remoteDir/root.apk');
  final pushImg = await ctx.adb.push(serial, source, '$remoteDir/${partition.image}');
  if (!pushApk.ok || !pushImg.ok) throw const OpException('推送文件到手机失败');
  final scriptPath = p.join(dir, 'patch.sh');
  File(scriptPath).writeAsStringSync(patchScript(scheme.family, partition.image, superkey: opts.superkey));
  await ctx.adb.push(serial, scriptPath, '$remoteDir/patch.sh');
  final patch = await ctx.adb.shell(serial, ['sh', '$remoteDir/patch.sh'], timeout: const Duration(minutes: 10));
  if (!patch.stdout.contains(patchOkMarker)) {
    await ctx.adb.shell(serial, ['rm', '-rf', remoteDir]);
    throw OpException('${partition.image} 修补失败，详见日志');
  }

  final patched = p.join(dir, 'patched_${partition.image}');
  await ctx.adb.pull(serial, '$remoteDir/out.img', patched);
  await ctx.adb.shell(serial, ['rm', '-rf', remoteDir]);
  final patchedFile = File(patched);
  if (!patchedFile.existsSync() || patchedFile.lengthSync() == 0) throw const OpException('从手机取回修补后的镜像失败');

  final saved = p.join(
    outputDir(env),
    patchedFileName(scheme.name, partition, props['ro.product.device'] ?? 'device', DateTime.now()),
  );
  patchedFile.copySync(saved);
  ctx.log(LogLevel.ok, '修补后的镜像已保存：$saved');

  if (opts.patchOnly) {
    return OperationResult(
      ok: true,
      message: '修补完成，镜像已保存。可手动执行 fastboot flash ${partition.id} 刷入',
      outputPath: saved,
    );
  }

  if (opts.uninstallOthers) {
    ctx.step('正在卸载其它 Root 管理器');
    for (final pkg in knownManagers.where((p) => p != scheme.package)) {
      final r = await ctx.adb
          .shell(serial, ['pm', 'uninstall', pkg], timeout: const Duration(seconds: 30), echoOutput: false);
      if (r.stdout.contains('Success')) ctx.log(LogLevel.info, '已卸载 $pkg');
    }
  }

  ctx.step('正在安装 ${scheme.name} 管理器，请留意手机上的安装提示');
  if (await ctx.adb.install(serial, scheme.apk)) {
    ctx.log(LogLevel.ok, '管理器 App 已安装');
  } else {
    ctx.log(LogLevel.warn, '管理器 App 安装未确认，Root 完成后可手动安装');
  }

  final fbSerial = await ctx.ensureFastboot();
  ctx.step('正在检测 Bootloader 解锁状态');
  if (await ctx.fastboot.isUnlocked(fbSerial) != true) {
    await ctx.fastboot.reboot(fbSerial);
    throw const OpException('Bootloader 未解锁，无法刷入。请先完成解锁（修补后的镜像已保存，可稍后手动刷入）');
  }

  // 用临时目录里的副本刷入，避开「文档\一加工具箱」中文路径
  ctx.step('正在刷入 ${partition.id}');
  final flash = await ctx.fastboot.flash(fbSerial, partition.id, patched);
  if (!flash.ok) throw OpException('刷入 ${partition.id} 失败，设备仍在 Fastboot 模式，可尝试重刷或切换槽位');

  // 原厂的另一个分区一并刷回，清除之前装过的其它 Root
  final other = partition.other;
  final otherImage = images[other];
  if (opts.flashOther && otherImage != null) {
    ctx.step('正在刷入原厂 ${other.id}');
    final r = await ctx.fastboot.flash(fbSerial, other.id, otherImage);
    if (!r.ok) ctx.log(LogLevel.warn, '原厂 ${other.id} 刷入失败，不影响本次 Root');
  }

  await ctx.fastboot.reboot(fbSerial);
  return OperationResult(
    ok: true,
    message: '刷入完成，手机正在重启。${_afterRoot[scheme.family]}',
    outputPath: saved,
  );
}
