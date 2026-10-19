import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:toolbox_core/toolbox_core.dart';

import 'exec.dart';
import 'tool_paths.dart';

/// AAB 的转换：用 bundletool 按当前手机的配置生成对应的分包 APK。
///
/// 对应 TS 版 src/main/ops/aab.ts 和 src/main/ops/aab-key.ts。

/// 内置的调试签名密钥（base64，别名 androiddebugkey，密码 android）。
/// bundletool 默认使用 ~/.android/debug.keystore 签名转换出来的分包；电脑上没有这个文件时
/// bundletool 会输出未签名的 APK（装不上），所以内置一份，保证 AAB 转换后总能安装。
const debugKeystoreBase64 =
    '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';

String _userHome(Map<String, String> env) => env['USERPROFILE'] ?? env['HOME'] ?? '';

/// bundletool 会优先用这两个位置里的调试密钥自动签名
bool hasDebugKeystore({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final sdkHome = env['ANDROID_SDK_HOME'];
  final home = _userHome(env);
  return [
    if (sdkHome != null && sdkHome.isNotEmpty) sdkHome,
    if (home.isNotEmpty) home,
  ].any((h) => File(p.join(h, '.android', 'debug.keystore')).existsSync());
}

/// 优先用随安装包的精简 JRE；开发环境没有它时，再按 JAVA_HOME → PATH → 常见安装位置查找
String? findJava(ToolPaths tools, {Map<String, String>? environment}) {
  if (File(tools.java).existsSync()) return tools.java;
  final env = environment ?? Platform.environment;
  final exe = Platform.isWindows ? 'java.exe' : 'java';
  final pathSeparator = Platform.isWindows ? ';' : ':';
  final candidates = <String>[
    if ((env['JAVA_HOME'] ?? '').isNotEmpty) p.join(env['JAVA_HOME']!, 'bin', exe),
    for (final d in (env['PATH'] ?? '').split(pathSeparator))
      if (d.isNotEmpty) p.join(d, exe),
  ];
  // Android Studio 自带 JBR，没单独装 Java 的电脑也能用
  final programFiles = env['ProgramFiles'] ?? r'C:\Program Files';
  for (final sub in ['jbr', 'jre']) {
    candidates.add(p.join(programFiles, 'Android', 'Android Studio', sub, 'bin', exe));
  }
  // 常见的 JDK 安装目录（下面还有一层带版本号的子目录）
  for (final parent in ['Java', 'Eclipse Adoptium', 'Microsoft']) {
    try {
      for (final entry in Directory(p.join(programFiles, parent)).listSync()) {
        if (entry is Directory) candidates.add(p.join(entry.path, 'bin', exe));
      }
    } catch (_) {
      // 目录不存在
    }
  }
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

/// 从 `java -version` 的输出里取主版本号（`1.8.0` 记作 8）
int? parseJavaMajor(String output) {
  final m = RegExp(r'version "(\d+)(?:\.(\d+))?', caseSensitive: false).firstMatch(output);
  if (m == null) return null;
  final first = int.parse(m[1]!);
  return first == 1 ? int.parse(m[2] ?? '0') : first;
}

Future<int?> javaMajor(String java, {CancelToken? cancel}) async {
  final r = await exec(java, ['-version'], cancel: cancel, timeout: const Duration(seconds: 30), echoOutput: false);
  return parseJavaMajor(r.all);
}

/// bundletool 的参数。`--connected-device` + `--device-id` 只生成这台手机需要的那几个分包；
/// 传了 [keystore] 时用这个密钥签名。
List<String> bundletoolArgs({
  required String bundletool,
  required String bundle,
  required String out,
  required String serial,
  required String adb,
  String? keystore,
}) =>
    [
      '-jar',
      bundletool,
      'build-apks',
      '--bundle=$bundle',
      '--output=$out',
      '--output-format=directory',
      '--connected-device',
      '--device-id=$serial',
      '--adb=$adb',
      if (keystore != null) ...[
        '--ks=$keystore',
        '--ks-key-alias=androiddebugkey',
        '--ks-pass=pass:android',
        '--key-pass=pass:android',
      ],
    ];

/// 调用 bundletool 把 [bundle] 转换成分包目录 [out]。
/// 电脑上没有调试密钥时用内置的一份签名，否则 bundletool 会输出未签名的 APK，装不上。
Future<ExecResult> convertAab({
  required ToolPaths tools,
  required String java,
  required String bundle,
  required String out,
  required String serial,
  CancelToken? cancel,
  LogSink? log,
}) async {
  String? keystore;
  if (!hasDebugKeystore()) {
    keystore = p.join(p.dirname(out), 'debug.keystore');
    File(keystore).writeAsBytesSync(base64Decode(debugKeystoreBase64));
  }
  final args = bundletoolArgs(
    bundletool: tools.bundletool,
    bundle: bundle,
    out: out,
    serial: serial,
    adb: tools.adb,
    keystore: keystore,
  );
  return exec(java, args, cancel: cancel, log: log, timeout: const Duration(minutes: 15));
}
