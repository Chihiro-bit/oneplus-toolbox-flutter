// 截图用的模拟数据：全部是虚构的，不连接任何设备。与 TS 版 scripts/screenshots/mock.js 保持一致。

import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:toolbox_service/toolbox_service.dart';

const devices = {
  'none': DeviceInfo.disconnected,
  'system': DeviceInfo(
    mode: DeviceMode.system,
    serial: '1a2b3c4d',
    model: 'OnePlus 13',
    brand: 'OnePlus',
    manufacturer: 'OnePlus',
    device: 'OP5D0DL1',
    androidVersion: '16',
    buildId: 'PJZ110_16.0.0.300(CN01)',
    romVersion: 'V16.0.0',
    slot: 'a',
  ),
  'fastboot': DeviceInfo(
    mode: DeviceMode.fastboot,
    serial: '1a2b3c4d',
    model: 'OnePlus 13',
    brand: 'OnePlus',
    device: 'sun',
    slot: 'b',
    unlocked: true,
  ),
  'edl': DeviceInfo(
    mode: DeviceMode.edl,
    serial: 'COM5',
    edlPort: 'COM5',
    device: 'Qualcomm HS-USB QDLoader 9008 (COM5)',
  ),
};

const edlPorts = [EdlDevice(port: 'COM5', name: 'Qualcomm HS-USB QDLoader 9008 (COM5)')];
const edlChip = 'Sahara version   : 3\n'
    'MSM HWID         : 0x600001 | model_id:0x0000 | oem_id:0x0051 OPPO\n'
    'HW_ID            : 0060000100510000';
const edlProgrammer = r'D:\EDL\8Gen3\devprg_firehose_ddr.mbn';
const edlVipDir = r'D:\EDL\8Gen3\vip';
const edlImagesDir = r'D:\EDL\PJZ110_images';
const edlXmls = [r'D:\EDL\PJZ110_images\rawprogram0.xml', r'D:\EDL\PJZ110_images\patch0.xml'];
const rom = r'D:\ROM\PJZ110_16.0.0.300.zip';

const apps = [
  AppEntry(package: 'com.example.chat', label: '聊天', cloned: true),
  AppEntry(package: 'com.example.notes', label: '便签', cloned: false),
  AppEntry(package: 'com.example.music', label: '音乐', cloned: true),
  AppEntry(package: 'com.example.camera', label: '相机 Pro', cloned: false),
  AppEntry(package: 'com.example.maps', label: '地图导航', cloned: false),
  AppEntry(package: 'com.example.reader', label: '阅读', cloned: false),
  AppEntry(package: 'com.example.shop', label: '购物', cloned: false),
  AppEntry(package: 'com.example.video', label: '视频', cloned: false),
  AppEntry(package: 'com.example.bank', label: '银行', cloned: false),
];

const rootLogs = [
  (LogLevel.step, '── 开始：Root（magisk） ──'),
  (LogLevel.ok, 'Magisk 30.7 下载完成，sha256 校验通过'),
  (LogLevel.step, '正在读取 ROM 信息'),
  (LogLevel.cmd, r'payload_dumper D:\ROM\PJZ110_16.0.0.300.zip --metadata -o C:\Temp\oneplus-toolbox\work\metadata'),
  (LogLevel.info, 'ROM 构建时间 = 1785725462，手机 ro.build.date.utc = 1785725462'),
  (LogLevel.ok, 'ROM 与手机系统版本一致'),
  (LogLevel.cmd, r'payload_dumper D:\ROM\PJZ110_16.0.0.300.zip -i boot,init_boot -o C:\Temp\oneplus-toolbox\work -q'),
  (LogLevel.info, '提取结果：boot.img ✓  init_boot.img ✓'),
  (LogLevel.ok, '将修补 init_boot.img'),
  (LogLevel.step, '正在手机上修补 init_boot.img'),
  (LogLevel.info, 'KEEPVERITY=true KEEPFORCEENCRYPT=true PATCHVBMETAFLAG=false'),
  (LogLevel.info, '- Unpacking boot image'),
  (LogLevel.info, '- Patching ramdisk'),
  (LogLevel.info, '- Repacking boot image'),
];

/// 代替 [ToolboxService]：返回模拟数据，列表以外的操作一直停在「进行中」，用来展示进度横幅
class MockService implements ToolboxService {
  MockService(this.device, {this.logLines = const [], this.icons = const {}});

  @override
  final DeviceInfo device;
  final List<(LogLevel, String)> logLines;
  final Map<String, Uint8List> icons;

  final _logs = StreamController<LogEntry>.broadcast();
  final _steps = StreamController<String>.broadcast();
  final _icons = StreamController<Map<String, Uint8List>>.broadcast();

  @override
  Stream<DeviceInfo> get deviceChanges => const Stream.empty();
  @override
  Stream<LogEntry> get logs => _logs.stream;
  @override
  Stream<String> get steps => _steps.stream;
  @override
  Stream<Map<String, Uint8List>> get appIcons => _icons.stream;
  @override
  bool get busy => false;

  @override
  void start() {
    final now = DateTime(2026, 10, 15, 14, 30);
    for (var i = 0; i < logLines.length; i++) {
      final (level, text) = logLines[i];
      _logs.add(LogEntry(now.subtract(Duration(seconds: (logLines.length - i) * 2)), level, text));
    }
  }

  @override
  Future<OperationResult> run(OperationRequest req) async {
    switch (req) {
      case ListAppsRequest():
        scheduleMicrotask(() => _icons.add(icons));
        return const OperationResult(ok: true, message: '共 9 个应用，其中 2 个已双开', apps: apps);
      case EdlDetectRequest():
        return const OperationResult(
          ok: true,
          message: '已找到 1 台 9008 设备',
          edl: EdlState(ports: edlPorts, qdlList: 'COM5'),
        );
      case EdlProbeRequest():
        return const OperationResult(
          ok: true,
          message: '预检通过：Sahara 正常，文件集与摘要表一致，可以开始刷写',
          edl: EdlState(
            ports: edlPorts,
            chipInfo: edlChip,
            saharaOk: true,
            command: 'qdl --storage=ufs --vip-table-path=$edlVipDir --include=$edlImagesDir $edlProgrammer '
                'rawprogram0.xml patch0.xml',
          ),
        );
      default:
        scheduleMicrotask(() => _steps.add('正在手机上修补 init_boot.img'));
        return Completer<OperationResult>().future;
    }
  }

  @override
  void cancel() {}

  @override
  Future<CatalogState> catalog({bool refresh = false}) async =>
      CatalogState(schemes: builtinCatalog.schemes, source: CatalogSource.builtin);

  @override
  Settings get settings => const Settings();

  @override
  Future<UpdateInfo> checkUpdate() async => const UpdateInfo(current: '0.1.0');

  @override
  void dispose() {
    _logs.close();
    _steps.close();
    _icons.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 代替系统的文件选择对话框。第一次选目录返回摘要表目录，之后返回散包目录
class MockFilePicker extends FileSelectorPlatform {
  var _dirPicks = 0;

  @override
  Future<XFile?> openFile(
      {List<XTypeGroup>? acceptedTypeGroups, String? initialDirectory, String? confirmButtonText}) async {
    final exts = acceptedTypeGroups?.expand((g) => g.extensions ?? const <String>[]) ?? const <String>[];
    return XFile(exts.contains('zip') ? rom : edlProgrammer);
  }

  @override
  Future<List<XFile>> openFiles(
          {List<XTypeGroup>? acceptedTypeGroups, String? initialDirectory, String? confirmButtonText}) async =>
      [for (final x in edlXmls) XFile(x)];

  @override
  Future<String?> getDirectoryPath({String? initialDirectory, String? confirmButtonText}) async =>
      _dirPicks++ == 0 ? edlVipDir : edlImagesDir;
}
