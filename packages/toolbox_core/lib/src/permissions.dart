/// 可以用 adb 的 `pm grant` 授予的权限：保护级别带 development 标记，普通应用申请了也拿不到，
/// 只能由用户手动敲命令授予。只有应用在清单里申请了的才能授予，否则 pm grant 会报错。
///
/// 对应 TS 版的 src/shared/permissions.ts。
library;

class GrantablePermission {
  const GrantablePermission(this.label, this.desc);

  final String label;
  final String desc;
}

const grantablePermissions = <String, GrantablePermission>{
  'android.permission.WRITE_SECURE_SETTINGS': GrantablePermission(
    '修改安全系统设置',
    '自动化（Tasker、MacroDroid）、按键映射、手势、SystemUI Tuner 等切换系统开关时需要',
  ),
  'android.permission.DUMP': GrantablePermission('读取系统状态（dumpsys）', '电池、性能监控类应用需要'),
  'android.permission.READ_LOGS': GrantablePermission('读取系统日志', '日志查看器、部分自动化应用需要'),
  'android.permission.PACKAGE_USAGE_STATS': GrantablePermission(
    '读取应用使用情况',
    '使用时长统计、按前台应用触发的自动化需要',
  ),
  'android.permission.BATTERY_STATS': GrantablePermission('读取电池统计', '耗电分析类应用需要'),
  'android.permission.SET_ANIMATION_SCALE': GrantablePermission('修改动画速度', '调节系统动画倍率的应用需要'),
  'android.permission.CHANGE_CONFIGURATION': GrantablePermission('修改系统配置', '切换语言、字体缩放等的应用需要'),
};

bool isGrantable(String permission) => grantablePermissions.containsKey(permission);

class PackagePermissions {
  const PackagePermissions({required this.requested, required this.granted});

  final List<String> requested;
  final Set<String> granted;
}

final _grantedLine = RegExp(r'^([\w.]+): granted=true');
final _userId = RegExp(r'userId=(\d+)');

/// 解析 `dumpsys package <包名>`：requested permissions 段列出申请的权限，
/// install / runtime permissions 段里 `权限: granted=true` 表示已授予。
PackagePermissions parsePackagePermissions(String out) {
  final requested = <String>[];
  final granted = <String>{};
  var indent = -1;
  for (final line in out.split(RegExp(r'\r?\n'))) {
    final depth = line.length - line.trimLeft().length;
    final text = line.trim();
    if (text == 'requested permissions:') {
      indent = depth;
      continue;
    }
    if (indent >= 0) {
      if (text.isNotEmpty && depth > indent) {
        final name = text.split(RegExp(r'[:,\s]')).first;
        if (!requested.contains(name)) requested.add(name);
        continue;
      }
      indent = -1;
    }
    // 开发者权限记在 install permissions 段，有多个用户时其它用户另起一行并带 userId=N，只看用户 0
    final m = _grantedLine.firstMatch(text);
    final user = _userId.firstMatch(text)?.group(1);
    if (m != null && (user == null || user == '0')) granted.add(m.group(1)!);
  }
  return PackagePermissions(requested: requested, granted: granted);
}
