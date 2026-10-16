import 'package:toolbox_service/toolbox_service.dart';

import 'controller.dart';

/// 投屏的两个动作。投屏是独立进程、不走操作队列，所以不能写成 `tb.start(...)`，
/// 单独放在这里，由 [ToolboxController] 提供（见最终报告里的接线说明）。
extension MirrorActions on ToolboxController {
  /// 打开投屏窗口。返回值可直接显示给用户，不占用操作队列（投屏期间可以照常做别的事）
  Future<OperationResult> startMirror(MirrorOptions options) => service.startMirror(options);

  /// 关掉投屏窗口
  void stopMirror() => service.stopMirror();
}
