/// 应用备份与恢复，对应 TS 版的 src/main/ops/appbackup.ts。
///
/// 备份目录是「<文档>\一加工具箱\应用备份\<应用名>_<版本>_<时间>\」：
/// 安装包从 `pm path` 拉回（有分包时打成 .apks，能直接用「安装应用」装回去）；
/// 勾选了同时备份数据时用 su 把 /data/data 和 /data/user_de/0 下的应用目录打成 tgz（不含缓存）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:toolbox_commands/toolbox_commands.dart';
import 'package:toolbox_core/toolbox_core.dart';

import '../environment.dart';
import 'context.dart';

/// `YYYYMMDDHHMMSS`，用作备份文件夹名的一部分（与 TS 版的 toISOString 前 14 位一致）
String appBackupStamp([DateTime? now]) =>
    (now ?? DateTime.now().toUtc()).toIso8601String().replaceAll(RegExp(r'[-:T]'), '').substring(0, 14);

/// `pm path` 的输出：每行 `package:<APK 路径>`，有分包时多行
List<String> parsePmPath(String out) => [
      for (final m in RegExp(r'^package:(/\S+\.apk)\s*$', multiLine: true).allMatches(out)) m[1]!,
    ];

/// 从 `dumpsys package <包名>` 里取版本
({String? versionName, String? versionCode}) parseVersion(String dumpsys) => (
      versionName: RegExp(r'^\s*versionName=(\S+)', multiLine: true).firstMatch(dumpsys)?[1],
      versionCode: RegExp(r'^\s*versionCode=(\d+)', multiLine: true).firstMatch(dumpsys)?[1],
    );

/// 用作 Windows 文件夹名
String safeAppName(String s) {
  final cleaned = s.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_').replaceAll(RegExp(r'^[._]+|[._]+$'), '');
  final sliced = cleaned.length > 60 ? cleaned.substring(0, 60) : cleaned;
  return sliced.isEmpty ? 'app' : sliced;
}

/// 备份文件夹里的 backup.json
class AppBackup {
  const AppBackup({
    required this.package,
    required this.label,
    required this.versionName,
    required this.versionCode,
    required this.apk,
    required this.data,
    required this.time,
    required this.model,
  });

  final String package;
  final String label;
  final String? versionName;
  final String? versionCode;

  /// 安装包文件名：app.apk 或 app.apks
  final String apk;

  /// 数据压缩包文件名（data.tgz / data_de.tgz）
  final List<String> data;
  final int time;
  final String? model;

  AppBackupManifest toManifest() => AppBackupManifest(
        package: package,
        label: label,
        versionName: versionName,
        versionCode: versionCode,
        apk: apk,
        data: data,
        time: time,
        model: model,
      );
}

/// 手机上的应用数据目录 → 备份文件夹里的压缩包名
String? dataFileOf(String root) {
  for (final d in dataRoots) {
    if (d.root == root) return d.file;
  }
  return null;
}

/// 应用数据的备份根目录，「<文档>\一加工具箱\应用备份」
String appBackupDir(ToolboxEnvironment env) {
  final dir = Directory(p.join(env.documentsDir, '一加工具箱', '应用备份'))..createSync(recursive: true);
  return dir.path;
}

/// 每次备份前清空的工作目录，避免上一次的残留混进这一次的产物
String appWorkDir(ToolboxEnvironment env) {
  final dir = Directory(p.join(env.tempDir, 'oneplus-toolbox', 'work'));
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  return dir.path;
}

/// 在 su 里跑脚本。拿到 Root 时脚本自己输出的标记才会出现；timeout 防止没人点授权时一直挂着
Future<ExecResult> _su(String serial, String script, OpContext ctx, int timeoutSec) => ctx.adb.shell(
      serial,
      ['timeout $timeoutSec su -c ${shq(script)} 2>&1'],
      timeout: Duration(seconds: timeoutSec + 15),
    );

/// 备份和恢复应用数据需要 Root，没拿到时直接拒绝（只备份安装包不需要）
Future<void> _requireRoot(String serial, OpContext ctx) async {
  final root = await ctx.probe.rootStatus(serial, ctx.cancel);
  if (!isRooted(root)) {
    throw OpException('备份和恢复应用数据需要 Root，这台手机当前是「${root ?? '未知'}」。不勾选「同时备份数据」可以只备份安装包');
  }
}

/// 备份一个应用到「文档\一加工具箱\应用备份\<应用名>_<版本>_<时间>\」
Future<OperationResult> backupApp(String pkg, String label, OpContext ctx, {required bool withData}) async {
  if (!isValidPackageName(pkg)) throw const OpException('包名不合法');
  final serial = await ctx.requireSystem();
  if (withData) await _requireRoot(serial, ctx);

  ctx.step('正在读取 $label 的安装包位置');
  final pathResult = await ctx.adb.shell(serial, ['pm', 'path', pkg], timeout: const Duration(seconds: 15));
  final paths = parsePmPath(pathResult.stdout);
  if (paths.isEmpty) throw OpException('手机上没有安装 $pkg');
  final version = parseVersion((await ctx.adb
          .shell(serial, ['dumpsys', 'package', pkg], timeout: const Duration(seconds: 30), echoOutput: false))
      .stdout);

  final tmp = appWorkDir(ctx.env);
  final apkDir = Directory(p.join(tmp, 'apk'))..createSync(recursive: true);
  for (var i = 0; i < paths.length; i++) {
    ctx.step('正在拉取安装包（${i + 1}/${paths.length}）');
    final r = await ctx.adb
        .pull(serial, paths[i], p.join(apkDir.path, p.basename(paths[i])), timeout: const Duration(minutes: 10));
    if (r.code != 0) throw OpException('拉取 ${p.basename(paths[i])} 失败，详见日志');
  }
  var apk = 'app.apk';
  if (paths.length > 1) {
    apk = 'app.apks';
    // -mx=1：背包只要装得回去，不必压到最小
    final z = await exec(
      ctx.tools.sevenZip,
      ['a', '-tzip', '-mx=1', p.join(tmp, apk), for (final path in paths) p.join(apkDir.path, p.basename(path))],
      cancel: ctx.cancel,
      log: ctx.log,
      timeout: const Duration(minutes: 10),
    );
    if (z.code != 0) throw const OpException('打包分包失败，详见日志');
  } else {
    File(p.join(apkDir.path, p.basename(paths.first))).copySync(p.join(tmp, apk));
  }

  final data = <String>[];
  if (withData) {
    await ctx.adb.shell(serial, ['mkdir', '-p', remoteDir]);
    ctx.step('正在停止 $label，避免备份到写了一半的数据');
    await ctx.adb.shell(serial, ['am', 'force-stop', pkg]);
    for (final d in dataRoots) {
      ctx.step('正在打包 ${d.root}/$pkg，手机上弹出 Root 授权时请点允许');
      final remote = '$remoteDir/${d.file}';
      final r = await _su(serial, dataBackupScript(root: d.root, pkg: pkg, remote: remote), ctx, 1800);
      if (r.stdout.contains(noDataDirMarker)) continue;
      if (!r.stdout.contains(tarOkMarker)) {
        throw OpException(
            r.stdout.contains('tar') ? '打包 ${d.root}/$pkg 失败，详见日志' : '没有拿到 Root 授权。请在 Root 管理器里允许 Shell 的超级用户权限后再试');
      }
      final pulled = await ctx.adb.pull(serial, remote, p.join(tmp, d.file), timeout: const Duration(minutes: 30));
      await ctx.adb.shell(serial, ['rm', '-f', remote]);
      if (pulled.code != 0) throw OpException('拉取 ${d.file} 失败，详见日志');
      data.add(d.file);
    }
    if (data.isEmpty) ctx.log(LogLevel.warn, '这个应用没有数据目录，只备份了安装包');
  }

  final props = await ctx.probe.getProps(serial, ctx.cancel);
  final manifest = AppBackup(
    package: pkg,
    label: label,
    versionName: version.versionName,
    versionCode: version.versionCode,
    apk: apk,
    data: data,
    time: DateTime.now().millisecondsSinceEpoch,
    model: props['ro.product.model'],
  );
  final dir = p.join(
    appBackupDir(ctx.env),
    '${safeAppName(label)}_${safeAppName(version.versionName ?? 'unknown')}_${appBackupStamp()}',
  );
  Directory(dir).createSync(recursive: true);
  for (final f in [apk, ...data]) {
    File(p.join(tmp, f)).copySync(p.join(dir, f));
  }
  File(p.join(dir, 'backup.json')).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(manifest.toManifest().toJson()),
  );
  final versionName = version.versionName;
  return OperationResult(
    ok: true,
    message: '已备份 $label${versionName != null ? ' $versionName' : ''}'
        '${data.isNotEmpty ? '（含应用数据）' : '（只有安装包）'}',
    outputPath: dir,
  );
}

/// 读备份文件夹里的 backup.json，校验里面记的安装包还在
AppBackup _readBackup(String dir, OpContext ctx) {
  AppBackupManifest manifest;
  try {
    manifest = AppBackupManifest.fromJson(
      Map<String, Object?>.from(jsonDecode(File(p.join(dir, 'backup.json')).readAsStringSync()) as Map),
    );
  } catch (_) {
    throw const OpException('这个文件夹里没有 backup.json，请选择工具箱备份出来的应用文件夹');
  }
  if (!isValidPackageName(manifest.package)) throw const OpException('backup.json 里的包名不合法');
  if ((manifest.apk != 'app.apk' && manifest.apk != 'app.apks') || !File(p.join(dir, manifest.apk)).existsSync()) {
    throw const OpException('备份文件夹里缺少安装包');
  }
  // 只认工具箱自己会生成的压缩包名，且文件确实还在
  final data = [
    for (final f in manifest.data)
      if (dataRoots.any((d) => d.file == f) && File(p.join(dir, f)).existsSync()) f,
  ];
  return AppBackup(
    package: manifest.package,
    label: manifest.label,
    versionName: manifest.versionName,
    versionCode: manifest.versionCode,
    apk: manifest.apk,
    data: data,
    time: manifest.time,
    model: manifest.model,
  );
}

/// 从分包里挑出要装的 APK：ABI 分包只留手机最优先支持的那一种，其余（base、语言、屏幕密度）全装。
/// bundletool 的 .apks 里 standalones/ 是给不支持分包的老系统用的整包，跳过。
/// [names] 为相对路径（/ 分隔），[abiList] 为 ro.product.cpu.abilist（逗号分隔）
List<String> pickSplits(List<String> names, String abiList) {
  final apks = [
    for (final n in names)
      if (RegExp(r'\.apk$', caseSensitive: false).hasMatch(n) &&
          !RegExp(r'^(standalones|instant)/', caseSensitive: false).hasMatch(n))
        n,
  ];
  final abis = [
    for (final a in abiList.split(','))
      if (a.trim().replaceAll('-', '_').toLowerCase() case final a when a.isNotEmpty) a,
  ];
  final abiPattern =
      RegExp(r'(?:^|[._-])(arm64_v8a|armeabi_v7a|armeabi|x86_64|x86|mips64|mips)\.apk$', caseSensitive: false);
  String? abiOf(String n) => abiPattern.firstMatch(n)?.group(1)?.toLowerCase();
  final present = <String>{
    for (final n in apks)
      if (abiOf(n) case final a?) a
  };
  final matchingAbis = abis.where(present.contains);
  final best = matchingAbis.isEmpty ? null : matchingAbis.first;
  return [
    for (final n in apks)
      if (abiOf(n) == null || abiOf(n) == best) n,
  ];
}

/// 递归列出目录里的文件名（相对该目录、用 / 分隔）
List<String> _listFiles(String dir) => [
      for (final e in Directory(dir).listSync(recursive: true))
        if (e is File) p.relative(e.path, from: dir).replaceAll(r'\', '/'),
    ];

/// 安装备份里的安装包：单个 APK 直接 `adb install`；
/// 有分包时先解开 .apks，用 `adb install-multiple` 装成一个应用
Future<bool> _installBackup(String serial, String dir, String apk, OpContext ctx) async {
  final file = p.join(dir, apk);
  if (apk != 'app.apks') {
    return ctx.adb.install(serial, file, timeout: const Duration(minutes: 5));
  }
  final out = Directory(p.join(appWorkDir(ctx.env), 'apks'))..createSync(recursive: true);
  final x = await ctx.sevenZip.extract(file, const [], out.path);
  if (x.code != 0) return false;
  final props = await ctx.probe.getProps(serial, ctx.cancel);
  final splits = pickSplits(_listFiles(out.path), props['ro.product.cpu.abilist'] ?? '');
  if (splits.isEmpty) return false;
  final r = await ctx.adb.run(
    serial,
    ['install-multiple', '-r', for (final s in splits) p.join(out.path, s)],
    timeout: const Duration(minutes: 10),
  );
  return r.ok && r.all.contains('Success');
}

/// 从备份文件夹恢复：先装安装包，备份里有数据、手机也已 Root 时，再把数据解回去，
/// 并把属主改成新装应用的 uid、恢复 SELinux 标签（换了手机或重装后 uid 会变）
Future<OperationResult> restoreApp(String dir, OpContext ctx) async {
  final m = _readBackup(dir, ctx);
  final name = '${m.label}${m.versionName != null ? ' ${m.versionName}' : ''}';
  final serial = await ctx.requireSystem();
  final rooted = m.data.isNotEmpty && isRooted(await ctx.probe.rootStatus(serial, ctx.cancel));

  final installed = await _installBackup(serial, dir, m.apk, ctx);
  if (!installed) {
    throw OpException('安装 $name 失败。手机上已有的版本更新、或签名不同时都装不上，可以先卸载手机上的再恢复');
  }
  if (m.data.isEmpty) return OperationResult(ok: true, message: '已安装 $name（备份里没有应用数据）');
  if (!rooted) return OperationResult(ok: true, message: '已安装 $name。手机没有 Root，应用数据没有恢复');

  await ctx.adb.shell(serial, ['mkdir', '-p', remoteDir]);
  ctx.step('正在停止 ${m.label}');
  await ctx.adb.shell(serial, ['am', 'force-stop', m.package]);
  for (final d in dataRoots.where((d) => m.data.contains(d.file))) {
    ctx.step('正在恢复 ${d.root}/${m.package}');
    final remote = '$remoteDir/${d.file}';
    final pushed = await ctx.adb.push(serial, p.join(dir, d.file), remote, timeout: const Duration(minutes: 30));
    if (pushed.code != 0) throw OpException('推送 ${d.file} 失败，详见日志');
    final list =
        await ctx.adb.shell(serial, listArchiveArgs(remote), timeout: const Duration(minutes: 5), echoOutput: false);
    if (list.code != 0 || !checkArchive(list.stdout, m.package)) {
      await ctx.adb.shell(serial, ['rm', '-f', remote]);
      throw OpException('${d.file} 里有不属于 ${m.package} 的文件，为了安全已停止');
    }
    // 先清掉现有数据（缓存和 lib 保留），解压后属主改成这台手机上新装应用的 uid
    final r = await _su(
      serial,
      dataRestoreScript(root: d.root, pkg: m.package, remote: remote),
      ctx,
      1800,
    );
    await ctx.adb.shell(serial, ['rm', '-f', remote]);
    if (r.stdout.contains(noDataDirMarker)) {
      ctx.log(LogLevel.warn, '手机上没有 ${d.root}/${m.package}，跳过');
      continue;
    }
    if (!r.stdout.contains(restoreOkMarker)) {
      throw OpException(r.stdout.contains('tar') ? '恢复 ${d.file} 失败，详见日志' : '没有拿到 Root 授权，应用已安装但数据没有恢复');
    }
  }
  return OperationResult(
    ok: true,
    message: '已恢复 $name 和它的数据。换了手机时，部分应用的登录状态可能失效，需要重新登录',
  );
}
