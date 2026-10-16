import 'package:test/test.dart';
import 'package:toolbox_service/src/update_checker.dart';

void main() {
  /// 移植 TS 版 test/parsers.test.ts 里 newer() 的用例
  group('isNewerVersion', () {
    test('按数字逐段比较，忽略前缀 v', () {
      expect(isNewerVersion('0.2.0', '0.1.0'), isTrue);
      expect(isNewerVersion('v0.1.10', '0.1.9'), isTrue);
      expect(isNewerVersion('0.1.0', '0.1.0'), isFalse);
      expect(isNewerVersion('0.1', '0.1.0'), isFalse);
      expect(isNewerVersion('0.1.0', '0.2.0'), isFalse);
    });

    test('预发布后缀按段比较', () {
      expect(isNewerVersion('1.0.0-2', '1.0.0'), isTrue);
      expect(isNewerVersion('v0.2.0', '0.1.9'), isTrue);
    });
  });

  group('canAutoUpdate', () {
    test('免安装发布包（对应 TS 版的便携版）不能自动下载替换', () {
      expect(canAutoUpdate(), isFalse);
    });

    test('未配置仓库时报错与 TS 版一致，canAuto 仍带在结果里', () async {
      final u = await checkUpdate(current: '0.1.0', repo: '');
      expect(u.current, '0.1.0');
      expect(u.error, '未配置更新仓库');
      expect(u.hasUpdate, isFalse);
      expect(u.latest, isNull);
      expect(u.url, isNull);
      expect(u.canAuto, isFalse);
    });
  });
}
