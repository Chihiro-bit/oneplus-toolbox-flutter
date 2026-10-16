/// 应用权限，对应 TS 版的 src/main/ops/permissions.ts。
///
/// 只列出应用申请了、可以用 adb 授予的权限（[grantablePermissions]），
/// 悬浮窗、无障碍、通知使用权这些只能在手机设置里打开，工具箱不管。
library;

import 'package:toolbox_commands/toolbox_commands.dart';
import 'package:toolbox_core/toolbox_core.dart';

import 'context.dart';

/// 读应用申请的权限和已授予的权限
Future<List<AppPermission>> _readPermissions(String serial, String pkg, OpContext ctx) async {
  final r =
      await ctx.adb.shell(serial, appPermissionsArgs(pkg), timeout: const Duration(seconds: 30), echoOutput: false);
  if (!r.stdout.contains('Package [$pkg]')) throw OpException('手机上没有安装 $pkg');
  final parsed = parsePackagePermissions(r.stdout);
  return [
    for (final name in parsed.requested)
      if (grantablePermissions[name] case final p?)
        AppPermission(name: name, label: p.label, desc: p.desc, granted: parsed.granted.contains(name)),
  ];
}

/// 列出应用申请了、可以用 adb 授予的权限，以及是否已授予
Future<OperationResult> appPermissions(String pkg, OpContext ctx) async {
  if (!isValidPackageName(pkg)) throw const OpException('包名不合法');
  final serial = await ctx.requireSystem();
  ctx.step('正在读取 $pkg 申请的权限');
  final permissions = await _readPermissions(serial, pkg, ctx);
  return OperationResult(
    ok: true,
    message: permissions.isNotEmpty ? '$pkg 有 ${permissions.length} 项权限可以用 adb 授予' : '$pkg 没有申请需要用 adb 授予的权限',
    permissions: permissions,
  );
}

/// pm grant / pm revoke，完成后重新读一遍确认
Future<OperationResult> grantPermission(String pkg, String permission, OpContext ctx, {required bool grant}) async {
  if (!isValidPackageName(pkg)) throw const OpException('包名不合法');
  final info = grantablePermissions[permission];
  if (info == null) throw OpException('工具箱不支持授予 $permission');
  final serial = await ctx.requireSystem();
  final label = info.label;
  ctx.step(grant ? '正在授予「$label」' : '正在撤销「$label」');
  await ctx.adb.shell(serial, grantPermissionArgs(pkg, permission, grant: grant));
  final permissions = await _readPermissions(serial, pkg, ctx);
  final matches = permissions.where((p) => p.name == permission);
  final now = matches.isEmpty ? null : matches.first.granted;
  if (now != grant) {
    return OperationResult(
      ok: false,
      message: '${grant ? '授予' : '撤销'}「$label」失败，详见日志',
      permissions: permissions,
    );
  }
  return OperationResult(
    ok: true,
    message: grant ? '已授予「$label」。应用正在运行的话，可能需要重新打开才能生效' : '已撤销「$label」',
    permissions: permissions,
  );
}
