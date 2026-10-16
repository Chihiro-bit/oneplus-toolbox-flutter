import 'dart:io';

import 'package:test/test.dart';
import 'package:toolbox_commands/toolbox_commands.dart';
import 'package:toolbox_core/toolbox_core.dart';

/// golden/ 下的文件由 TS 版生成，保证两个版本发到手机上的脚本完全一致
String golden(String name) => File('test/golden/$name').readAsStringSync();

/// ColorOS / 氧 OS 的分身空间固定是用户 999
const cloneUser = '999';

void main() {
  group('手机端脚本与 TS 版一致', () {
    test('magisk', () => expect(patchScript(RootFamily.magisk, 'init_boot.img'), golden('patch_magisk.sh')));
    test('apatch',
        () => expect(patchScript(RootFamily.apatch, 'boot.img', superkey: 'abc123XY'), golden('patch_apatch.sh')));
    test('ksu', () => expect(patchScript(RootFamily.ksu, 'init_boot.img'), golden('patch_ksu.sh')));
    test(
        '应用列表（第三方，标出已双开）',
        () => expect(
            appListScript('pm list packages -3 -f', listClonedPackagesScript(cloneUser)), golden('app_list.sh')));
    test(
        '预装应用列表（标出已卸载 / 已停用）',
        () => expect(
            appListScript('pm list packages -s -u -f', [
              ...listInstalledSystemPackagesScript(),
              ...listDisabledSystemPackagesScript(),
            ]),
            golden('app_list_system.sh')));
    test(
        '冻结与权限的应用列表（标出已冻结）',
        () => expect(appListScript('pm list packages -3 -f', listDisabledUserPackagesScript()),
            golden('app_list_user_frozen.sh')));
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
    expect(l.apps.first.apkPath, '/data/app/a/base.apk');
    expect(l.apps.first.iconPath, 'res/icon.png');
    expect(l.apps.last.label, 'com.b');
    expect(l.apps.last.iconPath, isNull);
    expect(l.mark(clonedMark), {'com.a'});
    expect(l.mark(installedMark), isEmpty);
  });

  test('componentPackage / resolvedActivityPackage', () {
    expect(componentPackage('com.baidu.input/.ImeService\n'), 'com.baidu.input');
    expect(componentPackage('null\n'), isNull);
    expect(componentPackage(''), isNull);
    expect(
        resolvedActivityPackage('priority=0 preferredOrder=0\n'
            'com.android.launcher/.Launcher\n'),
        'com.android.launcher');
    expect(resolvedActivityPackage(''), isNull);
  });

  group('应用数据脚本', () {
    test('打包脚本与 TS 版一致', () {
      expect(
        dataBackupScript(root: '/data/data', pkg: 'com.example.app', remote: '$remoteDir/data.tgz'),
        '[ -d /data/data/com.example.app ] || { echo NO_DIR; exit 0; }; '
        'cd /data/data && tar -czf $remoteDir/data.tgz '
        '--exclude=com.example.app/cache --exclude=com.example.app/code_cache --exclude=com.example.app/lib '
        'com.example.app && chmod 644 $remoteDir/data.tgz && echo TAR_OK',
      );
    });

    test('解包脚本与 TS 版一致', () {
      expect(
        dataRestoreScript(root: '/data/data', pkg: 'com.example.app', remote: '$remoteDir/data.tgz'),
        '[ -d /data/data/com.example.app ] || { echo NO_DIR; exit 0; }\n'
        'U=\$(stat -c %u /data/data/com.example.app)\n'
        'find /data/data/com.example.app -mindepth 1 -maxdepth 1 ! -name cache ! -name code_cache ! -name lib -exec rm -rf {} +\n'
        'tar -xzf $remoteDir/data.tgz -C /data/data || exit 1\n'
        'chown -R \$U:\$U /data/data/com.example.app\n'
        'restorecon -RF /data/data/com.example.app\n'
        'echo RESTORE_OK',
      );
    });

    test('checkArchive 只接受该应用目录下的条目', () {
      expect(checkArchive('com.a/\ncom.a/shared_prefs/x.xml\n', 'com.a'), isTrue);
      expect(checkArchive('com.a\n', 'com.a'), isTrue);
      expect(checkArchive('com.b/x\n', 'com.a'), isFalse);
      expect(checkArchive('com.a/../com.b/x\n', 'com.a'), isFalse);
      expect(checkArchive('', 'com.a'), isFalse);
    });
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
