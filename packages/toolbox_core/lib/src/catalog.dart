import 'models.dart';

/// 内置方案目录。下载地址全部指向各项目的 GitHub Releases，sha256 取自 GitHub 公布的资产摘要。
/// 需要更新版本时，可以改这里，也可以在设置里填一个远程 catalog.json（格式见 TS 版仓库的 catalog/README.md）。
///
/// 与 TS 版 src/shared/catalog.ts 保持一致。
const builtinCatalog = Catalog(
  updated: '2026-10-14',
  schemes: [
    RootScheme(
      id: 'magisk',
      name: 'Magisk',
      family: RootFamily.magisk,
      version: '30.7',
      package: 'com.topjohnwu.magisk',
      apk: SchemeApk(
        url: 'https://github.com/topjohnwu/Magisk/releases/download/v30.7/Magisk-v30.7.apk',
        sha256: 'e0d32d2123532860f97123d927b1bb86c4e08e6fd8a48bfc6b5bee0afae9ebd5',
        size: 11613864,
      ),
      homepage: 'https://github.com/topjohnwu/Magisk',
      note: '最通用的方案。部分老机型（一加 7T / 8 / 8T / 9R 等）不适用',
    ),
    RootScheme(
      id: 'magisk-bundled',
      name: 'Magisk（内置）',
      family: RootFamily.magisk,
      version: '30.7',
      package: 'com.topjohnwu.magisk',
      apk: SchemeApk(bundled: true),
      homepage: 'https://github.com/topjohnwu/Magisk',
      note: '随工具箱附带，无需联网下载',
    ),
    RootScheme(
      id: 'apatch',
      name: 'APatch',
      family: RootFamily.apatch,
      version: '11224',
      package: 'me.bmax.apatch',
      apk: SchemeApk(
        url: 'https://github.com/bmax121/APatch/releases/download/11224/APatch_11224_9a63e0f_HEAD-release-signed.apk',
        sha256: 'f1986f9a9c3b2b2d5ca09aa6b9ef24226fef662f8faf5677ce1447ffcae68590',
        size: 6569091,
      ),
      homepage: 'https://github.com/bmax121/APatch',
      note: '修补内核（boot），需要设置超级密钥。一加 8 / 8 Pro 不支持',
    ),
    RootScheme(
      id: 'kernelsu',
      name: 'KernelSU',
      family: RootFamily.ksu,
      version: '3.3.1',
      package: 'me.weishu.kernelsu',
      apk: SchemeApk(
        url: 'https://github.com/tiann/KernelSU/releases/download/v3.3.1/KernelSU_v3.3.1_32680-release.apk',
        sha256: 'b4a059ace71de2fa65cc7f12b1c58d55fc23ab25e057ee4230ce779742abe450',
        size: 13637206,
      ),
      homepage: 'https://github.com/tiann/KernelSU',
      note: '仅支持 GKI 2.0 设备（Android 12 及以后出厂，内核 5.10+）。不支持时修补会失败，不会刷入任何东西',
    ),
    RootScheme(
      id: 'kernelsu-next',
      name: 'KernelSU Next',
      family: RootFamily.ksu,
      version: '3.4.2',
      package: 'com.rifsxd.ksunext',
      apk: SchemeApk(
        url:
            'https://github.com/KernelSU-Next/KernelSU-Next/releases/download/v3.4.2/KernelSU_Next_v3.4.2_33355-release.apk',
        sha256: '774a5511f7034a4930e881114e202319cbdc34c5aaaa5c7c6b6d2902364e4c58',
        size: 16682167,
      ),
      homepage: 'https://github.com/KernelSU-Next/KernelSU-Next',
      note: '仅支持 GKI 2.0 设备',
    ),
    RootScheme(
      id: 'sukisu-ultra',
      name: 'SukiSU Ultra',
      family: RootFamily.ksu,
      version: '4.2.0',
      package: 'com.sukisu.ultra',
      apk: SchemeApk(
        url: 'https://github.com/SukiSU-Ultra/SukiSU-Ultra/releases/download/v4.2.0/SukiSU_v4.2.0_40900-release.apk',
        sha256: '4ca9810e6355fbff0bbe4bf5ce159808e64a40d85987a11894030cd990a6bdf3',
        size: 14084162,
      ),
      homepage: 'https://github.com/SukiSU-Ultra/SukiSU-Ultra',
      note: '仅支持 GKI 2.0 设备',
    ),
  ],
);

/// 已知的 Root 管理器包名，切换方案时用于卸载旧管理器
const knownManagers = [
  'com.topjohnwu.magisk',
  'io.github.huskydg.magisk',
  'io.github.vvb2060.magisk',
  'me.bmax.apatch',
  'me.weishu.kernelsu',
  'com.rifsxd.ksunext',
  'com.sukisu.ultra',
  'com.resukisu.resukisu',
];

class CatalogFormatException implements Exception {
  const CatalogFormatException(this.message);
  final String message;

  @override
  String toString() => message;
}

final _idPattern = RegExp(r'^[a-z0-9-]{1,40}$');
final _packagePattern = RegExp(r'^[\w.]+$');
final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$', caseSensitive: false);

/// 校验远程目录：只接受数据字段，下载地址必须是 https，哈希必须是 sha256
Catalog validateCatalog(Object? raw) {
  if (raw is! Map || raw['schemaVersion'] != Catalog.schemaVersion || raw['schemes'] is! List) {
    throw const CatalogFormatException('目录格式不正确（需要 schemaVersion: 1 和 schemes 数组）');
  }
  final list = raw['schemes'] as List;
  final schemes = <RootScheme>[];
  for (var i = 0; i < list.length; i++) {
    final where = '第 ${i + 1} 个方案';
    final s = list[i];
    Never fail(String msg) => throw CatalogFormatException('$where：$msg');

    if (s is! Map) fail('格式不正确');
    final id = s['id'];
    if (id is! String || !_idPattern.hasMatch(id)) fail('id 不合法');
    final name = s['name'];
    if (name is! String || name.isEmpty) fail('缺少 name');
    final family = RootFamily.tryParse(s['family']);
    if (family == null) fail('family 必须是 ${RootFamily.values.map((f) => f.name).join(' / ')}');
    final version = s['version'];
    if (version is! String) fail('缺少 version');
    final package = s['package'];
    if (package is! String || !_packagePattern.hasMatch(package)) fail('package 不合法');
    final apk = s['apk'];
    if (apk is! Map || apk['url'] is! String || !(apk['url'] as String).startsWith('https://')) {
      fail('apk.url 必须是 https 地址');
    }
    final sha = apk['sha256'];
    if (sha is! String || !_sha256Pattern.hasMatch(sha)) fail('apk.sha256 必须是 64 位十六进制');
    final homepage = s['homepage'];
    final note = s['note'];
    final size = apk['size'];

    schemes.add(RootScheme(
      id: id,
      name: name,
      family: family,
      version: version,
      package: package,
      apk: SchemeApk(url: apk['url'] as String, sha256: sha.toLowerCase(), size: size is num ? size.toInt() : null),
      homepage: homepage is String && homepage.startsWith('https://') ? homepage : null,
      note: note is String ? note : null,
    ));
  }
  final updated = raw['updated'];
  return Catalog(updated: updated is String ? updated : null, schemes: schemes);
}

/// 远程目录覆盖同 id 的内置方案，新 id 追加在后；内置的离线方案始终保留
List<RootScheme> mergeCatalog(Catalog remote) {
  final byId = {for (final s in builtinCatalog.schemes) s.id: s};
  for (final s in remote.schemes) {
    if (byId[s.id]?.apk.bundled != true) byId[s.id] = s;
  }
  return byId.values.toList();
}
