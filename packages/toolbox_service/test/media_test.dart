import 'package:test/test.dart';
import 'package:toolbox_commands/src/media_script.dart';
import 'package:toolbox_core/toolbox_core.dart';
import 'package:toolbox_service/src/ops/op_exception.dart';
import 'package:toolbox_service/src/ops/wireless.dart';

/// 对应 TS 版 test/media.test.ts（mirrorArgs / parseStat / remotePath）与 ops/wireless.ts 的纯函数。
///
/// 这几处都通过 src/ 下的文件直接导入：toolbox_commands / toolbox_service 的 barrel
/// 还没有导出这两个模块，测试不需要为此改动 barrel。
void main() {
  group('remotePath', () {
    test('规范化', () {
      expect(remotePath('/sdcard/Download/../DCIM/./Camera/'), '/sdcard/DCIM/Camera');
      expect(remotePath('/sdcard'), '/sdcard');
    });
    for (final bad in ['/data/local/tmp', '/sdcard/../data', '/sdcardx', '/']) {
      test('拒绝 $bad', () => expect(() => remotePath(bad), throwsA(isA<PathOutsideStorageException>())));
    }
  });

  group('parseStat', () {
    test('目录在前、按名字排序，修改时间换成毫秒', () {
      const out = 'regular file|1234|1700000000|/sdcard/b.txt\n'
          'directory|3452|1700000001|/sdcard/DCIM\n'
          'directory|3452|1700000002|/sdcard/Alarms\n';
      expect(parseStat(out).map((e) => (e.name, e.dir, e.size, e.mtime)), const [
        ('Alarms', true, 3452, 1700000002000),
        ('DCIM', true, 3452, 1700000001000),
        ('b.txt', false, 1234, 1700000000000),
      ]);
    });
    test('文件名里有 |', () => expect(parseStat('regular file|1|1|/sdcard/a|b.txt').single.name, 'a|b.txt'));
    test('忽略不合法的行', () => expect(parseStat('乱七八糟\n\n'), isEmpty));
  });

  group('mirrorArgs', () {
    test('镜像手机屏幕', () {
      expect(
        mirrorArgs(const MirrorOptions(turnScreenOff: true, stayAwake: true), 'PJZ110'),
        ['--window-title', 'PJZ110', '--turn-screen-off', '--stay-awake'],
      );
    });
    test('镜像手机屏幕：只保持亮屏', () {
      expect(mirrorArgs(const MirrorOptions(stayAwake: true), 'PJZ110'), ['--window-title', 'PJZ110', '--stay-awake']);
    });
    test('置顶对镜像和独立屏幕都生效', () {
      expect(
        mirrorArgs(const MirrorOptions(alwaysOnTop: true), 'PJZ110'),
        ['--window-title', 'PJZ110', '--always-on-top'],
      );
      expect(
        mirrorArgs(const MirrorOptions(alwaysOnTop: true, display: MirrorDisplayOptions()), 'PJZ110'),
        contains('--always-on-top'),
      );
    });
    test('独立屏幕：指定应用和分辨率，不保持亮屏', () {
      final args = mirrorArgs(
        const MirrorOptions(
          stayAwake: true,
          display: MirrorDisplayOptions(
            app: 'tv.danmaku.bili',
            size: DisplaySize.fullHd,
            keepApp: true,
            audioOnPhone: true,
          ),
        ),
        'PJZ110',
      );
      expect(args, [
        '--window-title',
        'PJZ110（独立屏幕）',
        '--new-display=1920x1080/240',
        '--display-ime-policy=local',
        '--start-app=tv.danmaku.bili',
        '--no-vd-destroy-content',
        '--no-audio',
      ]);
    });
    test('独立屏幕：不指定应用时只开副屏桌面', () {
      final args = mirrorArgs(const MirrorOptions(stayAwake: true, display: MirrorDisplayOptions()), 'x');
      expect(args, contains('--new-display'));
      expect(args.any((a) => a.startsWith('--start-app')), isFalse);
      expect(args, isNot(contains('--turn-screen-off')));
      expect(args, isNot(contains('--stay-awake')));
      expect(args, isNot(contains('--no-vd-destroy-content')));
      expect(args, isNot(contains('--no-audio')));
    });
    test('独立屏幕：720p', () {
      final args = mirrorArgs(
        const MirrorOptions(display: MirrorDisplayOptions(size: DisplaySize.hd)),
        'x',
      );
      expect(args, contains('--new-display=1280x720/160'));
    });
    test('拒绝不合法的包名', () {
      expect(
        () => mirrorArgs(const MirrorOptions(display: MirrorDisplayOptions(app: 'a; reboot')), 'x'),
        throwsA(isA<InvalidMirrorOptionsException>()),
      );
    });
  });

  group('checkAddress', () {
    test('IP 与端口', () {
      expect(checkAddress(' 192.168.1.23 ', ' 5555 '), '192.168.1.23:5555');
      expect(checkAddress('oneplus.local', '1'), 'oneplus.local:1');
      expect(checkAddress('[fe80::1]', '65535'), '[fe80::1]:65535');
    });
    for (final bad in [
      ('', '5555'),
      ('有中文', '5555'),
      ('192.168.1.23', ''),
      ('192.168.1.23', '0'),
      ('192.168.1.23', '65536'),
      ('192.168.1.23', 'abc'),
    ]) {
      test('拒绝 ${bad.$1}:${bad.$2}', () => expect(() => checkAddress(bad.$1, bad.$2), throwsA(isA<OpException>())));
    }
    // 与 TS 版一致：HOST 正则只要求以数字字母开头，'192.168.1' 这种写法会被接受
    test('192.168.1 与 TS 版同样放行', () => expect(checkAddress('192.168.1', '5555'), '192.168.1:5555'));
  });

  test('列表脚本与 TS 版一致（路径加单引号转义）', () {
    expect(
      listRemoteScript('/sdcard/DCIM'),
      "find '/sdcard/DCIM'/ -mindepth 1 -maxdepth 1 -exec stat -L -c '%F|%s|%Y|%n' {} + 2>/dev/null",
    );
  });
}
