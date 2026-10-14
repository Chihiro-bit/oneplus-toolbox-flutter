// 检查各层只依赖它正下方允许的包（见 melos.yaml 顶部的分层说明）。
//
// 同时检查 pubspec.yaml 的依赖和 lib/ 下每个文件的 package: 导入，
// 防止「pubspec 没声明、靠传递依赖偷偷 import」的情况。
//
// 用法：在 flutter/ 目录下运行 `dart run tool/check_layers.dart`（或 `melos run check:layers`）

import 'dart:io';

import 'package:yaml/yaml.dart';

/// 包名 → 所在目录、允许依赖的工作区内部包、是否允许依赖 Flutter
const layers = {
  'oneplus_toolbox': (dir: 'apps/oneplus_toolbox', allowed: {'toolbox_service'}, flutter: true),
  'toolbox_service': (dir: 'packages/toolbox_service', allowed: {'toolbox_commands', 'toolbox_core'}, flutter: false),
  'toolbox_commands': (dir: 'packages/toolbox_commands', allowed: {'toolbox_core'}, flutter: false),
  'toolbox_core': (dir: 'packages/toolbox_core', allowed: <String>{}, flutter: false),
};

final _import = RegExp(r'''^\s*(?:import|export)\s+['"]package:([a-z0-9_]+)/''', multiLine: true);

void main() {
  final errors = <String>[];
  final internal = layers.keys.toSet();

  for (final MapEntry(key: name, value: layer) in layers.entries) {
    final pubspec = File('${layer.dir}/pubspec.yaml');
    if (!pubspec.existsSync()) {
      errors.add('$name：找不到 ${pubspec.path}');
      continue;
    }
    final yaml = loadYaml(pubspec.readAsStringSync()) as YamlMap;
    final deps = ((yaml['dependencies'] as YamlMap?)?.keys ?? const []).cast<String>().toSet();

    for (final d in deps.intersection(internal).difference(layer.allowed)) {
      errors.add('$name：pubspec.yaml 不应依赖 $d');
    }
    if (!layer.flutter && deps.contains('flutter')) {
      errors.add('$name：必须是纯 Dart 包，不能依赖 flutter');
    }

    final lib = Directory('${layer.dir}/lib');
    if (!lib.existsSync()) continue;
    for (final file in lib.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      for (final m in _import.allMatches(file.readAsStringSync())) {
        final pkg = m[1]!;
        if (pkg == name) continue;
        final rel = file.path.replaceAll(r'\', '/');
        if (internal.contains(pkg) && !layer.allowed.contains(pkg)) {
          errors.add('$rel：$name 不能导入 $pkg');
        } else if (!internal.contains(pkg) && !deps.contains(pkg) && !_sdkPackages.contains(pkg)) {
          errors.add('$rel：导入了 pubspec.yaml 未声明的包 $pkg');
        }
      }
    }
  }

  if (errors.isEmpty) {
    stdout.writeln('分层检查通过：${layers.keys.join(' → ')}');
    return;
  }
  stderr.writeln('分层检查失败：');
  for (final e in errors) {
    stderr.writeln('  - $e');
  }
  exitCode = 1;
}

/// 随 SDK 提供、不需要在 pubspec 中声明的包
const _sdkPackages = {'flutter', 'flutter_test', 'sky_engine'};
