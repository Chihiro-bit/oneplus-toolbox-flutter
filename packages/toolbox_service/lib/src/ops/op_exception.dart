/// 预期内的失败：消息直接展示给用户
class OpException implements Exception {
  const OpException(this.message);
  final String message;

  @override
  String toString() => message;
}
