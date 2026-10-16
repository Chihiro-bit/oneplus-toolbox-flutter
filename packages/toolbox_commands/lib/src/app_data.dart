/// 应用数据打包 / 解包的手机端脚本。
///
/// 这两段脚本都在 `su -c` 里跑（见 toolbox_service 的 ops/appbackup.dart），
/// 通过 echo 出来的标记判断结果：NO_DIR / TAR_OK / RESTORE_OK。
/// 对应 TS 版的 src/main/ops/appbackup.ts。
library;

/// 应用数据所在的两个目录：凭据加密（解锁后才能读）和设备加密（开机就能读，闹钟等应用用）
const dataRoots = <({String file, String root})>[
  (file: 'data.tgz', root: '/data/data'),
  (file: 'data_de.tgz', root: '/data/user_de/0'),
];

/// 缓存不备份；lib 在老系统上是指向 /data/app 的链接，也不备份。恢复时这几项原样保留
const skipDataDirs = ['cache', 'code_cache', 'lib'];

/// 打包失败 / 没有数据目录 / 解包成功的标记
const noDataDirMarker = 'NO_DIR';
const tarOkMarker = 'TAR_OK';
const restoreOkMarker = 'RESTORE_OK';

/// `tar -czf <远端文件>` 的排除参数：`--exclude=<包名>/cache --exclude=…`
String dataExcludeArgs(String pkg) => [
      for (final d in skipDataDirs) '--exclude=$pkg/$d',
    ].join(' ');

/// `find … -exec rm -rf {} +` 的保留参数：`! -name cache ! -name code_cache ! -name lib`
String dataKeepArgs() => [
      for (final d in skipDataDirs) '! -name $d',
    ].join(' ');

/// 在 su 里把 `<root>/<包名>` 打成 tgz 放到手机上。没有该目录时输出 [noDataDirMarker]，
/// 成功时输出 [tarOkMarker]；chmod 644 是为了让 shell 用户能把它 pull 回来。
String dataBackupScript({required String root, required String pkg, required String remote}) =>
    '[ -d $root/$pkg ] || { echo $noDataDirMarker; exit 0; }; '
    'cd $root && tar -czf $remote ${dataExcludeArgs(pkg)} $pkg && chmod 644 $remote && echo $tarOkMarker';

/// 在 su 里把 tgz 解回 `<root>/<包名>`：[remote] 已经推送到手机上。
///
/// 先清掉现有数据（缓存和 lib 保留），解压后把属主改成这台手机上新装应用的 uid、
/// 恢复 SELinux 标签。调用前必须用 `tar -tzf` 校验过压缩包内容。
List<String> dataRestoreScriptLines({required String root, required String pkg, required String remote}) {
  final dir = '$root/$pkg';
  return [
    '[ -d $dir ] || { echo $noDataDirMarker; exit 0; }',
    'U=\$(stat -c %u $dir)',
    'find $dir -mindepth 1 -maxdepth 1 ${dataKeepArgs()} -exec rm -rf {} +',
    'tar -xzf $remote -C $root || exit 1',
    'chown -R \$U:\$U $dir',
    'restorecon -RF $dir',
    'echo $restoreOkMarker',
  ];
}

/// [dataRestoreScriptLines] 拼成一段脚本
String dataRestoreScript({required String root, required String pkg, required String remote}) =>
    dataRestoreScriptLines(root: root, pkg: pkg, remote: remote).join('\n');

/// 列出 tgz 里的每一项：`tar -tzf <远端文件>`，恢复前用它校验压缩包内容
List<String> listArchiveArgs(String remote) => ['tar', '-tzf', remote];

/// 校验 `tar -tzf` 的输出：每一项都必须在 `<包名>/` 下、不含 ..，
/// 防止拿别人的压缩包以 Root 身份把文件解到别的应用或系统目录里
bool checkArchive(String list, String pkg) {
  final entries = [
    for (final l in list.split(RegExp(r'\r?\n')))
      if (l.trim().isNotEmpty) l.trim(),
  ];
  return entries.isNotEmpty &&
      entries.every((e) => (e == pkg || e == '$pkg/' || e.startsWith('$pkg/')) && !e.split('/').contains('..'));
}
