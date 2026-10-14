import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:toolbox_service/toolbox_service.dart';

/// 当前操作的界面状态
@immutable
class RunState {
  const RunState({this.running = false, this.title, this.step, this.result});

  static const idle = RunState();

  final bool running;
  final String? title;
  final String? step;
  final OperationResult? result;
}

/// 界面状态：订阅 [ToolboxService] 的各个流，转成可监听的状态，对应 TS 版的 useToolbox()
class ToolboxController extends ChangeNotifier {
  ToolboxController(this.service) {
    _device = service.device;
    _subs = [
      service.deviceChanges.listen((d) {
        _device = d;
        notifyListeners();
      }),
      service.logs.listen((e) {
        if (_logs.length >= maxLogs) _logs.removeRange(0, _logs.length - maxLogs + 1);
        _logs.add(e);
        logRevision.value++;
      }),
      service.steps.listen((s) {
        if (!_run.running) return;
        _run = RunState(running: true, title: _run.title, step: s);
        notifyListeners();
      }),
      service.appIcons.listen((batch) => icons.value = {...icons.value, ...batch}),
    ];
    service.start();
  }

  static const maxLogs = 2000;

  final ToolboxService service;
  late final List<StreamSubscription<Object?>> _subs;

  late DeviceInfo _device;
  DeviceInfo get device => _device;

  RunState _run = RunState.idle;
  RunState get run => _run;

  final _logs = <LogEntry>[];
  List<LogEntry> get logs => _logs;

  /// 日志变化计数。日志单独通知，避免每一行输出都重建整个界面
  final logRevision = ValueNotifier(0);

  /// 应用图标：包名 → 图片字节
  final icons = ValueNotifier<Map<String, Uint8List>>(const {});

  /// 本次运行中已确认过「非一加设备」警告的序列号
  final acknowledged = <String>{};

  Future<OperationResult> start(String title, OperationRequest req) async {
    _run = RunState(running: true, title: title, step: '准备中…');
    notifyListeners();
    final result = await service.run(req);
    _run = RunState(title: title, result: result);
    notifyListeners();
    return result;
  }

  void cancel() => service.cancel();

  void dismiss() {
    _run = RunState.idle;
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    logRevision.value++;
  }

  void acknowledge(String serial) {
    acknowledged.add(serial);
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    logRevision.dispose();
    icons.dispose();
    super.dispose();
  }
}
