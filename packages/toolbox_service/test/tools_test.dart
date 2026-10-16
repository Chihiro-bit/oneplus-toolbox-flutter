import 'package:test/test.dart';
import 'package:toolbox_commands/toolbox_commands.dart';
import 'package:toolbox_core/toolbox_core.dart';

// ───────────── 发到手机上的脚本（与 TS 版逐字比对） ─────────────
//
// 期望值是直接跑 TS 版（src/main/ops/shizuku.ts 的 PROBE、src/main/ops/modules.ts 的 installScript、
// src/main/ops/network.ts 的 READ_KEYS、src/main/ops/drivers.ts 的 PNP_SCRIPT）打印出来的原文，
// 不是手抄的。改动 Dart 侧脚本前请先对照 TS 版。

const _probeGolden = r'''P=moe.shizuku.privileged.api
echo "SDK|$(getprop ro.build.version.sdk)"
pid=$(pidof shizuku_server)
[ -n "$pid" ] && echo "RUNNING|$pid"
apk=$(pm path $P 2>/dev/null | head -n 1 | sed 's/^package://')
if [ -n "$apk" ]; then
  d=${apk%/*}
  for f in $d/lib/arm64/libshizuku.so $d/lib/*/libshizuku.so /sdcard/Android/data/$P/start.sh; do
    [ -f "$f" ] && { echo "STARTER|$f"; break; }
  done
  echo "DUMPSYS|"
  dumpsys package $P
fi
true''';

const _installScriptGolden = r'''Z=/data/local/tmp/oneplus-toolbox/module_0.zip
if [ -x /data/adb/ksud ]; then /data/adb/ksud module install "$Z"
elif [ -x /data/adb/apd ]; then /data/adb/apd module install "$Z"
elif command -v magisk >/dev/null 2>&1; then magisk --install-module "$Z"
else echo NO_TOOL; exit 0; fi
echo "EXIT|$?"''';

const _readScriptGolden = r'echo "captive_portal_https_url=$(settings get global captive_portal_https_url)"; '
    r'echo "captive_portal_http_url=$(settings get global captive_portal_http_url)"; '
    r'echo "captive_portal_fallback_url=$(settings get global captive_portal_fallback_url)"; '
    r'echo "captive_portal_other_fallback_urls=$(settings get global captive_portal_other_fallback_urls)"; '
    r'echo "private_dns_mode=$(settings get global private_dns_mode)"; '
    r'echo "private_dns_specifier=$(settings get global private_dns_specifier)"';

const _pnpGolden = r"$ErrorActionPreference='SilentlyContinue';"
    r"Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match 'VID_(2A70|22D9|18D1|05C6)' -or $_.FriendlyName -match 'Android|ADB|Fastboot|Bootloader|QDLoader|OnePlus' } |"
    r"ForEach-Object { '{0}|{1}|{2}|{3}|{4}' -f $_.FriendlyName, $_.InstanceId, $_.Status, $_.Class, [int]$_.ConfigManagerErrorCode }";

/// `dumpsys package moe.shizuku.privileged.api` 的片段（取自 TS 版 test/shizuku.test.ts）
const _dump = '''Packages:
  Package [moe.shizuku.privileged.api] (3c1f2a1):
    versionCode=1086 minSdk=24 targetSdk=35
    versionName=13.6.0.r1086.2650830c
    requested permissions:
      android.permission.WRITE_SECURE_SETTINGS
      android.permission.INTERNET
    install permissions:
      android.permission.INTERNET: granted=true
    User 0: ceDataInode=1234 installed=true hidden=false suspended=false
      runtime permissions:
        android.permission.WRITE_SECURE_SETTINGS: granted=true, flags=[ USER_SET ]
      disabledComponents:
        moe.shizuku.manager.receiver.BootCompleteReceiver
''';

void main() {
  group('手机端脚本与 TS 版逐字一致', () {
    test('Shizuku 状态探测', () => expect(shizukuProbeScript, _probeGolden));
    test('Root 模块安装', () => expect(installScript('$remoteDir/module_0.zip'), _installScriptGolden));
    test('读取联网设置', () => expect(networkReadScript(), _readScriptGolden));
    test('设备管理器查询', () => expect(driverCheckScript, _pnpGolden));
  });

  group('parseShizukuProbe', () {
    test('未安装', () {
      final s = parseShizukuProbe('SDK|35\n');
      expect(s.installed, isFalse);
      expect(s.running, isFalse);
      expect(s.sdk, 35);
      expect(s.version, isNull);
      expect(s.starter, isNull);
      expect(s.secureSettings, isNull);
      expect(s.bootReceiver, isNull);
    });

    test('已安装、未运行，找到 libshizuku.so', () {
      final s = parseShizukuProbe('SDK|35\r\n'
          'STARTER|/data/app/~~a==/moe.shizuku.privileged.api-b==/lib/arm64/libshizuku.so\r\n'
          'DUMPSYS|\r\n$_dump');
      expect(s.installed, isTrue);
      expect(s.version, '13.6.0.r1086.2650830c');
      expect(s.running, isFalse);
      expect(s.sdk, 35);
      expect(s.starter, '/data/app/~~a==/moe.shizuku.privileged.api-b==/lib/arm64/libshizuku.so');
      expect(s.secureSettings, isTrue);
      expect(s.bootReceiver, isFalse);
      expect(starterCommand(s.starter!), [s.starter]);
    });

    test('正在运行，开机广播没被关', () {
      final s = parseShizukuProbe('SDK|34\nRUNNING|12345\n'
          'STARTER|/sdcard/Android/data/moe.shizuku.privileged.api/start.sh\n'
          'DUMPSYS|\n    versionName=13.6.0\n');
      expect(s.installed, isTrue);
      expect(s.running, isTrue);
      expect(s.sdk, 34);
      expect(s.version, '13.6.0');
      expect(s.starter, endsWith('start.sh'));
      expect(s.secureSettings, isFalse);
      expect(s.bootReceiver, isTrue);
      expect(starterCommand(s.starter!), ['sh', s.starter]);
    });

    test('dumpsys 里的 | 不影响解析', () {
      final s = parseShizukuProbe('SDK|35\nDUMPSYS|\n  RUNNING|1 STARTER|x\n');
      expect(s.installed, isTrue);
      expect(s.running, isFalse);
      expect(s.starter, isNull);
      expect(s.secureSettings, isFalse);
      expect(s.bootReceiver, isTrue);
    });

    test('SDK 不是数字时忽略', () {
      expect(parseShizukuProbe('SDK|abc\n').sdk, isNull);
    });
  });

  group('parseDrivers', () {
    test('正常的设备不给提示，复合设备父节点不显示', () {
      final out = [
        r'USB Composite Device|USB\VID_22D9&PID_2766\B8A048D8|OK|USB|0',
        r'一加 13|USB\VID_22D9&PID_2769\B8A048D8|OK|USBDevice|0',
        r'Android Bootloader Interface|USB\VID_18D1&PID_4EE0\B8A048D8|OK|AndroidUsbDeviceClass|0',
      ].join('\r\n');
      final list = parseDrivers(out);
      expect([for (final d in list) d.name], ['一加 13', 'Android Bootloader Interface']);
      expect(list.every((d) => d.ok && d.hint == null), isTrue);
      expect(list.first.className, 'USBDevice');
      expect(list.first.problem, isNull);
    });

    test('没装驱动的 Fastboot 设备', () {
      final d = parseDrivers(r'Android|USB\VID_18D1&PID_D00D\B8A048D8|Error||28').single;
      expect(d.ok, isFalse);
      expect(d.problem, '没有安装驱动（代码 28）');
      expect(d.hint, contains('Google USB'));
      expect(d.className, isNull);
    });

    test('9008 驱动签名失败', () {
      final d = parseDrivers(r'Qualcomm HS-USB QDLoader 9008 (COM5)|USB\VID_05C6&PID_9008\5&1|Error|Ports|52').single;
      expect(d.problem, '驱动签名验证失败（代码 52）');
      expect(d.hint, contains('9008'));
    });

    test('有问题的复合设备也要显示', () {
      expect(parseDrivers(r'USB Composite Device|USB\VID_22D9&PID_2766\X|Error|USB|10'), hasLength(1));
    });

    test('状态不是 OK 而错误码是 0 时也给说明', () {
      final d = parseDrivers(r'一加 13|USB\VID_22D9&PID_2769\B8A048D8|Unknown|USBDevice|0').single;
      expect(d.ok, isFalse);
      expect(d.problem, '状态 Unknown');
      expect(d.hint, '安装 Google USB 驱动后，在设备管理器里对它「更新驱动程序」并选择驱动所在的文件夹');
    });

    test('没有 InstanceId 的行丢掉，没有名称的留「（无名称）」', () {
      expect(parseDrivers('|||||\n'), isEmpty);
      expect(parseDrivers(r'|USB\VID_22D9&PID_2769\X|||0').single.name, '（无名称）');
    });

    test('未知错误码给「设备异常」', () {
      expect(parseDrivers(r'Foo|USB\VID_2A70&PID_1234\X|Error|USB|7').single.problem, '设备异常（代码 7）');
    });
  });

  group('pickSplits', () {
    test('ABI 分包只留手机首选架构，standalones 跳过', () {
      final names = [
        'base.apk',
        'split_config.arm64_v8a.apk',
        'split_config.armeabi_v7a.apk',
        'split_config.xxhdpi.apk',
        'standalones/standalone-arm64_v8a.apk',
      ];
      expect(pickSplits(names, 'arm64-v8a,armeabi-v7a,armeabi'), [
        'base.apk',
        'split_config.arm64_v8a.apk',
        'split_config.xxhdpi.apk',
      ]);
    });

    test('按 abilist 的顺序决定首选架构', () {
      final names = ['split_config.x86_64.apk', 'split_config.arm64_v8a.apk'];
      expect(pickSplits(names, 'x86_64,arm64-v8a'), ['split_config.x86_64.apk']);
      expect(pickSplits(names, 'arm64-v8a,x86_64'), ['split_config.arm64_v8a.apk']);
    });

    test('手机支持的架构一个都没有时，只装不带 ABI 的分包', () {
      final names = ['base.apk', 'split_config.armeabi_v7a.apk', 'split_config.xxhdpi.apk'];
      expect(pickSplits(names, 'mips'), ['base.apk', 'split_config.xxhdpi.apk']);
    });

    test('instant/ 与非 apk 文件都跳过', () {
      expect(pickSplits(['instant/base.apk', 'manifest.json', 'toc.pb', 'base.apk'], ''), ['base.apk']);
    });

    test('ABI 分包写在文件名前缀或中段也能认出来', () {
      expect(pickSplits(['com.a-armeabi_v7a.apk'], 'armeabi_v7a'), ['com.a-armeabi_v7a.apk']);
      expect(pickSplits(['com.a-armeabi_v7a.apk'], 'arm64-v8a'), isEmpty);
    });
  });

  group('XAPK 的 manifest', () {
    test('只留下 Android/obb 下的合法项', () {
      final list = parseXapkManifest('{"expansions":['
          '{"file":"Android/obb/com.a/main.1.obb","install_path":"Android/obb/com.a/main.1.obb"},'
          '{"file":"../evil.apk","install_path":"Android/obb/com.a/x.obb"},'
          '{"file":"a.obb","install_path":"/sdcard/Android/obb/com.a/x.obb"},'
          '{"file":"a.obb","install_path":"Android/obb/com.a/sub/x.obb"},'
          '{"file":"a.obb"},'
          '"nope"]}');
      expect(list, hasLength(1));
      expect(list.single.file, 'Android/obb/com.a/main.1.obb');
      expect(list.single.installPath, 'Android/obb/com.a/main.1.obb');
    });

    test('没有 expansions 或不是 JSON 时返回空', () {
      expect(parseXapkManifest('{}'), isEmpty);
      expect(parseXapkManifest('{"expansions":{}}'), isEmpty);
      expect(parseXapkManifest('not json'), isEmpty);
    });
  });

  group('Root 模块', () {
    test('根目录有 module.prop 才算模块', () {
      const mod = '2024-01-01 00:00:00 .....          123          100  module.prop\r\n'
          '2024-01-01 00:00:00 .....          1          1  META-INF/com/google/android/update-binary\r\n';
      expect(isModuleListing(mod), isTrue);
      expect(isModuleListing('2024-01-01 00:00:00 .....  1  1  sub/module.prop\n'), isFalse);
      expect(isModuleListing('2024-01-01 00:00:00 .....  1  1  payload.bin\n'), isFalse);
      expect(isModuleListing('2024-01-01 00:00:00 .....  1  1  ./module.prop\n'), isTrue);
    });

    test('按 KernelSU → APatch → Magisk 的顺序找安装命令', () {
      final s = installScript('$remoteDir/module_0.zip');
      expect(s.indexOf('ksud'), lessThan(s.indexOf('apd')));
      expect(s.indexOf('apd'), lessThan(s.indexOf('magisk')));
    });

    test('解析 NO_TOOL 与退出码', () {
      final noTool = parseModuleInstall('NO_TOOL\n');
      expect(noTool.noTool, isTrue);
      expect(noTool.code, isNull);
      expect(parseModuleInstall('some output\nEXIT|0\n').code, '0');
      expect(parseModuleInstall('noise\nEXIT|7\n').code, '7');
      expect(parseModuleInstall('noise\n').code, isNull);
      expect(parseModuleInstall('noise\n').noTool, isFalse);
    });
  });

  group('安装文件与失败原因', () {
    test('isInstallable 只认三种后缀', () {
      for (final p in [r'C:\a\b.apk', 'C:/a/b.APKS', 'b.xapk']) {
        expect(isInstallable(p), isTrue, reason: p);
      }
      for (final p in ['b.zip', 'b.apk.bak', 'b']) {
        expect(isInstallable(p), isFalse, reason: p);
      }
    });

    test('failureReason 只取 Failure [...] 那一行', () {
      expect(
        failureReason('Performing Streamed Install\nFailure [INSTALL_FAILED_ALREADY_EXISTS: x]\nmore'),
        'Failure [INSTALL_FAILED_ALREADY_EXISTS: x]',
      );
      expect(failureReason('one\ntwo'), 'two');
      expect(failureReason(''), '');
    });
  });

  group('私人 DNS 参数', () {
    test('settings put 的值按手机端 shell 转义', () {
      expect(settingsPutArgs('private_dns_specifier', 'dns.alidns.com'),
          ['settings', 'put', 'global', 'private_dns_specifier', "'dns.alidns.com'"]);
      expect(settingsDeleteArgs('private_dns_mode'), ['settings', 'delete', 'global', 'private_dns_mode']);
    });
  });

  test('isRooted 区分已 Root 和未 Root', () {
    expect(isRooted('Magisk 30.7'), isTrue);
    expect(isRooted('KernelSU 3.3.1'), isTrue);
    expect(isRooted('未 Root'), isFalse);
    expect(isRooted('未检测到（装有 Magisk App）'), isFalse);
    expect(isRooted(null), isFalse);
  });
}
