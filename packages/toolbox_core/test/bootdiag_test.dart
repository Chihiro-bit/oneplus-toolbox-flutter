import 'package:test/test.dart';
import 'package:toolbox_core/toolbox_core.dart';

// 一加 13（2026-10-15 实测）bootloader 下 getvar all 的节选
const _bootloaderAll = '''
(bootloader) snapshot-update-status:none
(bootloader) parallel-download-flash:yes
(bootloader) unlocked:yes
(bootloader) erase-block-size: 0x1000
(bootloader) current-slot:a
(bootloader) slot-retry-count:b:7
(bootloader) slot-unbootable:b:yes
(bootloader) slot-successful:b:yes
(bootloader) slot-retry-count:a:6
(bootloader) slot-unbootable:a:no
(bootloader) slot-successful:a:yes
(bootloader) product:sun
(bootloader) is-userspace:no
(bootloader) version-bootloader:
all:
Finished. Total time: 0.059s''';

// 同一台手机 fastbootd 下的节选：slot-* 只能单独查询，successful 与 bootloader 相反
const _fastbootdAll = '''
(bootloader) snapshot-update-status:none
(bootloader) is-userspace:yes
(bootloader) partition-size:boot_a:0x6000000
(bootloader) is-logical:system_a:yes
(bootloader) vendor-fingerprint:oplus/ossi/ossi:15/AP3A.240617.008/1785725844921:user/release-keys
(bootloader) current-slot:a
(bootloader) slot-successful:a:no
(bootloader) slot-unbootable:b:yes
(bootloader) version-bootloader:unknown''';

void main() {
  group('parseGetvarAll', () {
    final v = parseGetvarAll(_bootloaderAll);

    test('普通变量', () {
      expect(v['current-slot'], 'a');
      expect(v['product'], 'sun');
      expect(v['erase-block-size'], '0x1000');
      expect(v['version-bootloader'], '');
    });

    test('带槽位子键的变量', () {
      expect(v['slot-retry-count:b'], '7');
      expect(v['slot-unbootable:a'], 'no');
    });

    test('值里带冒号的不被切开', () {
      final d = parseGetvarAll(_fastbootdAll);
      expect(d['vendor-fingerprint'], 'oplus/ossi/ossi:15/AP3A.240617.008/1785725844921:user/release-keys');
      expect(d['partition-size:boot_a'], '0x6000000');
      expect(d['is-logical:system_a'], 'yes');
    });
  });

  group('slotsFromVars', () {
    test('bootloader 下全部可读', () {
      final slots = slotsFromVars(parseGetvarAll(_bootloaderAll), false);
      expect(slots.length, 2);
      expect(slots['a']!.successful, isTrue);
      expect(slots['a']!.unbootable, isFalse);
      expect(slots['a']!.retryCount, 6);
      expect(slots['b']!.successful, isTrue);
      expect(slots['b']!.unbootable, isTrue);
      expect(slots['b']!.retryCount, 7);
    });

    test('fastbootd 下丢弃 slot-successful', () {
      final slots = slotsFromVars(parseGetvarAll(_fastbootdAll), true);
      expect(slots.length, 1);
      expect(slots['b']!.successful, isNull);
      expect(slots['b']!.unbootable, isTrue);
      expect(slots['b']!.retryCount, isNull);
    });
  });

  group('parseCriticalUnlocked', () {
    test('解析 oem device-info', () {
      const out = '(bootloader) Verity mode: true\n'
          '(bootloader) Device unlocked: true\n'
          '(bootloader) Device critical unlocked: false\n'
          'OKAY';
      expect(parseCriticalUnlocked(out), isFalse);
    });

    test('fastbootd 下不支持', () {
      expect(parseCriticalUnlocked("FAILED (remote: 'Unable to do OEM command')"), isNull);
    });
  });

  // ───────────── 诊断规则 ─────────────

  List<Finding> run({
    BootState? state,
    List<BootSymptom> symptoms = const [],
    LastAction lastAction = LastAction.unknown,
    FlashRecord? lastFlash,
    bool canUndo = false,
  }) =>
      diagnose(DiagnoseInput(
        state: state ?? healthy(),
        symptoms: symptoms,
        lastAction: lastAction,
        lastFlash: lastFlash,
        canUndo: canUndo,
      ));

  List<String> ids({
    BootState? state,
    List<BootSymptom> symptoms = const [],
    LastAction lastAction = LastAction.unknown,
    FlashRecord? lastFlash,
    bool canUndo = false,
  }) =>
      [
        for (final f in run(
          state: state,
          symptoms: symptoms,
          lastAction: lastAction,
          lastFlash: lastFlash,
          canUndo: canUndo,
        ))
          f.id,
      ];

  List<FixKind> kinds(Finding f) => [for (final x in f.fixes) x.kind];

  group('diagnose', () {
    test('上锁时只给清数据和售后', () {
      final f = run(
        state: healthy(unlocked: false),
        lastAction: LastAction.root,
        symptoms: [BootSymptom.crashdump],
      );
      expect([for (final x in f) x.id], ['locked']);
      expect(kinds(f[0]), [FixKind.wipeData, FixKind.service]);
    });

    test('Root 后 CrashDump：高可信，优先撤销上一次刷写', () {
      final top = run(
        lastAction: LastAction.root,
        symptoms: [BootSymptom.crashdump],
        lastFlash: rootRecord(),
        canUndo: true,
      ).first;
      expect(top.id, 'patched-image');
      expect(top.confidence, Confidence.high);
      expect(kinds(top), [FixKind.undoFlash, FixKind.unroot]);
    });

    test('Root 后当前槽位被标为不可启动：高可信', () {
      final st = healthy(slots: {
        'a': const SlotState(successful: false, unbootable: true, retryCount: 0),
        'b': const SlotState(successful: true, unbootable: true, retryCount: 7),
      });
      final top = run(state: st, lastAction: LastAction.root, symptoms: [BootSymptom.logo])[0];
      expect(top.id, 'patched-image');
      expect(top.confidence, Confidence.high);
    });

    test('没有备份时不提供撤销', () {
      final f =
          run(lastAction: LastAction.root, symptoms: [BootSymptom.logo]).firstWhere((x) => x.id == 'patched-image');
      expect(f.confidence, Confidence.medium);
      expect(kinds(f), [FixKind.unroot]);
    });

    test('用户没选操作时，用没撤销的 Root 记录推断', () {
      expect(ids(lastFlash: rootRecord(), symptoms: [BootSymptom.logo]), contains('patched-image'));
      expect(ids(lastFlash: rootRecord(undone: true), symptoms: [BootSymptom.logo]), isNot(contains('patched-image')));
    });

    test('另一个槽位被 OTA 标为不可启动是正常的，不单独报故障', () {
      expect(ids(symptoms: [BootSymptom.logo]), ['unknown']);
    });

    test('装模块后卡开机且 adb 能连上：高可信', () {
      final f = run(
        state: healthy(mode: DeviceMode.system, adbDuringBoot: true, root: 'Magisk 30.7'),
        lastAction: LastAction.module,
        symptoms: [BootSymptom.bootloop],
      );
      expect(f[0].id, 'module');
      expect(f[0].confidence, Confidence.high);
      expect(kinds(f[0]), [FixKind.modulesDisable, FixKind.modulesRemove, FixKind.safeMode]);
    });

    test('没选操作但 adb 在开机时连上且已 Root：低可信地怀疑模块', () {
      final f = run(
        state: healthy(adbDuringBoot: true, root: 'KernelSU 3.3.1'),
        symptoms: [BootSymptom.logo],
      );
      expect(f.firstWhere((x) => x.id == 'module').confidence, Confidence.low);
    });

    test('image destroyed → vbmeta', () {
      final top = run(symptoms: [BootSymptom.destroyed])[0];
      expect(top.id, 'vbmeta');
      expect(top.confidence, Confidence.high);
    });

    test('更新还没合并：snapshotted 给取消，merging 给继续合并', () {
      final snapped = run(state: healthy(snapshotStatus: 'snapshotted'), lastAction: LastAction.flash)
          .firstWhere((x) => x.id == 'snapshot');
      expect(snapped.confidence, Confidence.high);
      expect(snapped.fixes[0].kind, FixKind.snapshotCancel);
      final merging = run(state: healthy(snapshotStatus: 'merging')).firstWhere((x) => x.id == 'snapshot');
      expect(merging.fixes[0].kind, FixKind.snapshotMerge);
    });

    test('刷系统后：另一个槽位完好才建议切换，否则完整线刷', () {
      final st = healthy(slots: {
        'a': const SlotState(successful: false, unbootable: true),
        'b': const SlotState(successful: true, unbootable: false),
      });
      final usable = run(state: st, lastAction: LastAction.flash).firstWhere((x) => x.id == 'slots');
      expect(kinds(usable), [FixKind.switchSlot, FixKind.fullFlash]);
      // 实测状态：b 槽不可启动，不能切过去
      final notUsable = run(lastAction: LastAction.flash).firstWhere((x) => x.id == 'slots');
      expect(kinds(notUsable), [FixKind.fullFlash]);
    });

    test('fastbootd 下读不到 successful 时，不建议切换槽位', () {
      final st = healthy(mode: DeviceMode.fastbootd, slots: {
        'a': const SlotState(unbootable: true),
        'b': const SlotState(unbootable: false),
      });
      final f = run(state: st, lastAction: LastAction.ota).firstWhere((x) => x.id == 'slots');
      expect(kinds(f), [FixKind.fullFlash]);
    });

    test('自动进 Recovery → 清除数据', () {
      final f = run(symptoms: [BootSymptom.recovery], lastAction: LastAction.flash).firstWhere((x) => x.id == 'data');
      expect(f.confidence, Confidence.high);
    });

    test('结果按可信度排序', () {
      final f = run(
        state: healthy(adbDuringBoot: true, root: 'Magisk 30.7'),
        symptoms: [BootSymptom.logo, BootSymptom.destroyed],
      );
      expect([for (final x in f) x.confidence], [Confidence.high, Confidence.low]);
    });
  });

  group('guessLastAction', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    test('一天内的 Root 记录', () => expect(guessLastAction(rootRecord(time: now - 1000), now), LastAction.root));
    test('太久以前的不算', () => expect(guessLastAction(rootRecord(time: now - 2 * 86400000), now), LastAction.unknown));
    test('撤销过的不算', () => expect(guessLastAction(rootRecord(undone: true), now), LastAction.unknown));
  });
}

/// 实测的正常状态：a 槽在用，b 槽被 OTA 标为不可启动
BootState healthy({
  DeviceMode mode = DeviceMode.fastboot,
  Map<String, SlotState>? slots,
  bool? unlocked = true,
  bool? criticalUnlocked = false,
  String? snapshotStatus = 'none',
  bool? adbDuringBoot,
  bool? bootCompleted,
  String? crashLog,
  String? root,
  List<String> notes = const [],
}) =>
    BootState(
      mode: mode,
      serial: 'x',
      currentSlot: 'a',
      slots: slots ??
          const {
            'a': SlotState(successful: true, unbootable: false, retryCount: 6),
            'b': SlotState(successful: true, unbootable: true, retryCount: 7),
          },
      unlocked: unlocked,
      criticalUnlocked: criticalUnlocked,
      snapshotStatus: snapshotStatus,
      adbDuringBoot: adbDuringBoot,
      bootCompleted: bootCompleted,
      crashLog: crashLog,
      root: root,
      notes: notes,
    );

FlashRecord rootRecord({bool undone = false, int? time}) => FlashRecord(
      id: 'r1',
      time: time ?? DateTime.now().millisecondsSinceEpoch - 3600000,
      serial: 'x',
      kind: FlashKind.root,
      scheme: 'Magisk',
      slot: 'a',
      build: const FlashBuild(buildDateUtc: '1785725844'),
      partitions: const [FlashPartition(name: 'init_boot', source: FlashSource.patched, sha256: 'aa')],
      backups: const {'init_boot': FlashBackup(path: r'C:\b\init_boot.img', sha256: 'bb')},
      status: FlashStatus.ok,
      undone: undone,
    );
