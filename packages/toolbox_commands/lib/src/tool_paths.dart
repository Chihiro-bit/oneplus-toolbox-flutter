import 'dart:io';

import 'package:path/path.dart' as p;

/// 随程序分发的第三方工具（由 `melos run fetch-tools` 下载到仓库根目录的 resources/bin 并校验）
class ToolPaths {
  const ToolPaths(this.binDir);

  final String binDir;

  String get adb => p.join(binDir, 'platform-tools', 'adb.exe');
  String get fastboot => p.join(binDir, 'platform-tools', 'fastboot.exe');
  String get sevenZip => p.join(binDir, '7za.exe');

  /// payload-dumper-rust：支持 payload.bin、ROM zip 和 http(s) URL（按需读取）
  String get payloadDumper => p.join(binDir, 'payload_dumper.exe');
  String get magiskApk => p.join(binDir, 'magisk.apk');

  /// Android 端的 aapt2，推到手机上读取应用名
  String get aapt2 => p.join(binDir, 'aapt2');

  /// 投屏，随附的 DLL 和 scrcpy-server 必须与它同目录
  String get scrcpy => p.join(binDir, 'scrcpy', 'scrcpy.exe');

  /// AAB 转分包 APK
  String get bundletool => p.join(binDir, 'bundletool', 'bundletool.jar');

  /// 随安装包的精简 Java 运行时（bundletool 用），用户不需要自己安装 Java
  String get java => p.join(binDir, 'jre', 'bin', 'java.exe');

  /// 高通 9008 / EDL 刷写工具，随附的 DLL 必须与它同目录
  String get qdl => p.join(binDir, 'qdl', 'qdl.exe');

  Map<String, String> get all => {
        'adb': adb,
        'fastboot': fastboot,
        'sevenZip': sevenZip,
        'payloadDumper': payloadDumper,
        'magiskApk': magiskApk,
        'aapt2': aapt2,
        'scrcpy': scrcpy,
        'bundletool': bundletool,
        'java': java,
        'qdl': qdl,
      };

  List<String> missing() => [
        for (final e in all.entries)
          if (!File(e.value).existsSync()) e.key
      ];
}
