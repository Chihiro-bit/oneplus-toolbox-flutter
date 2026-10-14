import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:toolbox_service/src/catalog_repository.dart';
import 'package:toolbox_service/src/ops/op_exception.dart';
import 'package:toolbox_service/src/ops/root.dart';
import 'package:toolbox_service/src/settings_store.dart';
import 'package:toolbox_service/toolbox_service.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('toolbox_service_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  ToolboxEnvironment env() => ToolboxEnvironment(
        binDir: p.join(tmp.path, 'bin'),
        dataDir: p.join(tmp.path, 'data'),
        tempDir: p.join(tmp.path, 'temp'),
        documentsDir: p.join(tmp.path, 'docs'),
        appVersion: '0.1.0',
      );

  group('choosePartition', () {
    test('自动：有 init_boot 就修补它', () {
      expect(choosePartition(RootFamily.magisk, PatchTarget.auto, hasInitBoot: true), Partition.initBoot);
      expect(choosePartition(RootFamily.ksu, PatchTarget.auto, hasInitBoot: false), Partition.boot);
    });

    test('APatch 固定 boot，指定 init_boot 时报错', () {
      expect(choosePartition(RootFamily.apatch, PatchTarget.auto, hasInitBoot: true), Partition.boot);
      expect(() => choosePartition(RootFamily.apatch, PatchTarget.initBoot, hasInitBoot: true),
          throwsA(isA<OpException>()));
    });

    test('手动指定', () {
      expect(choosePartition(RootFamily.magisk, PatchTarget.boot, hasInitBoot: true), Partition.boot);
      expect(choosePartition(RootFamily.magisk, PatchTarget.initBoot, hasInitBoot: false), Partition.initBoot);
    });
  });

  test('patchedFileName', () {
    expect(
      patchedFileName('Magisk（内置）', Partition.initBoot, 'OP5D0DL1', DateTime(2026, 10, 14, 9, 5, 7)),
      'Magisk__patched_init_boot_OP5D0DL1_20261014090507.img',
    );
  });

  test('isNewerVersion', () {
    expect(isNewerVersion('v0.2.0', '0.1.9'), isTrue);
    expect(isNewerVersion('0.1.0', '0.1.0'), isFalse);
    expect(isNewerVersion('0.1', '0.1.1'), isFalse);
    expect(isNewerVersion('1.0.0-2', '1.0.0'), isTrue);
  });

  group('SettingsStore', () {
    test('没有文件时用默认值', () {
      final s = SettingsStore(tmp.path, defaultUpdateRepo: 'a/b').load();
      expect(s.catalogUrl, '');
      expect(s.updateRepo, 'a/b');
    });

    test('保存时清理 GitHub 地址', () {
      final store = SettingsStore(tmp.path);
      final saved =
          store.save(const Settings(catalogUrl: ' https://x.com/c.json ', updateRepo: 'https://github.com/o/r/'));
      expect(saved.catalogUrl, 'https://x.com/c.json');
      expect(saved.updateRepo, 'o/r');
      expect(store.load().updateRepo, 'o/r');
    });

    test('拒绝非 https 目录和错误的仓库格式', () {
      final store = SettingsStore(tmp.path);
      expect(() => store.save(const Settings(catalogUrl: 'http://x.com/c.json')), throwsA(isA<SettingsException>()));
      expect(() => store.save(const Settings(updateRepo: 'not a repo')), throwsA(isA<SettingsException>()));
    });

    test('与 TS 版的 settings.json 格式兼容', () {
      File(p.join(tmp.path, 'settings.json'))
          .writeAsStringSync(jsonEncode({'catalogUrl': 'https://x.com/c.json', 'updateRepo': 'o/r'}));
      expect(SettingsStore(tmp.path).load().catalogUrl, 'https://x.com/c.json');
    });
  });

  group('CatalogRepository', () {
    test('未配置远程地址时使用内置目录', () async {
      final repo = CatalogRepository(tmp.path, SettingsStore(tmp.path));
      final c = await repo.get();
      expect(c.source, CatalogSource.builtin);
      expect(c.error, isNull);
      expect((await repo.find('magisk-bundled'))?.apk.bundled, isTrue);
      expect(await repo.find('nope'), isNull);
    });

    test('远程读取失败时退回本地缓存', () async {
      final settings = SettingsStore(tmp.path)..save(const Settings(catalogUrl: 'https://127.0.0.1:1/catalog.json'));
      File(p.join(tmp.path, 'catalog-cache.json')).writeAsStringSync(jsonEncode({
        'schemaVersion': 1,
        'schemes': [
          {
            'id': 'extra',
            'name': 'Extra',
            'family': 'ksu',
            'version': '1',
            'package': 'a.b',
            'apk': {'url': 'https://example.com/a.apk', 'sha256': 'a' * 64},
          }
        ],
      }));
      final c = await CatalogRepository(tmp.path, settings).get();
      expect(c.source, CatalogSource.cache);
      expect(c.error, startsWith('远程目录读取失败'));
      expect(c.schemes.last.id, 'extra');
    });
  });

  group('ToolboxService', () {
    test('缺少工具时操作返回失败结果而不是抛出', () async {
      final service = ToolboxService(env());
      final logs = <LogEntry>[];
      service.logs.listen(logs.add);
      final r = await service.run(const RebootRequest(RebootTarget.system));
      expect(r.ok, isFalse);
      expect(r.message, startsWith('发生错误'));
      expect(service.busy, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(logs.first.text, contains('重启到'));
      service.dispose();
    });

    test('missing tools 在启动时写入日志', () async {
      final service = ToolboxService(env());
      final logs = <LogEntry>[];
      service.logs.listen(logs.add);
      service.start();
      await Future<void>.delayed(Duration.zero);
      expect(logs.single.level, LogLevel.error);
      expect(logs.single.text, contains('adb'));
      service.dispose();
    });
  });
}
