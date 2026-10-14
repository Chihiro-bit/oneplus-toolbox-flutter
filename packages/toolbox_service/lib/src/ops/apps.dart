import 'dart:typed_data';

import 'package:toolbox_commands/toolbox_commands.dart';
import 'package:toolbox_core/toolbox_core.dart';

import 'context.dart';

/// ColorOS / 氧 OS 的分身空间固定是用户 999
const cloneUser = '999';

// ───────────── 应用双开 ─────────────

/// 应用图标：列表先出来，图标在后台分批补全
class AppIconLoader {
  /// 最近一次读取应用列表得到的图标位置
  final _sources = <String, ({String serial, String apk, String icon})>{};

  /// 已取回的图标，按「APK 路径 + 图标路径」缓存；应用更新后 APK 路径会变，自然失效
  final _cache = <String, Uint8List>{};

  static const _batchSize = 20;

  void _reset(String serial, Iterable<RawApp> apps) {
    _sources.clear();
    for (final a in apps) {
      if (a.apkPath != null && a.iconPath != null) {
        _sources[a.package] = (serial: serial, apk: a.apkPath!, icon: a.iconPath!);
      }
    }
  }

  /// 从各 APK 中解出图标位图，分批回传。独立于操作队列运行，失败只会少几个图标。200 个应用约 5 秒。
  Future<void> load(String adbExe, void Function(Map<String, Uint8List>) onBatch) async {
    final pending = <MapEntry<String, ({String serial, String apk, String icon})>>[];
    final hits = <String, Uint8List>{};
    for (final e in _sources.entries) {
      final hit = _cache['${e.value.apk}|${e.value.icon}'];
      if (hit != null) {
        hits[e.key] = hit;
      } else {
        pending.add(e);
      }
    }
    if (hits.isNotEmpty) onBatch(hits);

    final adb = Adb(adbExe);
    for (var i = 0; i < pending.length; i += _batchSize) {
      final batch = pending.skip(i).take(_batchSize).toList();
      final icons = await readIcons(adb, batch.first.value.serial, {
        for (final e in batch) e.key: (apk: e.value.apk, icon: e.value.icon),
      });
      for (final e in icons.entries) {
        final src = _sources[e.key]!;
        _cache['${src.apk}|${src.icon}'] = e.value;
      }
      if (icons.isNotEmpty) onBatch(icons);
    }
  }
}

/// 列出第三方应用及其中文名，并标出已在双开空间（用户 999）中的应用
Future<OperationResult> listApps(OpContext ctx, AppIconLoader icons) async {
  final serial = await ctx.requireSystem();
  ctx.step('正在检查双开空间');
  final users = await ctx.adb.shell(serial, ['pm', 'list', 'users']);
  if (!users.stdout.contains('UserInfo{$cloneUser:')) {
    throw const OpException('手机上还没有双开空间。请先在系统「设置 → 应用 → 应用分身」中任意双开一个应用，再回来刷新');
  }

  ctx.step('正在读取应用列表，应用较多时需要一分钟左右');
  final listing = await listThirdPartyApps(ctx.adb, serial, aapt2Local: ctx.tools.aapt2, cloneUser: cloneUser);
  icons._reset(serial, listing.apps);

  final apps = [
    for (final a in listing.apps)
      AppEntry(package: a.package, label: a.label, cloned: listing.clonedPackages.contains(a.package))
  ]..sort((a, b) {
      if (a.cloned != b.cloned) return a.cloned ? -1 : 1;
      return a.label.compareTo(b.label);
    });
  final clonedCount = apps.where((a) => a.cloned).length;
  return OperationResult(ok: true, message: '共 ${apps.length} 个应用，其中 $clonedCount 个已双开', apps: apps);
}

Future<OperationResult> cloneApp(String pkg, OpContext ctx, {required bool enable}) async {
  if (!isValidPackageName(pkg)) throw const OpException('包名不合法');
  final serial = await ctx.requireSystem();
  ctx.step(enable ? '正在双开 $pkg' : '正在移除 $pkg 的双开');
  final r = await ctx.adb.shell(serial, ['pm', enable ? 'install-existing' : 'uninstall', '--user', cloneUser, pkg]);
  final ok = r.ok && RegExp('installed|Success', caseSensitive: false).hasMatch(r.all);
  if (!ok) return OperationResult.fail(enable ? '双开失败，该应用可能不支持分身' : '移除双开失败');
  return OperationResult(
    ok: true,
    message: enable ? '双开成功。注意：ColorOS 桌面重启后可能不显示分身图标，可改用第三方桌面' : '已移除该应用的双开',
  );
}

// ───────────── 安装 Play 商店 ─────────────

Future<OperationResult> installPlay(String apk, OpContext ctx) async {
  final serial = await ctx.requireSystem();
  ctx.step('正在卸载系统内置 Play 商店的更新');
  await ctx.adb.shell(serial, ['pm', 'uninstall', 'com.android.vending']);
  ctx.step('正在安装 Play 商店');
  final installed = await ctx.adb.install(serial, apk, allowDowngrade: true, timeout: const Duration(minutes: 5));
  if (!installed) return const OperationResult.fail('Play 商店安装失败，详见日志');
  // 通过应用商店的详情页触发 Play 商店自身更新
  for (final uri in [
    'oppomarket://details?packagename=com.android.vending',
    'market://details?id=com.android.vending'
  ]) {
    await ctx.adb.shell(serial, ['am', 'start', '-a', 'android.intent.action.VIEW', '-d', shq(uri)]);
  }
  return const OperationResult(ok: true, message: 'Play 商店已安装。如果手机上弹出了更新提示，请点击「更新」');
}

// ───────────── 禁用 / 恢复系统更新 ─────────────

const _otaPackages = ['com.oneplus.opbackup', 'com.oppo.ota', 'com.oplus.ota', 'com.oplus.romupdate'];
const _suspendPackages = ['com.oplus.ota', 'com.oplus.romupdate'];
const _playUpdateActivity = 'com.android.vending/com.google.android.finsky.systemupdateactivity.SystemUpdateActivity';

Future<OperationResult> otaUpdates(OpContext ctx, {required bool disable}) async {
  final serial = await ctx.requireSystem();
  Future<void> sh(List<String> args) => ctx.adb.shell(serial, args, timeout: const Duration(seconds: 30));
  if (disable) {
    ctx.step('正在禁用系统更新');
    await sh(['settings', 'put', 'system', 'strong_prompt_ota', '0']);
    await sh(['settings', 'put', 'system', 'has_new_version_to_update', '0']);
    // 先 suspend 再卸载：卸载之后 suspend 会失败
    for (final p in _suspendPackages) {
      await sh(['pm', 'suspend', p]);
    }
    for (final p in _otaPackages) {
      await sh(['pm', 'uninstall', '--user', '0', p]);
    }
    await sh(['pm', 'disable', _playUpdateActivity]);
    return const OperationResult(ok: true, message: '系统更新已禁用。需要恢复时，回到这里点击「恢复系统更新」');
  }
  ctx.step('正在恢复系统更新');
  for (final p in _otaPackages) {
    await sh(['pm', 'install-existing', p]);
  }
  for (final p in _suspendPackages) {
    await sh(['pm', 'unsuspend', p]);
  }
  await sh(['pm', 'enable', _playUpdateActivity]);
  return const OperationResult(ok: true, message: '系统更新已恢复');
}
