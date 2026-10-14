// 从各项目的官方发布地址下载运行所需的第三方工具，校验 sha256 后放到 resources/bin。
// 仓库里不提交任何二进制文件；本地开发和 CI 都用这个脚本准备工具。
//
// 用法：在仓库根目录运行 `melos run fetch-tools`（或 `dart run tool/fetch_tools.dart`）
// 升级某个工具时，修改下面的 url 和 sha256 即可（sha256 可在 GitHub Release 页面文件旁看到）。
// 版本与 TS 版（oneplus-toolbox 仓库的 scripts/fetch-tools.mjs）保持一致。

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

final root = p.dirname(p.dirname(Platform.script.toFilePath()));
final cache = p.join(root, '.tools-cache');
final bin = p.join(root, 'resources', 'bin');

/// [entries]：压缩包内路径 → resources/bin 下的路径；为空时整个文件另存为 [file]
typedef Tool = ({
  String name,
  String url,
  String sha256,
  Map<String, String>? entries,
  bool tarGz,
  String? file,
});

const List<Tool> tools = [
  (
    name: 'Android SDK Platform-Tools r37.0.1（adb / fastboot）',
    url: 'https://dl.google.com/android/repository/platform-tools_r37.0.1-win.zip',
    sha256: '45f4d63113e895ebde0c90f194099a4676b6ac653bd28d54314a9e022bbc1a99',
    entries: {
      'platform-tools/adb.exe': 'platform-tools/adb.exe',
      'platform-tools/fastboot.exe': 'platform-tools/fastboot.exe',
      'platform-tools/AdbWinApi.dll': 'platform-tools/AdbWinApi.dll',
      'platform-tools/AdbWinUsbApi.dll': 'platform-tools/AdbWinUsbApi.dll',
      'platform-tools/NOTICE.txt': 'platform-tools/NOTICE.txt',
    },
    tarGz: false,
    file: null,
  ),
  (
    name: 'payload-dumper-rust v0.8.4（ROM 解包，支持 URL）',
    url:
        'https://github.com/rhythmcache/payload-dumper-rust/releases/download/payload-dumper-rust-v0.8.4/payload_dumper-windows-x86_64.zip',
    sha256: 'e2bbee5476a594951d9d2e70c72e0fcf3414ed8d50a48344165bd3b106f778a1',
    entries: {'payload_dumper.exe': 'payload_dumper.exe'},
    tarGz: false,
    file: null,
  ),
  (
    // 与 TS 版使用同一个 7za.exe：取自 npm 包 7zip-bin 5.2.0（tarball 的 sha512 与 npm 公布的 integrity 一致）
    name: '7-Zip 21.07（7za.exe，取自 npm 包 7zip-bin 5.2.0）',
    url: 'https://registry.npmjs.org/7zip-bin/-/7zip-bin-5.2.0.tgz',
    sha256: '04f9738ee00be8be53f5d06254a9e6e4b5117b17f8b74058477d870e62764a7d',
    entries: {'package/win/x64/7za.exe': '7za.exe'},
    tarGz: true,
    file: null,
  ),
  (
    name: 'aapt2 arm64-v8a（ReVanced/aapt2 v1.1.0，推到手机上读取应用名）',
    url: 'https://github.com/ReVanced/aapt2/releases/download/v1.1.0/aapt2-arm64-v8a',
    sha256: '7e5ae2e1f62fc24cab14072555ffd0a1a7e1ce27e82cc1008967b835b6d8df5b',
    entries: null,
    tarGz: false,
    file: 'aapt2',
  ),
  (
    name: 'Magisk v30.7（离线 Root 方案）',
    url: 'https://github.com/topjohnwu/Magisk/releases/download/v30.7/Magisk-v30.7.apk',
    sha256: 'e0d32d2123532860f97123d927b1bb86c4e08e6fd8a48bfc6b5bee0afae9ebd5',
    entries: null,
    tarGz: false,
    file: 'magisk.apk',
  ),
];

String _sha256(List<int> bytes) => sha256.convert(bytes).toString();

/// 下载并校验，按哈希缓存在 .tools-cache
Future<Uint8List> download(Tool tool) async {
  final cached = File(p.join(cache, tool.sha256));
  if (cached.existsSync()) {
    final bytes = cached.readAsBytesSync();
    if (_sha256(bytes) == tool.sha256) return bytes;
  }
  stdout.writeln('  下载 ${tool.url}');
  final client = HttpClient();
  try {
    final res = await (await client.getUrl(Uri.parse(tool.url))).close();
    if (res.statusCode != HttpStatus.ok) throw '${tool.name} 下载失败：HTTP ${res.statusCode}';
    final builder = BytesBuilder(copy: false);
    await res.forEach(builder.add);
    final bytes = builder.takeBytes();
    final actual = _sha256(bytes);
    if (actual != tool.sha256) throw '${tool.name} 校验失败\n  期望 ${tool.sha256}\n  实际 $actual';
    cached.parent.createSync(recursive: true);
    cached.writeAsBytesSync(bytes);
    return bytes;
  } finally {
    client.close(force: true);
  }
}

void extract(Tool tool, Uint8List bytes) {
  final archive =
      tool.tarGz ? TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes)) : ZipDecoder().decodeBytes(bytes);
  for (final MapEntry(key: from, value: to) in tool.entries!.entries) {
    final entry = archive.findFile(from);
    if (entry == null) throw '${tool.name}：压缩包中缺少 $from';
    final out = File(p.join(bin, to))..parent.createSync(recursive: true);
    out.writeAsBytesSync(entry.content as List<int>);
  }
}

Future<void> main() async {
  final dir = Directory(bin);
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);

  try {
    for (final tool in tools) {
      stdout.writeln('✓ ${tool.name}');
      final bytes = await download(tool);
      if (tool.entries != null) {
        extract(tool, bytes);
      } else {
        File(p.join(bin, tool.file!)).writeAsBytesSync(bytes);
      }
    }
  } catch (e) {
    stderr.writeln('$e');
    exitCode = 1;
    return;
  }
  stdout.writeln('工具已就绪：$bin');
}
