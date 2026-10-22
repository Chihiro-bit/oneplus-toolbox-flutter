import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:toolbox_core/toolbox_core.dart';

/// 设置格式不正确，消息直接展示给用户
class SettingsException implements Exception {
  const SettingsException(this.message);
  final String message;

  @override
  String toString() => message;
}

class SettingsStore {
  SettingsStore(String dataDir, {String defaultUpdateRepo = ''})
      : _file = File(p.join(dataDir, 'settings.json')),
        _defaults = Settings(updateRepo: defaultUpdateRepo);

  final File _file;
  final Settings _defaults;

  Settings load() {
    try {
      return Settings.fromJson(jsonDecode(_file.readAsStringSync()) as Map<String, Object?>, defaults: _defaults);
    } catch (_) {
      return _defaults;
    }
  }

  /// 清理并校验后保存，返回实际保存的值
  Settings save(Settings s) {
    final clean = Settings(
      closeBehavior: s.closeBehavior,
      catalogUrl: s.catalogUrl.trim(),
      updateRepo:
          s.updateRepo.trim().replaceFirst(RegExp(r'^https://github\.com/'), '').replaceFirst(RegExp(r'/$'), ''),
    );
    if (clean.catalogUrl.isNotEmpty && !clean.catalogUrl.startsWith('https://')) {
      throw const SettingsException('目录地址必须以 https:// 开头');
    }
    if (clean.updateRepo.isNotEmpty && !RegExp(r'^[\w.-]+/[\w.-]+$').hasMatch(clean.updateRepo)) {
      throw const SettingsException('仓库格式应为 owner/repo');
    }
    _file.parent.createSync(recursive: true);
    _file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(clean.toJson()));
    return clean;
  }
}
