// 生成 README 用的截图：用模拟数据驱动真实界面，在 flutter test 中渲染后保存为 PNG。
// 用法：在仓库根目录运行 `melos run screenshots`，输出到 docs/screenshots。
// 需要在 Windows 上运行（用系统自带的微软雅黑、Consolas 渲染文字）。

import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneplus_toolbox/src/app.dart';
import 'package:oneplus_toolbox/src/controller.dart';
import 'package:path/path.dart' as p;

import 'mock.dart';

const _size = Size(1280, 800);
final _out = p.normalize(p.join(Directory.current.path, '..', '..', 'docs', 'screenshots'));
final _boundary = GlobalKey();

typedef Scene = ({
  String file,
  String device,
  String? page,
  bool dark,
  bool logs,
  Future<void> Function(WidgetTester tester)? act,
});

final scenes = <Scene>[
  (file: 'overview', device: 'system', page: null, dark: false, logs: false, act: null),
  (file: 'overview-dark', device: 'system', page: null, dark: true, logs: false, act: null),
  (
    file: 'root',
    device: 'system',
    page: '一键 Root',
    dark: false,
    logs: false,
    act: (t) async {
      await _tap(t, find.text('浏览…').first);
      _scrollTo(t, 0);
    },
  ),
  (
    file: 'root-running',
    device: 'system',
    page: '一键 Root',
    dark: false,
    logs: true,
    act: (t) async {
      await _tap(t, find.text('浏览…').first);
      await _tap(t, find.textContaining('只生成修补后的镜像'));
      await _tap(t, find.text('开始修补'));
      await _tap(t, find.text('日志'));
      _scrollTo(t, 0);
    },
  ),
  (
    file: 'root-apatch',
    device: 'system',
    page: '一键 Root',
    dark: false,
    logs: false,
    act: (t) async {
      await _tap(t, find.text('APatch').first);
      final key = find.byWidgetPredicate((w) => w is TextField && w.obscureText);
      await t.enterText(key, 'abc12345');
      await t.pump();
      _scrollTo(t, 330);
    },
  ),
  (
    file: 'bootloader',
    device: 'fastboot',
    page: 'Bootloader',
    dark: false,
    logs: false,
    act: (t) => _tap(t, find.text('开始解锁')),
  ),
  (
    file: 'edl',
    device: 'edl',
    page: '9008 救砖',
    dark: false,
    logs: false,
    act: (t) async {
      await _tap(t, find.text('检测设备'));
      for (var i = 0; i < 3; i++) {
        await _tap(t, find.text('浏览…').at(i));
      }
      await _tap(t, find.text('选择 XML'));
      await _tap(t, find.text('预检'));
      _scrollTo(t, 175);
    },
  ),
  (
    file: 'apps',
    device: 'system',
    page: '应用双开',
    dark: false,
    logs: false,
    act: (t) async {
      await _tap(t, find.text('读取应用列表'));
      // 图片解码在真实的异步环境里完成
      await t.runAsync(() async {
        final context = t.element(find.byType(Scaffold));
        for (final bytes in _icons.values) {
          await precacheImage(MemoryImage(bytes), context);
        }
      });
      await t.pump();
    },
  ),
  (file: 'tools', device: 'system', page: '系统工具', dark: false, logs: false, act: null),
];

late Map<String, Uint8List> _icons;

Future<void> _settle(WidgetTester t) async {
  // 进度条是无限动画，不能用 pumpAndSettle
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder);
  await t.pump();
  await t.tap(finder);
  await _settle(t);
}

/// 主内容区滚动到指定位置（超出范围时取最大值）
void _scrollTo(WidgetTester t, double offset) {
  final scrollable = find.descendant(of: find.byType(SingleChildScrollView).first, matching: find.byType(Scrollable));
  final pos = t.state<ScrollableState>(scrollable.first).position;
  pos.jumpTo(offset.clamp(0, pos.maxScrollExtent));
}

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    if (File(f).existsSync()) loader.addFont(File(f).readAsBytes().then((b) => ByteData.sublistView(b)));
  }
  await loader.load();
}

/// 和 TS 版一样：彩色圆角方块 + 应用名首字
Future<Map<String, Uint8List>> _makeIcons() async {
  const colors = [
    0xffe5173f,
    0xff2563eb,
    0xff16a34a,
    0xfff59e0b,
    0xff7c3aed,
    0xff0891b2,
    0xffdb2777,
    0xffea580c,
    0xff4f46e5
  ];
  final result = <String, Uint8List>{};
  for (var i = 0; i < apps.length; i++) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRRect(RRect.fromLTRBR(0, 0, 96, 96, const Radius.circular(22)), Paint()..color = Color(colors[i]));
    final para = (ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center, fontFamily: 'Microsoft YaHei UI'))
          ..pushStyle(ui.TextStyle(color: Colors.white, fontSize: 44))
          ..addText(apps[i].label.characters.first))
        .build()
      ..layout(const ui.ParagraphConstraints(width: 96));
    canvas.drawParagraph(para, Offset(0, (96 - para.height) / 2));
    final image = await recorder.endRecording().toImage(96, 96);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    result[apps[i].package] = png!.buffer.asUint8List();
  }
  return result;
}

void main() {
  setUpAll(() async {
    final fonts = p.join(Platform.environment['WINDIR'] ?? r'C:\Windows', 'Fonts');
    // flutter_tester.exe 位于 <flutter>/bin/cache/artifacts/engine/windows-x64/
    final artifacts = p.dirname(p.dirname(p.dirname(Platform.resolvedExecutable)));
    final yahei = [p.join(fonts, 'msyh.ttc'), p.join(fonts, 'msyhbd.ttc')];
    await _loadFont('Microsoft YaHei UI', yahei);
    await _loadFont('Segoe UI', [p.join(fonts, 'segoeui.ttf'), p.join(fonts, 'seguisb.ttf')]);
    await _loadFont('Segoe UI Symbol', [p.join(fonts, 'seguisym.ttf')]);
    await _loadFont('Consolas', [p.join(fonts, 'consola.ttf')]);
    await _loadFont('MaterialIcons', [p.join(artifacts, 'material_fonts', 'materialicons-regular.otf')]);
    _icons = await _makeIcons();
    FileSelectorPlatform.instance = MockFilePicker();
    Directory(_out).createSync(recursive: true);
  });

  for (final s in scenes) {
    testWidgets(s.file, (tester) async {
      tester.view.physicalSize = _size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.platformBrightnessTestValue = s.dark ? Brightness.dark : Brightness.light;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      FileSelectorPlatform.instance = MockFilePicker();

      final service = MockService(devices[s.device]!, logLines: s.logs ? rootLogs : const [], icons: _icons);
      final tb = ToolboxController(service);
      await tester.pumpWidget(RepaintBoundary(key: _boundary, child: ToolboxApp(controller: tb)));
      await _settle(tester);

      if (s.page != null) await _tap(tester, find.text(s.page!).first);
      await s.act?.call(tester);
      await _settle(tester);
      // 让进度圈转到一个能看清的角度
      await tester.pump(const Duration(milliseconds: 650));

      final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File(p.join(_out, '${s.file}.png')).writeAsBytesSync(png!.buffer.asUint8List());
      });

      // 卸载界面，结束进度条动画和未完成的操作
      await tester.pumpWidget(const SizedBox());
      tb.dispose();
    });
  }
}
