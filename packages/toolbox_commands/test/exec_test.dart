import 'dart:io';

import 'package:test/test.dart';
import 'package:toolbox_commands/toolbox_commands.dart';
import 'package:toolbox_core/toolbox_core.dart';

void main() {
  late Directory tmp;
  late File script;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('toolbox_exec_test');
    script = File('${tmp.path}/child.dart')..writeAsStringSync(r'''
import 'dart:convert';
import 'dart:io';
Future<void> main(List<String> args) async {
  if (args.first == 'wait') {
    stdout.write('READY\n未换行的输出');
    await stdout.flush();
    await Future<void>.delayed(const Duration(seconds: 30));
    return;
  }
  final bytes = utf8.encode('中文输出');
  stdout.add(bytes.sublist(0, 2));
  await stdout.flush();
  stderr.write('错误流');
  await stderr.flush();
  await Future<void>.delayed(const Duration(milliseconds: 50));
  stdout.add(bytes.sublist(2));
  await stdout.flush();
  exitCode = 3;
}
''');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('完整多行命令、跨块中文、独立输出流和退出码', () async {
    final logs = <String>[];
    final r = await exec(Platform.resolvedExecutable, [script.path, 'normal', 'echo first\necho second'],
        log: (_, text) => logs.add(text));
    expect(logs.first, contains('echo first\necho second'));
    expect(r.stdout, '中文输出');
    expect(logs, containsAll(['中文输出', '错误流']));
    expect(logs.last, contains('退出码 3'));
  });

  test('取消保留末行并记录原因', () async {
    final token = CancelToken();
    final logs = <String>[];
    await expectLater(
        exec(Platform.resolvedExecutable, [script.path, 'wait'], cancel: token, log: (_, text) {
          logs.add(text);
          if (text == 'READY') token.cancel();
        }),
        throwsA(isA<CancelledException>()));
    expect(logs, contains('未换行的输出'));
    expect(logs.last, contains('命令已取消'));
  });

  test('超时记录原因，内部数据仍可选择不显示', () async {
    final logs = <String>[];
    final r = await exec(Platform.resolvedExecutable, [script.path, 'wait'],
        timeout: const Duration(seconds: 2), log: (_, text) => logs.add(text));
    expect(r.code, -1);
    expect(logs, contains('未换行的输出'));
    expect(logs.last, contains('命令超时'));
    logs.clear();
    await exec(Platform.resolvedExecutable, [script.path, 'normal'],
        echoOutput: false, log: (_, text) => logs.add(text));
    expect(logs, hasLength(2));
    expect(logs.last, contains('内部数据'));
  });
}
