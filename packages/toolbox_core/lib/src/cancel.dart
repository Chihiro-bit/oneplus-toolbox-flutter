import 'dart:async';

/// 操作被用户取消
class CancelledException implements Exception {
  const CancelledException();

  @override
  String toString() => '操作已取消';
}

/// 取消令牌，对应 TS 版的 AbortSignal。由业务层创建，传给命令层的每一次调用。
class CancelToken {
  final _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  /// 取消时完成，用于结束正在运行的子进程或下载
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }

  void throwIfCancelled() {
    if (isCancelled) throw const CancelledException();
  }
}
