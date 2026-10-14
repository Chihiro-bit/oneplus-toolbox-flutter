import 'package:test/test.dart';
import 'package:toolbox_core/toolbox_core.dart';

Map<String, Object?> scheme([Map<String, Object?> override = const {}]) => {
      'id': 'magisk',
      'name': 'Magisk',
      'family': 'magisk',
      'version': '31.0',
      'package': 'com.topjohnwu.magisk',
      'apk': {'url': 'https://example.com/m.apk', 'sha256': 'A' * 64, 'size': 1024},
      ...override,
    };

void main() {
  group('validateCatalog', () {
    test('接受合法目录并把 sha256 转成小写', () {
      final c = validateCatalog({
        'schemaVersion': 1,
        'schemes': [scheme()],
      });
      expect(c.schemes.single.apk.sha256, 'a' * 64);
      expect(c.schemes.single.apk.size, 1024);
    });

    test('拒绝非 https 下载地址', () {
      expect(
        () => validateCatalog({
          'schemaVersion': 1,
          'schemes': [
            scheme({
              'apk': {'url': 'http://example.com/m.apk', 'sha256': 'a' * 64}
            })
          ],
        }),
        throwsA(isA<CatalogFormatException>()),
      );
    });

    test('拒绝未知的修补方式', () {
      expect(
        () => validateCatalog({
          'schemaVersion': 1,
          'schemes': [
            scheme({'family': 'script'})
          ],
        }),
        throwsA(isA<CatalogFormatException>()),
      );
    });

    test('丢弃非 https 的主页', () {
      final c = validateCatalog({
        'schemaVersion': 1,
        'schemes': [
          scheme({'homepage': 'javascript:alert(1)'})
        ],
      });
      expect(c.schemes.single.homepage, isNull);
    });
  });

  test('mergeCatalog 覆盖同 id，保留内置离线方案', () {
    final merged = mergeCatalog(validateCatalog({
      'schemaVersion': 1,
      'schemes': [
        scheme(),
        scheme({'id': 'magisk-bundled'}),
        scheme({'id': 'new-one'}),
      ],
    }));
    expect(merged.firstWhere((s) => s.id == 'magisk').version, '31.0');
    expect(merged.firstWhere((s) => s.id == 'magisk-bundled').apk.bundled, isTrue);
    expect(merged.last.id, 'new-one');
  });

  test('superkeyProblem', () {
    expect(superkeyProblem(''), isNotNull);
    expect(superkeyProblem('abc123'), '至少 8 位');
    expect(superkeyProblem('abcdefgh'), '必须同时包含字母和数字');
    expect(superkeyProblem("abcd1234'"), isNotNull);
    expect(superkeyProblem('abcd1234'), isNull);
  });

  test('isOnePlus', () {
    expect(const DeviceInfo(mode: DeviceMode.fastboot).isOnePlus, isNull);
    expect(const DeviceInfo(mode: DeviceMode.system, brand: 'OnePlus').isOnePlus, isTrue);
    expect(const DeviceInfo(mode: DeviceMode.system, brand: 'OPPO', manufacturer: 'OPPO').isOnePlus, isFalse);
  });
}
