import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:toolbox_core/toolbox_core.dart';

import 'settings_store.dart';

/// 方案目录：配置了远程地址就拉取并校验，失败时退回本地缓存，再退回内置目录
class CatalogRepository {
  CatalogRepository(String dataDir, this._settings) : _cacheFile = File(p.join(dataDir, 'catalog-cache.json'));

  final File _cacheFile;
  final SettingsStore _settings;
  CatalogState? _cached;

  Future<CatalogState> get({bool refresh = false}) async {
    if (_cached != null && !refresh) return _cached!;
    final url = _settings.load().catalogUrl;
    if (url.isEmpty) return _cached = CatalogState(schemes: builtinCatalog.schemes, source: CatalogSource.builtin);
    try {
      final remote = validateCatalog(await _fetchJson(url));
      _cacheFile.parent.createSync(recursive: true);
      _cacheFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(remote.toJson()));
      return _cached = CatalogState(schemes: mergeCatalog(remote), source: CatalogSource.remote);
    } catch (e) {
      final error = '远程目录读取失败：$e';
      try {
        final local = validateCatalog(jsonDecode(_cacheFile.readAsStringSync()));
        return _cached = CatalogState(schemes: mergeCatalog(local), source: CatalogSource.cache, error: error);
      } catch (_) {
        return _cached = CatalogState(schemes: builtinCatalog.schemes, source: CatalogSource.builtin, error: error);
      }
    }
  }

  Future<RootScheme?> find(String id) async {
    for (final s in (await get()).schemes) {
      if (s.id == id) return s;
    }
    return null;
  }

  static Future<Object?> _fetchJson(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      final res = await req.close().timeout(const Duration(seconds: 30));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != HttpStatus.ok) throw 'HTTP ${res.statusCode}';
      return jsonDecode(body);
    } finally {
      client.close(force: true);
    }
  }
}
