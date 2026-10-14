import 'dart:io';

import 'package:test/test.dart';
import 'package:toolbox_commands/toolbox_commands.dart';
import 'package:toolbox_core/toolbox_core.dart';

/// golden/ 下的文件由 TS 版生成，保证两个版本发到手机上的脚本完全一致
String golden(String name) => File('test/golden/$name').readAsStringSync();

void main() {
  group('手机端脚本与 TS 版一致', () {
    test('magisk', () => expect(patchScript(RootFamily.magisk, 'init_boot.img'), golden('patch_magisk.sh')));
    test('apatch',
        () => expect(patchScript(RootFamily.apatch, 'boot.img', superkey: 'abc123XY'), golden('patch_apatch.sh')));
    test('ksu', () => expect(patchScript(RootFamily.ksu, 'init_boot.img'), golden('patch_ksu.sh')));
    test('应用列表', () => expect(appListScript('$remoteDir/aapt2', '999'), golden('app_list.sh')));
  });

  test('shq 转义单引号', () {
    expect(shq("a'b"), r"'a'\''b'");
  });

  test('parseAdbDevices', () {
    final list = parseAdbDevices('List of devices attached\r\nabc123\tdevice\r\nxyz\tunauthorized\r\nq\toffline\r\n');
    expect(list.map((d) => (d.serial, d.mode)), [('abc123', DeviceMode.system), ('xyz', DeviceMode.unauthorized)]);
  });

  test('parseFastbootDevices', () {
    expect(parseFastbootDevices('a1b2c3\tfastboot\r\n').single.serial, 'a1b2c3');
  });

  test('parseGetprop', () {
    final props = parseGetprop('[ro.product.model]: [CPH2653]\r\n[ro.boot.slot_suffix]: [_a]\r\n[empty]: []\n');
    expect(props, {'ro.product.model': 'CPH2653', 'ro.boot.slot_suffix': '_a', 'empty': ''});
  });

  test('parseGetvar', () {
    expect(parseGetvar('current-slot: b\r\nFinished. Total time: 0.001s\r\n', 'current-slot'), 'b');
    expect(parseGetvar('current-slot: \nFinished.', 'current-slot'), isNull);
  });

  test('parseUnlocked', () {
    expect(parseUnlocked(deviceInfo: '(bootloader) Device unlocked: true'), isTrue);
    expect(parseUnlocked(deviceInfo: '(bootloader) Device unlocked: false'), isFalse);
    expect(parseUnlocked(deviceInfo: 'FAILED', getvarUnlocked: 'yes'), isTrue);
    expect(parseUnlocked(deviceInfo: 'FAILED'), isNull);
  });

  test('parseAppListing', () {
    final l = parseAppListing('APP|com.a|/data/app/a/base.apk|res/icon.png|微信|x\n'
        'APP|com.b|/data/app/b/base.apk||\n'
        'CLONED|com.a\n');
    expect(l.apps.first.label, '微信|x');
    expect(l.apps.first.iconPath, 'res/icon.png');
    expect(l.apps.last.label, 'com.b');
    expect(l.apps.last.iconPath, isNull);
    expect(l.clonedPackages, {'com.a'});
  });

  test('SevenZip.listContains', () {
    const listing = '2024-01-01 00:00:00 ....A     100   50  boot.img\r\n'
        '2024-01-01 00:00:00 ....A     100   50  vendor_boot.img\r\n';
    expect(SevenZip.listContains(listing, 'boot.img'), isTrue);
    expect(SevenZip.listContains(listing, 'init_boot.img'), isFalse);
  });

  group('exec', () {
    test('收集输出和退出码', () async {
      final r = await exec('cmd', ['/c', 'echo hello & exit 3']);
      expect(r.code, 3);
      expect(r.stdout.trim(), 'hello');
    }, testOn: 'windows');

    test('取消时结束进程', () async {
      final token = CancelToken();
      final f = exec('ping', ['-n', '30', '127.0.0.1'], cancel: token);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      token.cancel();
      await expectLater(f, throwsA(isA<CancelledException>()));
    }, testOn: 'windows');

    test('超时返回 -1', () async {
      final r = await exec('ping', ['-n', '30', '127.0.0.1'], timeout: const Duration(milliseconds: 300));
      expect(r.code, -1);
      expect(r.all, contains('[超时]'));
    }, testOn: 'windows');
  });
}
