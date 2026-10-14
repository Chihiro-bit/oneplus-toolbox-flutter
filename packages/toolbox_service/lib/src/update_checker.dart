import 'dart:io';

import 'package:toolbox_core/toolbox_core.dart';

List<int> _parse(String v) => v
    .replaceFirst(RegExp('^v', caseSensitive: false), '')
    .split(RegExp('[.-]'))
    .map((x) => int.tryParse(x) ?? 0)
    .toList();

/// a 是否比 b 新（按数字逐段比较，忽略前缀 v）
bool isNewerVersion(String a, String b) {
  final x = _parse(a);
  final y = _parse(b);
  for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
    final xi = i < x.length ? x[i] : 0;
    final yi = i < y.length ? y[i] : 0;
    if (xi != yi) return xi > yi;
  }
  return false;
}

/// 通过 releases/latest 的跳转地址取最新 tag，不走 GitHub API，避免限流
Future<UpdateInfo> checkUpdate({required String current, required String repo}) async {
  if (repo.isEmpty) return UpdateInfo(current: current, error: '未配置更新仓库');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await client.getUrl(Uri.parse('https://github.com/$repo/releases/latest'));
    req.followRedirects = false;
    final res = await req.close().timeout(const Duration(seconds: 30));
    await res.drain<void>();
    final loc = res.headers.value(HttpHeaders.locationHeader) ?? '';
    final tag = RegExp(r'/releases/tag/([^/?#]+)').firstMatch(loc)?[1];
    if (tag == null) return UpdateInfo(current: current, error: '该仓库还没有发布版本');
    final latest = Uri.decodeComponent(tag);
    return UpdateInfo(
      current: current,
      latest: latest,
      url: 'https://github.com/$repo/releases/tag/$tag',
      hasUpdate: isNewerVersion(latest, current),
    );
  } catch (e) {
    return UpdateInfo(current: current, error: '$e');
  } finally {
    client.close(force: true);
  }
}
