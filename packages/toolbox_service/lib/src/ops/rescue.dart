import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:toolbox_commands/toolbox_commands.dart';
import 'package:toolbox_core/toolbox_core.dart';

import '../known.dart';
import 'context.dart';
import 'root.dart';

/// 可以从 ROM 刷回的原厂分区（都是 bootloader 下就能刷的物理分区，不含 super 里的逻辑分区）
const stockPartitions = [
  StockPartition.initBoot,
  StockPartition.boot,
  StockPartition.vendorBoot,
  StockPartition.dtbo,
  StockPartition.vbmeta,
  StockPartition.vbmetaSystem,
  StockPartition.vbmetaVendor,
];

// ───────────── 从 ROM 提取镜像 ─────────────
//
// workDir() / findFile() 在 ops/root.dart 里，与 TS 版的 ops/root.ts 一致，各 op 共用。
// 这里的 extractImages() 是通用版（可指定分区、可允许读不到手机版本），救援与备份用它；
// root 流程仍用 ops/root.dart 里那份只提取 boot / init_boot 的实现，两者行为一致。

final _partitionName = RegExp(r'^[a-z_]+$');

/// 从 ROM 中取出指定分区的镜像（默认 boot.img / init_boot.img）。
/// 1. 标准 OTA（payload.bin，本地 zip 或 URL）：先比对 ROM 的构建时间与手机 ro.build.date.utc，不一致则拒绝
/// 2. 镜像直接放在 zip 根目录（线刷包）：用 7-Zip 提取，无法校验版本，只给警告
///
/// [allowUnverified]：读不到手机版本时（例如卡开机只能进 Fastboot）只给警告、不拒绝。版本明确不一致时始终拒绝
Future<void> extractImages(
  String rom,
  String? deviceTimestamp,
  String dir,
  OpContext ctx, {
  bool allowUnverified = false,
  List<String> partitions = const ['boot', 'init_boot'],
}) async {
  if (partitions.any((x) => !_partitionName.hasMatch(x))) throw const OpException('分区名不合法');
  final names = partitions.join(' / ');
  final url = isUrl(rom);
  ctx.step(url ? '正在从链接读取 ROM 信息（只读取需要的部分）' : '正在读取 ROM 信息');
  final romTs = await ctx.payloadDumper.maxTimestamp(rom, dir);
  if (romTs != null) {
    ctx.log(LogLevel.info, 'ROM 构建时间 = $romTs，手机 ro.build.date.utc = ${deviceTimestamp ?? '未知'}');
    if (deviceTimestamp == null) {
      if (!allowUnverified) throw const OpException('无法读取手机的系统版本信息，可能是连接不稳定');
      ctx.log(LogLevel.warn, '读不到手机的系统版本，无法校验 ROM 是否一致，按你的选择继续');
    } else if (romTs != deviceTimestamp) {
      throw const OpException('ROM 与手机当前系统版本不一致，继续操作可能导致无法开机。为了安全，已停止操作');
    } else {
      ctx.log(LogLevel.ok, 'ROM 与手机系统版本一致');
    }
    ctx.step(url ? '正在从链接提取镜像（只下载 $names 所需的数据）' : '正在从 payload 中提取镜像');
    if (!await ctx.payloadDumper.extract(rom, partitions, dir)) {
      throw const OpException('从 ROM 中提取镜像失败，详见日志');
    }
    return;
  }

  if (url) {
    throw const OpException('无法从这个链接读取 ROM。链接需要直接指向完整的 OTA 包（.zip），并且服务器支持分段下载');
  }

  ctx.step('正在用 7-Zip 查找镜像');
  final listing = await ctx.sevenZip.list(rom);
  if (!partitions.any((x) => SevenZip.listContains(listing, '$x.img'))) {
    throw OpException('这个文件既不是标准 OTA 包，也没有在根目录找到 ${partitions.map((x) => '$x.img').join(' / ')}，请确认选择的是完整的全量包');
  }
  await ctx.sevenZip.extract(rom, [for (final x in partitions) '$x.img'], dir);
  ctx.log(LogLevel.warn, '此 ROM 不含版本元数据，无法自动校验是否与手机系统一致，请自行确认');
}

/// 与 TS 版 `new Date(t).toLocaleString('zh-CN', { hour12: false })` 一致，形如 `2026/10/15 14:30:05`
String formatDateTime(int millis) {
  final t = DateTime.fromMillisecondsSinceEpoch(millis);
  String two(int v) => '$v'.padLeft(2, '0');
  return '${t.year}/${t.month}/${t.day} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

// ───────────── 刷回原厂镜像 ─────────────

/// 手机当前的系统版本：开机时直接读，Fastboot 下用上次开机时的记录
Future<FlashBuild> _deviceBuild(String serial, DeviceMode mode, OpContext ctx) async {
  if (mode == DeviceMode.system) {
    ctx.step('正在读取手机信息');
    final props = await ctx.probe.getProps(serial, ctx.cancel);
    return FlashBuild(
      buildId: props['ro.build.display.id'],
      romVersion: props['ro.build.version.oplusrom'],
      buildDateUtc: props['ro.build.date.utc'],
    );
  }
  // OpContext 上没有 KnownStore，只能用同一份 <dataDir>/devices.json 重新读一次
  final known = KnownStore(ctx.env.dataDir).get(serial);
  if (known != null) {
    ctx.log(
      LogLevel.info,
      '使用这台手机上次开机时记下的系统版本：${known.buildId ?? ''} ${known.romVersion ?? ''}'.trim(),
    );
  }
  return FlashBuild(buildId: known?.buildId, romVersion: known?.romVersion, buildDateUtc: known?.buildDateUtc);
}

/// 从 ROM 中取出指定分区的原厂镜像，进 Fastboot 刷回当前槽位，并记入刷写记录。返回 Fastboot 下的序列号。
/// 开机状态下读手机版本做校验；Fastboot 下用之前开机连接时记下的版本，记录也没有时需要用户明确同意才继续。
Future<String> _flashStock(
  String rom,
  List<StockPartition> partitions,
  bool allowUnverified,
  FlashKind kind,
  OpContext ctx,
) async {
  final d = await ctx.requireDevice();
  if (d.mode != DeviceMode.system && d.mode != DeviceMode.fastboot && d.mode != DeviceMode.fastbootd) {
    throw const OpException('请让手机开机（开启 USB 调试），或者进入 Fastboot 模式后再操作');
  }
  final parts = [
    for (final x in partitions)
      if (stockPartitions.contains(x)) x
  ];
  if (parts.isEmpty) throw const OpException('请选择要刷回的分区');

  final build = await _deviceBuild(d.serial!, d.mode, ctx);
  if (build.buildDateUtc == null && !allowUnverified) {
    throw const OpException('手机在 Fastboot 模式下读不到系统版本，工具箱也没有这台手机之前开机时的记录。请确认 ROM 版本后勾选「读不到版本时仍然继续」');
  }

  final dir = workDir(ctx.env);
  await extractImages(
    rom.trim(),
    build.buildDateUtc,
    dir,
    ctx,
    allowUnverified: allowUnverified,
    partitions: [for (final x in parts) x.id],
  );
  final images = <(StockPartition, String)>[
    for (final part in parts)
      if (findFile(dir, '${part.id}.img') case final img?) (part, img),
  ];
  if (images.isEmpty) {
    throw OpException('没能从 ROM 中提取出 ${parts.map((x) => x.id).join(' / ')}，请确认选择的是完整的全量包');
  }
  final missing = [
    for (final x in parts)
      if (!images.any((e) => e.$1 == x)) x.id
  ];
  if (missing.isNotEmpty) ctx.log(LogLevel.warn, 'ROM 中没有 ${missing.join('、')}，跳过');
  ctx.log(LogLevel.ok, '将刷回原厂 ${images.map((e) => e.$1.id).join('、')}');

  final fb = await ctx.ensureFastboot();
  ctx.step('正在检测 Bootloader 解锁状态');
  if (await ctx.fastboot.isUnlocked(fb) != true) {
    throw const OpException('Bootloader 未解锁，无法刷写。设备停留在 Fastboot，可以在「重启与模式」中开机');
  }

  final flashed = <FlashPartition>[];
  for (final e in images) {
    flashed.add(FlashPartition(name: e.$1.id, source: FlashSource.stock, sha256: await sha256File(e.$2)));
  }
  final rec = ctx.history.add(
    serial: fb,
    kind: kind,
    slot: await ctx.fastboot.getvar(fb, 'current-slot'),
    build: build,
    partitions: flashed,
  );
  for (final (part, img) in images) {
    ctx.step('正在刷回原厂 ${part.id}');
    final r = await ctx.fastboot.flash(fb, part.id, img);
    if (!r.ok) {
      ctx.history.update(fb, rec.id, status: FlashStatus.failed);
      throw OpException('刷入 ${part.id} 失败，设备仍在 Fastboot 模式，可以重试或切换槽位');
    }
  }
  ctx.history.update(fb, rec.id, status: FlashStatus.ok);
  ctx.log(LogLevel.ok, '原厂镜像已刷回');
  await ctx.fastboot.reboot(fb);
  return fb;
}

/// 从 ROM 刷回指定的原厂分区（开机诊断里「刷回原厂 vbmeta」等修复用）
Future<OperationResult> restoreStock(RestoreOptions opts, OpContext ctx) async {
  await _flashStock(opts.rom, opts.partitions, opts.allowUnverified, FlashKind.restore, ctx);
  return OperationResult(
    ok: true,
    message: '已刷回原厂 ${opts.partitions.map((x) => x.id).join('、')}，手机正在重启',
  );
}

/// 卸载 Root：把 ROM 里原厂的 boot / init_boot 一起刷回当前槽位。各家 Root 方案改的都是这两个分区之一，
/// 两个都刷回原厂就等于卸载了 Root；Root 后卡开机时，这也是最可靠的救法。
Future<OperationResult> unroot(UnrootOptions opts, OpContext ctx) async {
  final fb = await _flashStock(
    opts.rom,
    const [StockPartition.initBoot, StockPartition.boot],
    opts.allowUnverified,
    FlashKind.unroot,
    ctx,
  );

  if (!opts.uninstallManagers) {
    return const OperationResult(
      ok: true,
      message: '已刷回原厂镜像，手机正在重启。Root 模块文件仍保留在手机上，重新 Root 后会再次生效',
    );
  }

  // 卸载管理器需要 adb，等手机开机
  ctx.step('等待手机开机，以便卸载 Root 管理器（最多 3 分钟）');
  String serial;
  try {
    serial = (await ctx.probe.waitForMode(
      {DeviceMode.system},
      timeout: const Duration(minutes: 3),
      serial: fb,
      cancel: ctx.cancel,
      log: ctx.log,
    ))
        .serial!;
  } on CancelledException {
    rethrow;
  } catch (_) {
    return const OperationResult(
      ok: true,
      message: '已刷回原厂镜像。没等到手机开机，Root 管理器 App 未卸载，可以在手机上手动卸载',
    );
  }
  ctx.step('正在卸载 Root 管理器');
  final removed = <String>[];
  for (final pkg in knownManagers) {
    final r =
        await ctx.adb.shell(serial, ['pm', 'uninstall', pkg], timeout: const Duration(seconds: 30), echoOutput: false);
    if (r.stdout.contains('Success')) removed.add(pkg);
  }
  ctx.device(await ctx.probe.describe(await ctx.probe.detect(ctx.cancel), ctx.cancel));
  return OperationResult(
    ok: true,
    message: '已刷回原厂镜像，手机已开机。'
        '${removed.isNotEmpty ? '已卸载 ${removed.join('、')}' : '没有找到需要卸载的管理器 App'}',
  );
}

// ───────────── 撤销上一次刷写 ─────────────

/// 把上一次刷写前备份的原厂镜像刷回原来的分区和槽位。不需要 ROM，是 Root 后卡开机最快的救法。
/// 手机在那之后升级过系统（构建时间变了）时拒绝：备份对应的是旧系统，刷回去反而可能起不来。
Future<OperationResult> undoFlash(OpContext ctx) async {
  final d = await ctx.requireDevice();
  if (d.mode != DeviceMode.system && d.mode != DeviceMode.fastboot && d.mode != DeviceMode.fastbootd) {
    throw const OpException('请让手机开机（开启 USB 调试），或者进入 Fastboot 模式后再操作');
  }
  final rec = ctx.history.undoable(d.serial!);
  if (rec == null) {
    throw const OpException('这台手机没有可以撤销的刷写。工具箱只能撤销由它完成、并且刷写前备份过原厂镜像的 Root');
  }
  ctx.log(
    LogLevel.info,
    '上一次刷写：${formatDateTime(rec.time)} ${rec.scheme ?? rec.kind.name}，'
    '${rec.partitions.map((x) => x.name).join('、')}，${rec.slot?.toUpperCase() ?? '?'} 槽',
  );

  final build = await _deviceBuild(d.serial!, d.mode, ctx);
  if (rec.build.buildDateUtc != null && build.buildDateUtc != null && rec.build.buildDateUtc != build.buildDateUtc) {
    throw const OpException('上一次刷写之后，手机的系统版本已经变了（升级过系统），备份的原厂镜像不再对应当前系统。请改用「刷回原厂镜像」并选择当前版本的 ROM');
  }

  ctx.step('正在校验备份的原厂镜像');
  final dir = workDir(ctx.env);
  final images = <(String, String)>[];
  for (final e in rec.backups.entries) {
    final backup = e.value;
    if (!File(backup.path).existsSync()) throw OpException('找不到备份文件 ${backup.path}，可能被删除或移动了');
    if (await sha256File(backup.path) != backup.sha256) {
      throw OpException('备份文件 ${backup.path} 的内容和刷写时记录的不一致，为了安全已停止');
    }
    // 复制到临时目录再刷，避开「文档\一加工具箱」中文路径
    final tmp = p.join(dir, '${e.key}.img');
    File(backup.path).copySync(tmp);
    images.add((e.key, tmp));
  }

  final fb = await ctx.ensureFastboot();
  ctx.step('正在检测 Bootloader 解锁状态');
  if (await ctx.fastboot.isUnlocked(fb) != true) {
    throw const OpException('Bootloader 未解锁，无法刷写。设备停留在 Fastboot，可以在「重启与模式」中开机');
  }

  // 刷回当时的槽位；之后切换过槽位也不会刷错
  final slot = (rec.slot == 'a' || rec.slot == 'b') ? rec.slot : null;
  final undo = ctx.history.add(
    serial: fb,
    kind: FlashKind.undo,
    slot: slot ?? await ctx.fastboot.getvar(fb, 'current-slot'),
    build: rec.build,
    partitions: [
      for (final e in images) FlashPartition(name: e.$1, source: FlashSource.stock, sha256: rec.backups[e.$1]!.sha256),
    ],
  );
  for (final (part, img) in images) {
    final target = slot != null ? '${part}_$slot' : part;
    ctx.step('正在刷回原厂 $target');
    final r = await ctx.fastboot.flash(fb, target, img);
    if (!r.ok) {
      ctx.history.update(fb, undo.id, status: FlashStatus.failed);
      throw OpException('刷入 $target 失败，设备仍在 Fastboot 模式，可以重试');
    }
  }
  ctx.history.update(fb, undo.id, status: FlashStatus.ok);
  ctx.history.update(fb, rec.id, undone: true);
  await ctx.fastboot.reboot(fb);
  return OperationResult(
    ok: true,
    message: '已把 ${images.map((e) => e.$1).join('、')} 恢复成刷写前的原厂镜像，手机正在重启',
  );
}

// ───────────── 模块导致卡开机 ─────────────

/// 卡开机时 adb 往往只在开机过程中连得上几秒，所以手机不在线时先 `adb wait-for-device` 等着，一连上立刻执行。
/// 前提是这台电脑之前已经被手机授权过 USB 调试。
Future<OperationResult> modules(ModuleAction action, OpContext ctx) async {
  String serial;
  final d = await ctx.probe.detect(ctx.cancel);
  // needsPick：选中的那台不在线（例如正卡在开机），当作「没连上」去等它
  final online = d.mode != DeviceMode.none && !d.needsPick;
  if (online && d.mode == DeviceMode.unauthorized) {
    throw const OpException('设备未授权，请在手机弹窗中允许 USB 调试');
  }
  if (online && (d.mode == DeviceMode.system || d.mode == DeviceMode.recovery)) {
    serial = d.serial!;
  } else {
    if (online) throw const OpException('请让手机开机（卡在开机画面也可以），这个功能需要 adb 连接');
    ctx.step('正在等待手机连上 adb（最多 3 分钟）。卡开机的话，请让它重启或长按电源键强制重启');
    final got = await ctx.waitForAdb();
    if (got == null) {
      throw const OpException('3 分钟内没有等到 adb 连接。可能这台电脑没被手机授权过 USB 调试，或系统还没启动到 adb 阶段');
    }
    serial = got;
    ctx.log(LogLevel.ok, '已连接 $serial');
  }

  if (action == ModuleAction.remove) {
    ctx.step('正在执行 magisk --remove-modules');
    final r = await ctx.adb.shell(serial, [removeModulesCommand], timeout: const Duration(seconds: 60));
    if (r.stdout.contains(noMagiskMarker)) {
      return OperationResult(ok: false, message: '手机上没有 Magisk，无法用这个办法。$safeModeTip');
    }
    // 成功时 Magisk 会删除全部模块并立即重启，adb 随之断开
    return const OperationResult(ok: true, message: '已删除全部 Magisk 模块，手机正在重启');
  }

  ctx.step(action == ModuleAction.disable ? '正在禁用全部模块，手机上弹出 Root 授权时请点允许' : '正在重新启用全部模块');
  // timeout：没有管理器能弹授权窗（例如卡开机）时，Magisk 默认 10 秒后拒绝
  final r = await ctx.adb.shell(serial, [modulesShellCommand(action)!], timeout: const Duration(seconds: 45));
  final n = parseModulesResult(r.stdout);
  if (n == null) {
    return OperationResult(
      ok: false,
      message: action == ModuleAction.disable
          ? '没有拿到 Root 授权，模块未改动。使用 Magisk 时可以改用「删除全部模块」；$safeModeTip'
          : '没有拿到 Root 授权，模块未改动。请在 Root 管理器里允许 Shell 的超级用户权限后再试',
    );
  }
  if (n == 0) {
    return OperationResult(ok: true, message: action == ModuleAction.disable ? '手机上没有需要禁用的模块' : '没有被禁用的模块');
  }

  if (action == ModuleAction.enable) return OperationResult(ok: true, message: '已重新启用 $n 个模块，重启手机后生效');
  ctx.step('正在重启手机');
  await ctx.adb.reboot(serial);
  return OperationResult(
    ok: true,
    message: '已禁用 $n 个模块，手机正在重启。确认能开机后，可以在 Root 管理器里逐个启用，找出有问题的模块',
  );
}
