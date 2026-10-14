/// 业务层：界面唯一需要依赖的包。
///
/// 对外只暴露 [ToolboxService] 和环境配置，命令层（toolbox_commands）的类型不会泄露给界面。
library;

export 'package:toolbox_core/toolbox_core.dart';

export 'src/environment.dart';
export 'src/settings_store.dart' show SettingsException;
export 'src/toolbox_service.dart';
export 'src/update_checker.dart' show isNewerVersion;
