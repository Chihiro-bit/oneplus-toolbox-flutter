import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// .apk / .apks / .xapk 的解析与 `adb install-multiple` 参数。
///
/// 对应 TS 版 src/main/ops/install.ts 里与文件有关的部分。

/// 可以安装的包格式
const installExtensions = ['apk', 'apks', 'xapk'];

/// 文件名后缀能不能装（界面用它决定要不要接受拖进来的文件）
bool isInstallable(String path) => installExtensions.contains(p.extension(path).replaceFirst('.', '').toLowerCase());

final _abiSplit =
    RegExp(r'(?:^|[._-])(arm64_v8a|armeabi_v7a|armeabi|x86_64|x86|mips64|mips)\.apk$', caseSensitive: false);
final _standaloneSplit = RegExp(r'^(standalones|instant)/', caseSensitive: false);
final _apkFile = RegExp(r'\.apk$', caseSensitive: false);

/// 从分包里挑出要装的 APK：ABI 分包只留手机最优先支持的那一种，其余（base、语言、屏幕密度）全装。
/// bundletool 的 .apks 里 standalones/ 是给不支持分包的老系统用的整包，跳过。
/// [names] 为相对路径（/ 分隔），[abiList] 为 ro.product.cpu.abilist（逗号分隔）。
List<String> pickSplits(List<String> names, String abiList) {
  final apks = <String>[];
  for (final n in names) {
    if (_apkFile.hasMatch(n) && !_standaloneSplit.hasMatch(n)) apks.add(n);
  }
  final present = <String>{};
  for (final n in apks) {
    final abi = _abiSplit.firstMatch(n)?.group(1)?.toLowerCase();
    if (abi != null) present.add(abi);
  }
  String? best;
  for (final raw in abiList.split(',')) {
    final abi = raw.trim().replaceAll('-', '_').toLowerCase();
    if (abi.isEmpty) continue;
    if (present.contains(abi)) {
      best = abi;
      break;
    }
  }
  final out = <String>[];
  for (final n in apks) {
    final abi = _abiSplit.firstMatch(n)?.group(1)?.toLowerCase();
    if (abi == null || abi == best) out.add(n);
  }
  return out;
}

/// 递归列出目录下所有文件，返回相对 [root] 的路径（/ 分隔）
List<String> listFiles(String dir, [String? root]) {
  final base = root ?? dir;
  final out = <String>[];
  for (final e in Directory(dir).listSync()) {
    if (e is Directory) {
      out.addAll(listFiles(e.path, base));
    } else if (e is File) {
      out.add(p.relative(e.path, from: base).replaceAll(r'\', '/'));
    }
  }
  return out;
}

final _failure = RegExp(r'Failure \[[^\]]*\]');

/// 失败原因只取 Failure [...] 那一行，取不到时用最后一行
String failureReason(String out) {
  final found = _failure.firstMatch(out);
  if (found != null) return found.group(0)!;
  final lines = out.trim().split(RegExp(r'\r?\n'));
  return lines.last;
}

/// XAPK 的 manifest.json 里 expansions 列出 OBB 及其在手机上的位置
class XapkExpansion {
  const XapkExpansion({required this.file, required this.installPath});

  /// 压缩包内的相对路径
  final String file;

  /// 手机上的位置，如 Android/obb/<包名>/main.1.xxx.obb
  final String installPath;
}

final _obbPath = RegExp(r'^Android/obb/[\w.]+/[^/]+$');

/// 解析 XAPK 的 manifest.json，只留下合法的 OBB 项：
/// 只接受 Android/obb 下的相对路径，防止 manifest 把文件写到别处
List<XapkExpansion> parseXapkManifest(String json) {
  final out = <XapkExpansion>[];
  Object? raw;
  try {
    raw = jsonDecode(json);
  } catch (_) {
    return out;
  }
  if (raw is! Map) return out;
  final expansions = raw['expansions'];
  if (expansions is! List) return out;
  for (final e in expansions) {
    if (e is! Map) continue;
    final file = e['file'];
    final installPath = e['install_path'];
    if (file is! String || installPath is! String) continue;
    if (!_obbPath.hasMatch(installPath) || file.contains('..')) continue;
    out.add(XapkExpansion(file: file, installPath: installPath));
  }
  return out;
}
