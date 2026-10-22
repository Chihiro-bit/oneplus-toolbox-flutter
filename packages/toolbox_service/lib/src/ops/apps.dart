import 'dart:typed_data';

import 'package:toolbox_commands/toolbox_commands.dart';
import 'package:toolbox_commands/toolbox_commands.dart' as apps_script;
import 'package:toolbox_core/toolbox_core.dart';

import 'context.dart';

/// ColorOS / 氧 OS 的分身空间固定是用户 999
const cloneUser = '999';

// ───────────── 应用双开 ─────────────

/// 卸了会导致无法开机、无法解锁屏幕或无法再用 adb 恢复的系统组件，工具箱直接拒绝。
/// 这不是「可以随便卸」的白名单：不在这里的应用也可能有依赖，卸之前请确认用途。
const protectedPackages = <String>{
  'android',
  'com.android.systemui',
  'com.android.settings',
  'com.android.phone',
  'com.android.shell',
  'com.android.packageinstaller',
  'com.android.permissioncontroller',
  'com.google.android.permissioncontroller',
  'com.android.providers.settings',
  'com.android.providers.telephony',
  'com.android.providers.media',
  'com.android.providers.contacts',
  'com.android.providers.downloads',
  'com.android.inputmethod.latin',
  'com.android.keychain',
  'com.android.location.fused',
  'com.android.server.telecom',
  'com.android.networkstack',
  'com.google.android.networkstack',
  'com.android.externalstorage',
  // 桌面：卸了开机后没有主屏幕（ColorOS / 氧 OS 的桌面包名是 com.android.launcher）
  'com.android.launcher',
  'com.android.launcher3',
  // ColorOS 的权限管理
  'com.oplus.securitypermission',
};

/// 应用图标：列表先出来，图标在后台分批补全
class AppIconLoader {
  /// 最近一次读取应用列表得到的图标位置
  final _sources = <String, ({String serial, String apk, String icon})>{};

  /// 已取回的图标，按「APK 路径 + 图标路径」缓存；应用更新后 APK 路径会变，自然失效
  final _cache = <String, Uint8List>{};

  /// 一批取多少个图标，一次 adb shell 搞定
  static const _batchSize = 20;

  /// 记下这次列表里各应用的图标位置。APK 路径直接来自 `pm list packages -f`，不用再跑一次 `pm path`
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
  final listing = await readThirdPartyApps(ctx.adb, serial, aapt2Local: ctx.tools.aapt2, cloneUser: cloneUser);
  icons._reset(serial, listing.apps);

  final cloned = listing.mark(clonedMark);
  final apps = [
    for (final a in listing.apps) AppEntry(package: a.package, label: a.label, cloned: cloned.contains(a.package))
  ]..sort((a, b) {
      if (a.cloned != b.cloned) return a.cloned ? -1 : 1;
      return a.label.compareTo(b.label);
    });
  return OperationResult(ok: true, message: '共 ${apps.length} 个应用，其中 ${cloned.length} 个已双开', apps: apps);
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

// ───────────── 预装应用精简 ─────────────

/// 列出系统预装应用，标出已对当前用户卸载（pm uninstall --user 0）的
Future<OperationResult> listSystemApps(OpContext ctx) async {
  final serial = await ctx.requireSystem();
  ctx.step('正在读取系统应用列表，数量较多，需要一两分钟');
  // -u 连已对当前用户卸载的也列出来，再对照 --user 0 的已安装列表
  final listing = await readSystemApps(ctx.adb, serial, aapt2Local: ctx.tools.aapt2);
  final installed = listing.mark(installedMark);
  final disabled = listing.mark(disabledMark);
  final apps = [
    for (final a in listing.apps)
      AppEntry(
        package: a.package,
        label: a.label,
        system: true,
        removed: !installed.contains(a.package),
        disabled: disabled.contains(a.package),
        protected: protectedPackages.contains(a.package),
      )
  ]..sort((a, b) {
      if (a.removed != b.removed) return a.removed ? -1 : 1;
      return a.label.compareTo(b.label);
    });
  final removed = apps.where((a) => a.removed).length;
  return OperationResult(ok: true, message: '共 ${apps.length} 个系统应用，其中 $removed 个已卸载', apps: apps);
}

/// remove：pm uninstall --user 0，只对当前用户卸载，系统分区里的 APK 还在；
/// restore：pm install-existing 恢复。恢复出厂设置也会让所有被卸载的预装应用回来
Future<OperationResult> debloat(String pkg, OpContext ctx, {required bool remove, bool root = false}) async {
  if (!isValidPackageName(pkg)) throw const OpException('包名不合法');
  if (root && !remove) throw const OpException('Root 强制卸载仅用于卸载操作');
  if (remove && protectedPackages.contains(pkg)) {
    throw OpException('$pkg 是系统运行必需的组件，卸载后可能无法开机或无法恢复，工具箱不允许卸载');
  }
  final serial = await ctx.requireSystem();
  if (root) {
    ctx.step('正在请求 Root 权限，请在手机上允许授权');
    final id = await ctx.adb.shell(serial, ["timeout 30 su -c 'id -u' 2>&1"], timeout: const Duration(seconds: 45));
    if (!id.ok || !id.stdout.split(RegExp(r'\r?\n')).any((line) => line.trim() == '0')) {
      throw const OpException('未获得 Root 权限，请确认手机已 Root 并允许工具箱的 Shell 授权');
    }
  }
  ctx.step(remove ? '正在卸载 $pkg' : '正在恢复 $pkg');
  final r = await ctx.adb.shell(
      serial,
      root
          ? ['timeout 30 su -c \'pm uninstall -k --user 0 $pkg\' 2>&1']
          : remove
              ? apps_script.debloatRemoveArgs(pkg)
              : apps_script.debloatRestoreArgs(pkg),
      timeout: const Duration(seconds: 45));
  final ok = r.ok && RegExp('Success|installed for user', caseSensitive: false).hasMatch(r.all);
  if (!ok) {
    return OperationResult.fail(
        remove ? '${root ? 'Root 强制' : ''}卸载 $pkg 失败，${root ? '系统仍拒绝卸载该应用，' : ''}详见日志' : '恢复 $pkg 失败，详见日志');
  }
  return OperationResult(ok: true, message: remove ? '已卸载 $pkg（只对当前用户，可以随时恢复）' : '已恢复 $pkg');
}

// ───────────── 冻结应用 ─────────────

/// 列出第三方应用，标出已冻结（停用）的
Future<OperationResult> listUserApps(OpContext ctx) async {
  final serial = await ctx.requireSystem();
  ctx.step('正在读取应用列表，应用较多时需要一分钟左右');
  final listing = await readUserApps(ctx.adb, serial, aapt2Local: ctx.tools.aapt2);
  final disabled = listing.mark(disabledMark);
  final apps = [
    for (final a in listing.apps) AppEntry(package: a.package, label: a.label, disabled: disabled.contains(a.package))
  ]..sort((a, b) {
      if (a.disabled != b.disabled) return a.disabled ? -1 : 1;
      return a.label.compareTo(b.label);
    });
  return OperationResult(ok: true, message: '共 ${apps.length} 个应用，其中 ${disabled.length} 个已冻结', apps: apps);
}

/// 冻结 = pm disable-user：应用和数据都还在，只是不能运行、图标从桌面消失；解冻 = pm enable。
/// 比卸载温和，适合偶尔才用、又爱在后台跑的应用。当前的桌面和输入法不允许冻结，否则手机可能没法操作
Future<OperationResult> freezeApp(String pkg, OpContext ctx, {required bool freeze}) async {
  if (!isValidPackageName(pkg)) throw const OpException('包名不合法');
  if (freeze && protectedPackages.contains(pkg)) {
    throw OpException('$pkg 是系统运行必需的组件，工具箱不允许冻结');
  }
  final serial = await ctx.requireSystem();
  if (freeze) {
    final ime = await ctx.adb.shell(
      serial,
      apps_script.defaultInputMethodArgs(),
      timeout: const Duration(seconds: 15),
      echoOutput: false,
    );
    if (apps_script.componentPackage(ime.stdout) == pkg) {
      throw const OpException('这是当前正在使用的输入法，冻结后可能没法输入锁屏密码。请先换一个输入法');
    }
    final home = await ctx.adb.shell(
      serial,
      apps_script.homeActivityArgs(),
      timeout: const Duration(seconds: 15),
      echoOutput: false,
    );
    if (apps_script.resolvedActivityPackage(home.stdout) == pkg) {
      throw const OpException('这是当前的桌面，冻结后会没有主屏幕。请先换一个默认桌面');
    }
  }
  ctx.step(freeze ? '正在冻结 $pkg' : '正在解冻 $pkg');
  final r = await ctx.adb.shell(serial, freeze ? apps_script.freezeAppArgs(pkg) : apps_script.unfreezeAppArgs(pkg));
  final ok = freeze
      ? RegExp('new state: disabled', caseSensitive: false).hasMatch(r.all)
      : RegExp('new state: (enabled|default)', caseSensitive: false).hasMatch(r.all);
  if (!ok) return OperationResult.fail(freeze ? '冻结 $pkg 失败，详见日志' : '解冻 $pkg 失败，详见日志');
  return OperationResult(ok: true, message: freeze ? '已冻结 $pkg，需要时在这里解冻即可' : '已解冻 $pkg');
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
