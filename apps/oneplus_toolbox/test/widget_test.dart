import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneplus_toolbox/src/app.dart';
import 'package:oneplus_toolbox/src/controller.dart';
import 'package:oneplus_toolbox/src/widgets/common.dart';
import 'package:oneplus_toolbox/src/widgets/dialogs.dart';
import 'package:path/path.dart' as p;
import 'package:toolbox_service/toolbox_service.dart';

void main() {
  late Directory tmp;
  late ToolboxController tb;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('toolbox_ui_test');
    // 工具目录为空：轮询会静默失败，界面停留在「未连接」
    tb = ToolboxController(ToolboxService(ToolboxEnvironment(
      binDir: p.join(tmp.path, 'bin'),
      dataDir: p.join(tmp.path, 'data'),
      tempDir: tmp.path,
      documentsDir: tmp.path,
      appVersion: '0.1.0',
    )));
  });

  tearDown(() {
    tb.service.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ToolboxApp(controller: tb));
    await tester.pump();
  }

  testWidgets('未连接设备时显示概览，缺少工具写入日志', (tester) async {
    await pumpApp(tester);
    expect(find.text('等待设备连接'), findsOneWidget);
    expect(find.text('无设备'), findsOneWidget);
    expect(tb.logs.single.text, contains('缺少工具'));
  });

  testWidgets('一键 Root 页显示内置方案，未选 ROM 时不能开始', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('一键 Root').first);
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(find.text('Magisk（内置）'), findsOneWidget);
    expect(find.text('SukiSU Ultra'), findsOneWidget);
    final start = find.widgetWithText(FilledButton, '开始 Root');
    expect(tester.widget<FilledButton>(start).onPressed, isNull);

    // 切到 APatch 后出现超级密钥输入框
    await tester.tap(find.text('APatch').first);
    await tester.pump();
    expect(find.text('超级密钥'), findsOneWidget);
    expect(find.text('流程 · APatch'), findsOneWidget);
  });

  testWidgets('页面之间切换', (tester) async {
    await pumpApp(tester);
    for (final (nav, header) in [
      ('重启与模式', '在开机、Recovery、Fastboot 之间切换'),
      ('Bootloader', '解锁是 Root 和刷第三方系统的前提。解锁、上锁都会清空手机全部数据'),
      ('A/B 槽位', '适用于 A/B 分区机型。刷坏一个槽位后，切换到另一个槽位往往能重新开机'),
      ('应用双开', '利用 ColorOS / 氧 OS 自带的分身空间（用户 999），把任意第三方应用克隆一份'),
      ('系统工具', '免 Root 的常用调整，需要手机开机并开启 USB 调试'),
      ('设置', '方案目录与版本更新'),
    ]) {
      await tester.tap(find.text(nav).first);
      await tester.pump();
      expect(find.text(header), findsOneWidget, reason: nav);
    }
    // 未连接设备时按钮不可用并给出原因
    await tester.tap(find.text('系统工具').first);
    await tester.pump();
    expect(find.text('未连接设备'), findsOneWidget);
  });

  testWidgets('危险操作需要勾选全部条目并输入确认码', (tester) async {
    await pumpApp(tester);
    final context = tester.element(find.byType(Scaffold));
    final result = confirmAction(
      context,
      const ConfirmSpec(title: '测试', danger: true, checks: ['条目一', '条目二'], confirmText: '确认执行'),
    );
    await tester.pumpAndSettle();

    FilledButton confirm() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, '确认执行'));
    expect(confirm().onPressed, isNull);
    await tester.tap(find.text('条目一'));
    await tester.tap(find.text('条目二'));
    await tester.pump();
    expect(confirm().onPressed, isNull, reason: '还没有输入确认码');

    final code = tester
        .widgetList<Text>(find.descendant(of: find.byType(Dialog), matching: find.byType(Text)))
        .map((t) => t.data ?? '')
        .firstWhere((s) => RegExp(r'^[A-Z2-9]{4}$').hasMatch(s));
    await tester.enterText(find.byType(TextField), code.toLowerCase());
    await tester.pump();
    expect(confirm().onPressed, isNotNull);
    await tester.tap(find.text('确认执行'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });

  test('gate', () {
    expect(gate(tb, {DeviceMode.system}).reason, '未连接设备');
  });
}
