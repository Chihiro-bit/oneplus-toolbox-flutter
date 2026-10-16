import 'package:test/test.dart';
import 'package:toolbox_core/toolbox_core.dart';

/// 对应 TS 版的 test/permissions.test.ts
const dump = '''Packages:
  Package [net.dinglisch.android.taskerm] (a1b2c3):
    versionName=6.5.11
    requested permissions:
      android.permission.WRITE_SECURE_SETTINGS
      android.permission.READ_LOGS
      android.permission.READ_SMS: restricted=true
      android.permission.INTERNET
    install permissions:
      android.permission.INTERNET: granted=true
    User 0: ceDataInode=1 installed=true
      runtime permissions:
        android.permission.WRITE_SECURE_SETTINGS: granted=true, flags=[ USER_SET ]
        android.permission.READ_LOGS: granted=false, flags=[ USER_SET ]
''';

void main() {
  group('parsePackagePermissions', () {
    test('申请的权限和已授予的权限', () {
      final parsed = parsePackagePermissions(dump);
      expect(parsed.requested, [
        'android.permission.WRITE_SECURE_SETTINGS',
        'android.permission.READ_LOGS',
        'android.permission.READ_SMS',
        'android.permission.INTERNET',
      ]);
      expect(
          parsed.granted.toList()..sort(), ['android.permission.INTERNET', 'android.permission.WRITE_SECURE_SETTINGS']);
    });

    test('只看用户 0（一加 13 实测：其它用户另起一行带 userId）', () {
      final out = [
        '    install permissions:',
        '      android.permission.WRITE_SECURE_SETTINGS: granted=false',
        '      android.permission.WRITE_SECURE_SETTINGS: granted=true, userId=10',
        '      android.permission.DUMP: granted=true',
        '      android.permission.DUMP: granted=false, userId=999',
      ].join('\n');
      expect(parsePackagePermissions(out).granted.toList(), ['android.permission.DUMP']);
    });

    test('只认 development 权限', () {
      expect(isGrantable('android.permission.WRITE_SECURE_SETTINGS'), isTrue);
      expect(isGrantable('android.permission.READ_SMS'), isFalse);
      expect(isGrantable('toString'), isFalse);
    });
  });
}
