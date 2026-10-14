import 'dart:math';

final _letter = RegExp(r'[a-zA-Z]');
final _digit = RegExp(r'\d');
final _superkeyChars = RegExp(r'^[A-Za-z0-9_.@#%+=-]+$');

/// APatch 超级密钥的问题描述，合法时返回 null。
/// 至少 8 位，同时包含字母和数字；限制字符集，避免拼进 shell 时出问题。
/// 界面（实时提示）和业务层（执行前把关）共用这一份规则。
String? superkeyProblem(String? key) {
  if (key == null || key.isEmpty) return '请设置超级密钥';
  if (key.length < 8) return '至少 8 位';
  if (!_letter.hasMatch(key) || !_digit.hasMatch(key)) return '必须同时包含字母和数字';
  if (!_superkeyChars.hasMatch(key)) return '只能包含字母、数字和 _ . @ # % + = -';
  return null;
}

final _packageName = RegExp(r'^[\w.]+$');

bool isValidPackageName(String pkg) => _packageName.hasMatch(pkg);

final _https = RegExp(r'^https?://', caseSensitive: false);

/// ROM 是否以下载链接的形式给出
bool isUrl(String s) => _https.hasMatch(s.trim());

/// 生成危险操作的确认码（去掉易混淆的字符）
String randomCode([int length = 4, Random? random]) {
  const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  final r = random ?? Random.secure();
  return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
}

/// 字节数格式化为 MB
String formatSize(int? bytes) => bytes == null || bytes == 0 ? '' : '${(bytes / 1048576).toStringAsFixed(1)} MB';
