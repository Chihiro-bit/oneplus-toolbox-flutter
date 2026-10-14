import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:toolbox_core/toolbox_core.dart';

Future<String> sha256File(String path) async => (await sha256.bind(File(path).openRead()).first).toString();

class ChecksumMismatchException implements Exception {
  const ChecksumMismatchException(this.expected, this.actual);

  final String expected;
  final String actual;

  @override
  String toString() => 'sha256 不匹配：期望 $expected，实际 $actual';
}

class HttpStatusException implements Exception {
  const HttpStatusException(this.status);
  final int status;

  @override
  String toString() => 'HTTP $status';
}

class VerifiedFile {
  const VerifiedFile(this.path, {required this.fromCache});

  final String path;
  final bool fromCache;
}

/// 下载文件到 [cacheDir] 并校验 sha256。缓存以哈希命名，校验通过的文件可重复使用。
/// 哈希不一致时删除文件并抛出 [ChecksumMismatchException] —— 绝不返回未通过校验的文件。
/// [onStart] 在确认缓存不可用、真正开始联网下载时调用。
Future<VerifiedFile> downloadVerified(
  String url,
  String expectedSha256,
  String cacheDir, {
  CancelToken? cancel,
  void Function()? onStart,
  void Function(int received, int? total)? onProgress,
  String extension = '.apk',
}) async {
  final want = expectedSha256.toLowerCase();
  Directory(cacheDir).createSync(recursive: true);
  final target = File(p.join(cacheDir, '$want$extension'));
  if (target.existsSync() && await sha256File(target.path) == want) return VerifiedFile(target.path, fromCache: true);

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  // 连接或等待响应头期间取消：强制关闭连接，让挂起的请求立即失败
  cancel?.whenCancelled.then((_) => client.close(force: true));
  final tmp = File('${target.path}.part');
  final sink = tmp.openWrite();
  final hashOut = _DigestSink();
  final hasher = sha256.startChunkedConversion(hashOut);
  try {
    cancel?.throwIfCancelled();
    onStart?.call();
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    if (res.statusCode != HttpStatus.ok) throw HttpStatusException(res.statusCode);
    final total = res.contentLength > 0 ? res.contentLength : null;
    var got = 0;

    final done = Completer<void>();
    final sub = res.listen(
      (chunk) {
        hasher.add(chunk);
        sink.add(chunk);
        got += chunk.length;
        onProgress?.call(got, total);
      },
      onError: done.completeError,
      onDone: done.complete,
      cancelOnError: true,
    );
    cancel?.whenCancelled.then((_) {
      sub.cancel();
      if (!done.isCompleted) done.completeError(const CancelledException());
    });
    await done.future;
    await sink.close();
    hasher.close();

    final actual = hashOut.value.toString();
    if (actual != want) throw ChecksumMismatchException(want, actual);
    if (target.existsSync()) target.deleteSync();
    tmp.renameSync(target.path);
    return VerifiedFile(target.path, fromCache: false);
  } catch (_) {
    await sink.close().catchError((_) {});
    if (tmp.existsSync()) tmp.deleteSync();
    if (cancel?.isCancelled ?? false) throw const CancelledException();
    rethrow;
  } finally {
    client.close(force: true);
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
