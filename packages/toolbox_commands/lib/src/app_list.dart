import 'dart:convert';
import 'dart:typed_data';

import 'adb.dart';
import 'apps_script.dart';
import 'patch_script.dart';

/// 手机上一个应用的原始信息
class RawApp {
  const RawApp({required this.package, required this.label, this.apkPath, this.iconPath});

  final String package;
  final String label;
  final String? apkPath;

  /// APK 内的图标位图路径（自适应图标是 XML，无法直接显示，不会出现在这里）
  final String? iconPath;
}

/// 一次应用列表读取的结果：应用本身，以及脚本额外输出的「标记 → 包名集合」
class AppListResult {
  const AppListResult(this.apps, this.marks);

  final List<RawApp> apps;

  /// 标记（CLONED / INSTALLED / DISABLED）→ 包名集合
  final Map<String, Set<String>> marks;

  /// 某个标记下的全部包名，没有该标记时为空集合
  Set<String> mark(String kind) => marks[kind] ?? const {};
}

/// 生成读取应用名和图标的手机端脚本。
///
/// [listCmd] 的输出是 `pm list packages [-s] [-3] [-u] -f` 的格式（`package:<APK 路径>=<包名>`），
/// 应用名用手机端的 aapt2 读取，整个循环在一次 adb shell 里完成，避免每个应用一次 adb 往返；
/// [extra] 追加在最后，用来输出 CLONED / INSTALLED / DISABLED 之类的标记行。
String appListScript(String listCmd, List<String> extra) {
  String field(String prefix) => '\$(echo "\$b" | grep "^$prefix:" | head -n 1 | sed "s/^[^:]*:\'\\(.*\\)\'\$/\\1/")';
  // 每个应用一个子 shell，8 个一批并行跑 aapt2（串行时 200 个应用要两分多钟）。
  // 图标路径也来自同一次 badging 输出，不增加耗时；只取位图（自适应图标是 XML，无法直接显示）
  return [
    'A=$remoteDir/aapt2',
    r'chmod 755 $A',
    'i=0',
    'for e in \$($listCmd | sed "s/^package://"); do',
    // APK 路径里可能有 =（base64 目录名），包名里没有，所以按最后一个 = 切
    r'  p=${e##*=}; path=${e%=*}',
    '  (',
    r'    b=$($A d badging "$path" 2>/dev/null | grep -E "^application-(label(-zh-CN)?|icon-(160|240|320|480)):")',
    '    l=${field('application-label-zh-CN')}',
    '    [ -z "\$l" ] && l=${field('application-label')}',
    '    ic=""',
    '    for d in 240 320 160 480; do',
    '      c=${field(r'application-icon-$d')}',
    r'      case "$c" in *.png|*.webp|*.jpg) ic=$c; break;; esac',
    '    done',
    r'    echo "APP|$p|$path|$ic|$l"',
    '  ) &',
    r'  i=$((i + 1)); [ $((i % 8)) -eq 0 ] && wait',
    'done',
    'wait',
    ...extra,
  ].join('\n');
}

/// 解析 [appListScript] 的输出。标记行形如 `CLONED|包名`，应用行形如 `APP|包名|APK 路径|图标路径|应用名`
AppListResult parseAppListing(String out) {
  final apps = <RawApp>[];
  final marks = <String, Set<String>>{};
  for (final line in const LineSplitter().convert(out)) {
    final parts = line.split('|');
    if (parts.length < 2) continue;
    final kind = parts[0].trim();
    final pkg = parts[1].trim();
    if (kind.isEmpty || pkg.isEmpty) continue;
    if (kind == 'APP') {
      if (parts.length < 5) continue;
      final apk = parts[2].trim();
      final icon = parts[3].trim();
      final label = parts.sublist(4).join('|').trim();
      apps.add(RawApp(
        package: pkg,
        label: label.isEmpty ? pkg : label,
        apkPath: apk.isEmpty ? null : apk,
        iconPath: icon.isEmpty ? null : icon,
      ));
      continue;
    }
    (marks[kind] ??= <String>{}).add(pkg);
  }
  return AppListResult(apps, marks);
}

/// 跑一次应用列表脚本：把 aapt2 推到手机上，再执行 [script]。
///
/// 应用较多时要一两分钟，也可能更久，所以超时给得比较宽。
Future<AppListResult> runAppListScript(
  Adb adb,
  String serial,
  String aapt2Local,
  String script, {
  Duration timeout = const Duration(minutes: 10),
}) async {
  await adb.shell(serial, ['mkdir', '-p', remoteDir]);
  await adb.push(serial, aapt2Local, '$remoteDir/aapt2', timeout: const Duration(seconds: 60));
  final r = await adb.shell(serial, [script], timeout: timeout, echoOutput: false);
  return parseAppListing(r.stdout);
}

/// 列出第三方应用及其中文名，并标出已在双开空间（[cloneUser]）中的应用
Future<AppListResult> readThirdPartyApps(Adb adb, String serial,
        {required String aapt2Local, required String cloneUser}) =>
    runAppListScript(
        adb, serial, aapt2Local, appListScript('pm list packages -3 -f', listClonedPackagesScript(cloneUser)));

/// 列出预装应用（含已对当前用户卸载的）：`pm list packages -s -u -f`，
/// 再对照 `--user 0` 的已安装 / 已停用列表
Future<AppListResult> readSystemApps(Adb adb, String serial, {required String aapt2Local}) => runAppListScript(
      adb,
      serial,
      aapt2Local,
      appListScript('pm list packages -s -u -f', [
        ...listInstalledSystemPackagesScript(),
        ...listDisabledSystemPackagesScript(),
      ]),
    );

/// 列出第三方应用并标出已冻结（停用）的
Future<AppListResult> readUserApps(Adb adb, String serial, {required String aapt2Local}) => runAppListScript(
      adb,
      serial,
      aapt2Local,
      appListScript('pm list packages -3 -f', listDisabledUserPackagesScript()),
    );

/// 一次 adb shell 从多个 APK 中解出图标位图。返回 包名 → 图片字节；失败的条目直接缺省。
Future<Map<String, Uint8List>> readIcons(
    Adb adb, String serial, Map<String, ({String apk, String icon})> sources) async {
  if (sources.isEmpty) return {};
  final script = sources.entries
      .map(
          (e) => 'echo "ICON|${e.key}|\$(unzip -p ${shq(e.value.apk)} ${shq(e.value.icon)} 2>/dev/null | base64 -w 0)"')
      .join('\n');
  final r = await adb.shell(serial, [script], echoOutput: false);
  final icons = <String, Uint8List>{};
  for (final line in const LineSplitter().convert(r.stdout)) {
    final parts = line.split('|');
    if (parts.length != 3 || parts[0] != 'ICON' || !sources.containsKey(parts[1])) continue;
    final b64 = parts[2].trim();
    if (b64.isEmpty) continue;
    try {
      icons[parts[1]] = base64Decode(b64);
    } on FormatException {
      // 截断的输出，跳过
    }
  }
  return icons;
}
