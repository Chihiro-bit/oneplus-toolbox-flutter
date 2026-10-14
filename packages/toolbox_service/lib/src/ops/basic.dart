import 'package:toolbox_core/toolbox_core.dart';

import 'context.dart';

// ───────────── 重启到各模式 ─────────────

Future<OperationResult> reboot(RebootTarget target, OpContext ctx) async {
  final d = await ctx.requireDevice();
  final serial = d.serial!;
  final name = target.label;
  ctx.step('正在重启到$name');

  if (d.mode == DeviceMode.fastboot) {
    final r = await ctx.fastboot.reboot(
        serial,
        switch (target) {
          RebootTarget.system => null,
          RebootTarget.recovery => 'recovery',
          RebootTarget.bootloader => 'bootloader',
          RebootTarget.edl => 'emergency',
        });
    if (target == RebootTarget.edl) ctx.log(LogLevel.warn, '大部分机型不支持从 Fastboot 进入 EDL，建议在开机状态使用');
    if (target == RebootTarget.recovery && !r.ok) {
      return const OperationResult.fail('该机型不支持从 Fastboot 直接进入 Recovery，可用音量键选择 Recovery mode 后按电源键');
    }
    return OperationResult(ok: r.ok, message: r.ok ? '已发送重启到$name的指令' : '指令执行失败');
  }

  final r = await ctx.adb.reboot(
      serial,
      switch (target) {
        RebootTarget.system => null,
        RebootTarget.recovery => 'recovery',
        RebootTarget.bootloader => 'bootloader',
        RebootTarget.edl => 'edl',
      });
  final tip = target == RebootTarget.edl ? '。退出 EDL：长按 音量上 + 电源键（老机型长按电源键）' : '';
  return OperationResult(ok: r.ok, message: r.ok ? '已发送重启到$name的指令$tip' : '指令执行失败');
}

// ───────────── 解锁 / 上锁 Bootloader ─────────────

Future<OperationResult> setLock(OpContext ctx, {required bool unlock}) async {
  final serial = await ctx.ensureFastboot();
  ctx.step('正在检测当前锁定状态');
  final state = await ctx.fastboot.isUnlocked(serial);
  if (state == unlock) {
    await ctx.fastboot.reboot(serial);
    return OperationResult(ok: true, message: unlock ? '设备已经解锁，无需重复操作（已重启）' : '设备已经上锁，无需重复操作（已重启）');
  }

  ctx.step(unlock ? '正在发送解锁指令' : '正在发送上锁指令');
  final r = await ctx.fastboot.setLock(serial, unlock: unlock);
  if (!r.ok) {
    await ctx.fastboot.reboot(serial);
    return OperationResult.fail(unlock ? '解锁失败：请在「开发者选项」中打开「OEM 解锁」；需要深度测试的机型须先通过深度测试申请' : '上锁失败：设备可能已上锁，或该机型不支持此指令');
  }
  final option = unlock ? 'UNLOCK THE BOOTLOADER' : 'LOCK THE BOOTLOADER';
  return OperationResult(ok: true, message: '最后一步：请在手机上用音量键选中「$option」，再按电源键确认。设备将清除全部数据并重启');
}

// ───────────── A/B 槽位切换 ─────────────

Future<OperationResult> switchSlot(OpContext ctx) async {
  final serial = await ctx.ensureFastboot();
  final before = await ctx.fastboot.getvar(serial, 'current-slot');
  if (before == null) return const OperationResult.fail('无法读取当前槽位，该设备可能不是 A/B 分区机型');
  ctx.step('当前为 ${before.toUpperCase()} 槽，正在切换');
  final r = await ctx.fastboot.setActiveOther(serial);
  final after = await ctx.fastboot.getvar(serial, 'current-slot');
  if (!r.ok || after == null || after == before) return const OperationResult.fail('槽位切换失败');
  ctx.device(await ctx.probe.describe(DeviceInfo(mode: DeviceMode.fastboot, serial: serial), ctx.cancel));
  return OperationResult(
    ok: true,
    message: '已从 ${before.toUpperCase()} 槽切换到 ${after.toUpperCase()} 槽，设备仍停留在 Fastboot，可在「重启」中开机',
  );
}
