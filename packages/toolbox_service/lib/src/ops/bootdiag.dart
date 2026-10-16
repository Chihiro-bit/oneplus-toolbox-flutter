import 'package:toolbox_core/toolbox_core.dart';

import 'context.dart';

/// 开机诊断的信息采集，只读，不改动手机：
/// - Fastboot：getvar all（槽位状态、解锁、snapshot 状态）+ oem device-info（critical 是否解锁）
/// - fastbootd：getvar all 里没有 slot-*，单独查询；slot-successful 不可靠，不采用
/// - 开机 / 卡开机时 adb 连得上：getprop、Root 状态、logcat -b crash
/// - 手机不在线且允许等待：adb wait-for-device 抓开机过程中 adb 能连上的那几秒
///
/// 对应 TS 版的 src/main/ops/bootdiag.ts 的 bootCollect()。
Future<OperationResult> bootCollect(OpContext ctx, {required bool waitAdb}) async {
  var d = await ctx.probe.detect(ctx.cancel);
  if (d.needsPick && ctx.probe.selectedSerial == null) {
    throw const OpException('连接了多台设备，请先在左下角选择要操作的那一台');
  }
  // 选中的那台不在线（例如正卡在开机），当作没连上
  if (d.needsPick) d = DeviceInfo.disconnected;
  if (d.mode == DeviceMode.unauthorized) throw const OpException('设备未授权，请在手机弹窗中允许 USB 调试');
  if (d.mode == DeviceMode.edl) throw const OpException('手机在 9008 模式，读不到开机状态。长按 音量上 + 电源键退出后再试');

  final notes = <String>[];
  var mode = d.mode;
  var adbDuringBoot = false;

  if (d.mode == DeviceMode.none) {
    if (!waitAdb) {
      return OperationResult(
        ok: true,
        message: '没有连接设备，只能根据你选择的现象来判断',
        bootState: BootState(mode: DeviceMode.none, notes: ['没有连接设备']),
      );
    }
    ctx.step('正在等待开机过程中的 adb 连接（最多 3 分钟）。请让手机重启，或长按电源键强制重启');
    final got = await ctx.waitForAdb();
    if (got != null) d = await ctx.probe.detect(ctx.cancel);
    // 开机诊断只认「开机」和「Recovery」；其它模式（例如只等到 Fastboot）也算没等到
    if (got == null || d.serial == null || (d.mode != DeviceMode.system && d.mode != DeviceMode.recovery)) {
      return OperationResult(
        ok: true,
        message: '3 分钟内没有等到 adb 连接，只能根据你选择的现象来判断',
        bootState: BootState(
          mode: DeviceMode.none,
          adbDuringBoot: false,
          notes: ['开机过程中 adb 一直没连上（也可能是这台电脑没被手机授权过 USB 调试）'],
        ),
      );
    }
    mode = d.mode;
    adbDuringBoot = true;
    ctx.log(LogLevel.ok, '开机过程中连上了 adb：${d.serial}');
  }
  final serial = d.serial!;

  if (mode == DeviceMode.fastboot || mode == DeviceMode.fastbootd) {
    final userspace = mode == DeviceMode.fastbootd;
    ctx.step('正在读取 Fastboot 变量');
    final vars = parseGetvarAll(await ctx.probe.getvarAll(serial, ctx.cancel));
    if (userspace) {
      for (final s in const ['a', 'b']) {
        for (final k in const ['slot-unbootable', 'slot-retry-count']) {
          final v = await ctx.fastboot.getvar(serial, '$k:$s');
          if (v != null && !RegExp('unknown variable', caseSensitive: false).hasMatch(v)) vars['$k:$s'] = v;
        }
      }
      notes.add('fastbootd 下读不到槽位是否成功启动过；重启到 Fastboot（bootloader）再诊断一次，信息会更全');
    }
    final slot = vars['current-slot'];
    final currentSlot = (slot == 'a' || slot == 'b') ? slot : null;
    final slots = slotsFromVars(vars, userspace);
    var unlocked = _yesNo(vars['unlocked']);
    final snapshotStatus = vars['snapshot-update-status'];
    bool? criticalUnlocked;
    if (!userspace) {
      final info = await ctx.fastboot.run(serial, ['oem', 'device-info'], timeout: const Duration(seconds: 10));
      criticalUnlocked = parseCriticalUnlocked(info.all);
      if (unlocked == null && _deviceUnlocked.hasMatch(info.all)) {
        unlocked = RegExp('Device unlocked:\\s*true', caseSensitive: false).hasMatch(info.all);
      }
    }
    ctx.log(
      LogLevel.info,
      '当前 ${currentSlot?.toUpperCase() ?? '?'} 槽，槽位状态 ${_slotsJson(slots)}，snapshot ${snapshotStatus ?? '未知'}',
    );
    return OperationResult(
      ok: true,
      message: '已读取 Fastboot 下的设备状态',
      bootState: BootState(
        mode: mode,
        serial: serial,
        currentSlot: currentSlot,
        slots: slots,
        unlocked: unlocked,
        criticalUnlocked: criticalUnlocked,
        snapshotStatus: snapshotStatus,
        adbDuringBoot: adbDuringBoot,
        notes: notes,
      ),
    );
  }

  // 开机或 Recovery（adb）
  ctx.step('正在读取系统属性');
  final props = await ctx.probe.getProps(serial, ctx.cancel);
  final bootCompleted = props['sys.boot_completed'] == '1';
  final suffix = props['ro.boot.slot_suffix']?.replaceFirst(RegExp('^_'), '');
  final currentSlot = (suffix == 'a' || suffix == 'b') ? suffix : null;
  // 还没开机完成就能连上 adb，等同于抓到了开机过程中的 adb
  if (mode == DeviceMode.system && !bootCompleted) adbDuringBoot = true;
  final root = mode == DeviceMode.system ? await ctx.probe.rootStatus(serial, ctx.cancel) : null;
  if (mode == DeviceMode.recovery) notes.add('手机在 Recovery，读到的是 Recovery 自己的属性');

  ctx.step('正在读取崩溃日志');
  final crash = await ctx.adb.run(
    serial,
    ['shell', 'logcat', '-b', 'crash', '-d', '-t', '80'],
    timeout: const Duration(seconds: 20),
    echoOutput: false,
  );
  final crashLog = crash.code == 0 && crash.stdout.trim().isNotEmpty ? crash.stdout.trim() : null;
  if (bootCompleted) notes.add('手机已经正常开机完成');
  return OperationResult(
    ok: true,
    message: bootCompleted ? '手机已经正常开机，状态已读取' : '已读取开机过程中的状态',
    bootState: BootState(
      mode: mode,
      serial: serial,
      currentSlot: currentSlot,
      adbDuringBoot: adbDuringBoot,
      bootCompleted: bootCompleted,
      crashLog: crashLog,
      root: root,
      notes: notes,
    ),
  );
}

/// 处理没合并完的虚拟 A/B 更新，只能在 fastbootd 下执行：
/// cancel 放弃更新（之后才能正常刷分区），merge 让正在进行的合并继续完成
///
/// 对应 TS 版的 src/main/ops/bootdiag.ts 的 snapshotUpdate()。
Future<OperationResult> snapshotUpdate(SnapshotUpdateAction action, OpContext ctx) async {
  final d = await ctx.probe.detect(ctx.cancel);
  if (d.needsPick) throw const OpException('连接了多台设备，请先在左下角选择要操作的那一台');
  if (d.serial == null ||
      (d.mode != DeviceMode.system && d.mode != DeviceMode.fastboot && d.mode != DeviceMode.fastbootd)) {
    throw const OpException('请让手机进入 Fastboot，或者开机并开启 USB 调试');
  }
  var serial = d.serial!;
  if (d.mode != DeviceMode.fastbootd) {
    ctx.step('正在重启到 fastbootd');
    if (d.mode == DeviceMode.fastboot) {
      await ctx.fastboot.run(serial, ['reboot', 'fastboot']);
    } else {
      await ctx.adb.reboot(serial, 'fastboot');
    }
    final fd = await ctx.probe.waitForMode(
      {DeviceMode.fastbootd},
      timeout: const Duration(minutes: 2),
      serial: serial,
      cancel: ctx.cancel,
      log: ctx.log,
    );
    ctx.device(fd);
    serial = fd.serial!;
  }
  final before = await ctx.fastboot.getvar(serial, 'snapshot-update-status');
  ctx.log(LogLevel.info, 'snapshot-update-status: ${before ?? '未知'}');
  if (before == 'none') {
    return const OperationResult(ok: true, message: '没有未合并的系统更新，不需要处理。手机停留在 fastbootd');
  }

  final name = action.name;
  ctx.step(action == SnapshotUpdateAction.cancel ? '正在取消未合并的更新' : '正在继续合并更新');
  final r = await ctx.fastboot.run(
    serial,
    ['snapshot-update', name],
    timeout: action == SnapshotUpdateAction.merge ? const Duration(minutes: 30) : const Duration(seconds: 60),
  );
  if (!r.ok) return OperationResult(ok: false, message: 'snapshot-update $name 失败，详见日志。手机停留在 fastbootd');
  final after = await ctx.fastboot.getvar(serial, 'snapshot-update-status');
  return OperationResult(
    ok: true,
    message: '已执行 snapshot-update $name，现在的状态是 ${after ?? '未知'}。手机停留在 fastbootd，可以在「重启与模式」中开机',
  );
}

bool? _yesNo(String? v) => v == 'yes' ? true : (v == 'no' ? false : null);

final _deviceUnlocked = RegExp('Device unlocked:\\s*(true|false)', caseSensitive: false);

/// 槽位状态转成和 TS 版 `JSON.stringify(st.slots)` 一样的字符串（值为 null 的字段不输出）
String _slotsJson(Map<String, SlotState> slots) {
  final entries = <String>[];
  for (final e in slots.entries) {
    final fields = <String>[
      if (e.value.successful != null) '"successful":${e.value.successful}',
      if (e.value.unbootable != null) '"unbootable":${e.value.unbootable}',
      if (e.value.retryCount != null) '"retryCount":${e.value.retryCount}',
    ];
    entries.add('"${e.key}":{${fields.join(',')}}');
  }
  return '{${entries.join(',')}}';
}
