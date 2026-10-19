/// 命令层：真正和外部程序、手机、网络打交道的部分。
///
/// 这里只负责「怎么执行」和「怎么解析输出」，不决定「该不该执行」——
/// 前置检查、流程编排、给用户看的提示都在 toolbox_service 里。
library;

export 'src/aab.dart';
export 'src/adb.dart';
export 'src/app_data.dart';
export 'src/app_list.dart';
export 'src/apps_script.dart';
export 'src/backup_script.dart';
export 'src/download.dart';
export 'src/drivers_script.dart';
export 'src/exec.dart';
export 'src/fastboot.dart';
export 'src/install_split.dart';
export 'src/media_script.dart';
export 'src/module_install.dart';
export 'src/network_script.dart';
export 'src/patch_script.dart';
export 'src/payload_dumper.dart';
export 'src/qdl.dart';
export 'src/rescue_script.dart';
export 'src/seven_zip.dart';
export 'src/shizuku_script.dart';
export 'src/tool_paths.dart';
