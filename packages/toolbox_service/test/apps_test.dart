import 'package:test/test.dart';
import 'package:toolbox_commands/toolbox_commands.dart';
import 'package:toolbox_service/src/ops/apps.dart' as apps;
import 'package:toolbox_service/src/ops/context.dart';

class _Adb extends Adb {
  _Adb(this.responses) : super('unused');
  final List<ExecResult> responses;
  final calls = <List<String>>[];
  @override
  Future<ExecResult> shell(String serial, List<String> args,
      {Duration timeout = const Duration(seconds: 60), bool echoOutput = true}) async {
    calls.add(args);
    return responses.removeAt(0);
  }
}

class _Context implements OpContext {
  _Context(this.adb);
  @override
  final Adb adb;
  @override
  Future<String> requireSystem() async => 'phone';
  @override
  void Function(String) get step => (_) {};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('Root 不绕过必需组件保护和包名校验', () async {
    final adb = _Adb([]);
    for (final pkg in ['com.android.systemui', 'com.example;reboot']) {
      await expectLater(apps.debloat(pkg, _Context(adb), remove: true, root: true), throwsA(isA<OpException>()));
    }
    expect(adb.calls, isEmpty);
  });
  test('授权被拒绝时不卸载', () async {
    final adb = _Adb([const ExecResult(1, '', 'Permission denied', 'Permission denied')]);
    await expectLater(
        apps.debloat('com.example.app', _Context(adb), remove: true, root: true), throwsA(isA<OpException>()));
    expect(adb.calls, hasLength(1));
  });
  test('Root 授权后只卸载当前用户，系统拒绝时返回失败', () async {
    final adb = _Adb([const ExecResult(0, '0\n', '', '0\n'), const ExecResult(1, '', '', 'Failure')]);
    final r = await apps.debloat('com.example.app', _Context(adb), remove: true, root: true);
    expect(adb.calls.last.single, contains("su -c 'pm uninstall -k --user 0 com.example.app'"));
    expect(r.ok, isFalse);
    expect(r.message, contains('系统仍拒绝'));
  });
}
