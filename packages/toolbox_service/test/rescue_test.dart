import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:toolbox_commands/toolbox_commands.dart';
import 'package:toolbox_core/toolbox_core.dart';
import 'package:toolbox_service/src/device_probe.dart';
import 'package:toolbox_service/src/environment.dart';
import 'package:toolbox_service/src/history.dart';
import 'package:toolbox_service/src/known.dart';
import 'package:toolbox_service/src/logfile.dart';
import 'package:toolbox_service/src/ops/backup.dart';
import 'package:toolbox_service/src/ops/context.dart';
import 'package:toolbox_service/src/ops/rescue.dart';
import 'package:toolbox_service/src/ops/root.dart';

/// 「救援与恢复」「备份关键分区」里新增的纯函数与解析。
/// 脚本字符串都写死在断言里，防止以后改写时和 TS 版不再一致。
void main() {
  group('模块救援脚本（与 TS 版逐字一致）', () {
    test('禁用：给每个模块写 disable 标记', () {
      expect(
        modulesSuScript(ModuleAction.disable),
        r'n=0; for m in /data/adb/modules/*; do [ -d "$m" ] || continue; touch "$m/disable" && n=$((n+1)) && echo "MOD|${m##*/}"; done; echo "RESULT|$n"',
      );
    });

    test('启用：删掉 disable 标记', () {
      expect(
        modulesSuScript(ModuleAction.enable),
        r'n=0; for m in /data/adb/modules/*; do [ -f "$m/disable" ] || continue; rm -f "$m/disable" && n=$((n+1)) && echo "MOD|${m##*/}"; done; echo "RESULT|$n"',
      );
    });

    test('删除不走 su 脚本', () => expect(modulesSuScript(ModuleAction.remove), isNull));

    test('完整命令行：timeout 30 su -c … 2>&1', () {
      final script = modulesSuScript(ModuleAction.disable)!;
      expect(modulesShellCommand(ModuleAction.disable), "timeout 30 su -c '$script' 2>&1");
      expect(modulesShellCommand(ModuleAction.remove), isNull);
    });

    test('删除模块用的官方救砖命令', () {
      expect(removeModulesCommand, 'command -v magisk >/dev/null && magisk --remove-modules || echo NO_MAGISK');
      expect(noMagiskMarker, 'NO_MAGISK');
    });

    test('解析 RESULT|n', () {
      expect(parseModulesResult('MOD|a\nMOD|b\nRESULT|2\n'), 2);
      expect(parseModulesResult('RESULT|0\r\n'), 0);
      expect(parseModulesResult('su: not found\nRESULT|12'), 12);
      expect(parseModulesResult('Permission denied'), isNull);
      expect(parseModulesResult(''), isNull);
    });

    test('安全模式提示文案', () {
      expect(
        safeModeTip,
        'KernelSU / APatch 可以进安全模式（所有模块临时失效）：开机过程中出现第一屏后连续按几次音量下键；Magisk 的安全模式是开机时一直按住音量下键',
      );
    });

    test('模块目录', () => expect(modulesDir, '/data/adb/modules'));
  });

  group('备份脚本（与 TS 版逐字一致）', () {
    test('拿 Root 权限的探测命令', () => expect(suIdCommand, "timeout 30 su -c 'id -u' 2>&1"));

    test('列出手机上存在的分区', () {
      expect(
        listPartitionsCommand(const ['persist', 'modemst1']),
        "su -c 'for p in persist modemst1; do [ -e /dev/block/by-name/\$p ] && echo \"HAS|\$p\"; done'",
      );
    });

    test('解析 HAS| 输出', () {
      expect(parsePresentPartitions('HAS|persist\nHAS|fsg\r\nNO|nope\n'), ['persist', 'fsg']);
      expect(parsePresentPartitions(''), isEmpty);
    });

    test('备份用的远程目录与清理命令', () {
      const remote = '/data/local/tmp/oneplus-toolbox/backup';
      expect(backupRemote, remote);
      expect(resetRemoteCommand(remote), 'rm -rf $remote && mkdir -p $remote');
      expect(removeRemoteDirCommand(remote), 'rm -rf $remote');
      expect(removeRemoteImageCommand(remote, 'persist'), 'rm -f $remote/persist.img');
    });

    test('dd 读出分区并改成所有人可读', () {
      expect(
        ddCommand('/data/local/tmp/oneplus-toolbox/backup', 'persist'),
        "su -c 'dd if=/dev/block/by-name/persist of=/data/local/tmp/oneplus-toolbox/backup/persist.img bs=1048576 2>&1 && chmod 644 /data/local/tmp/oneplus-toolbox/backup/persist.img'",
      );
    });

    test('SHA256SUMS.txt 的内容', () {
      expect(
        sha256Sums(header: '# CPH2653 CPH2653_16.0.1 2026/10/15 12:30:45', lines: ['ab  persist.img  4096']),
        '# CPH2653 CPH2653_16.0.1 2026/10/15 12:30:45\nab  persist.img  4096\n',
      );
      expect(sha256Sums(header: '# x', lines: const []), '# x\n');
    });

    test('清单里的一行', () => expect(manifestLine('ab', 'persist.img', 4096), 'ab  persist.img  4096'));

    test('备份目录的时间戳用 UTC（与 TS 的 toISOString 一致）', () {
      expect(backupStamp(DateTime.utc(2026, 10, 15, 12, 30, 45, 123)), '20261015123045');
    });

    test('要备份的分区清单', () {
      expect(uniquePartitions, ['persist', 'modemst1', 'modemst2', 'fsg', 'fsc', 'ocdt']);
      expect(slotPartitions, ['boot', 'init_boot', 'vendor_boot', 'dtbo']);
      expect([
        for (final x in romPartitions) x.id
      ], [
        'init_boot',
        'boot',
        'vendor_boot',
        'dtbo',
        'vbmeta',
        'vbmeta_system',
        'vbmeta_vendor',
      ]);
    });
  });

  group('刷回原厂', () {
    test('可刷回的分区就是那 7 个物理分区', () {
      expect([
        for (final x in stockPartitions) x.id
      ], [
        'init_boot',
        'boot',
        'vendor_boot',
        'dtbo',
        'vbmeta',
        'vbmeta_system',
        'vbmeta_vendor',
      ]);
    });

    test('日期格式与 TS 的 toLocaleString(zh-CN, hour12:false) 一致', () {
      expect(formatDateTime(DateTime(2026, 10, 15, 14, 30, 5).millisecondsSinceEpoch), '2026/10/15 14:30:05');
      expect(formatDateTime(DateTime(2026, 1, 2, 3, 4, 5).millisecondsSinceEpoch), '2026/1/2 03:04:05');
    });

    test('工作目录每次重建', () {
      final ctx = _context();
      final dir = workDir(ctx.env);
      File(p.join(dir, 'x.img')).writeAsStringSync('x');
      expect(File(p.join(dir, 'x.img')).existsSync(), isTrue);
      expect(workDir(ctx.env), dir);
      expect(File(p.join(dir, 'x.img')).existsSync(), isFalse);
    });

    test('在目录里递归找镜像（跳过空文件）', () {
      final dir = Directory.systemTemp.createTempSync('toolbox_find');
      addTearDown(() => dir.deleteSync(recursive: true));
      final sub = Directory(p.join(dir.path, 'payload'))..createSync();
      File(p.join(sub.path, 'boot.img')).writeAsStringSync('boot');
      File(p.join(dir.path, 'init_boot.img')).writeAsStringSync('');
      expect(findFile(dir.path, 'boot.img'), p.join(sub.path, 'boot.img'));
      expect(findFile(dir.path, 'init_boot.img'), isNull);
      expect(findFile(dir.path, 'nope.img'), isNull);
    });
  });

  group('backupPartitions', () {
    test('source=rom 但没选 ROM 时直接拒绝，不碰设备', () {
      expect(
        backupPartitions(const BackupOptions(source: BackupSource.rom, rom: '  '), _context()),
        throwsA(isA<OpException>().having((e) => e.message, 'message', '请先选择 ROM')),
      );
    });
  });
}

/// 一个不连设备的最小上下文（只用于走到「参数校验就返回」的路径）
OpContext _context() {
  final tmp = Directory.systemTemp.createTempSync('toolbox_rescue');
  addTearDown(() => tmp.deleteSync(recursive: true));
  final tools = ToolPaths(p.join(tmp.path, 'bin'));
  return OpContext(
    cancel: CancelToken(),
    log: (LogLevel level, String text) {},
    step: (String text) {},
    device: (DeviceInfo d) {},
    tools: tools,
    probe: DeviceProbe(tools, KnownStore(tmp.path)),
    env: ToolboxEnvironment(
      binDir: p.join(tmp.path, 'bin'),
      dataDir: tmp.path,
      tempDir: p.join(tmp.path, 'temp'),
      documentsDir: p.join(tmp.path, 'docs'),
      appVersion: '0.1.0',
    ),
    history: FlashHistory(dataDir: tmp.path, documentsDir: p.join(tmp.path, 'docs')),
    logFile: LogFile(p.join(tmp.path, 'docs')),
  );
}
