// 各层共用的类型，对应 TS 版的 src/shared/types.ts

// ───────────── 设备 ─────────────

/// none=未连接，system=开机(adb)，recovery=Recovery(adb)，fastboot=Fastboot，unauthorized=adb 未授权，edl=高通 9008 深刷
enum DeviceMode {
  none('未连接'),
  system('开机'),
  recovery('Recovery'),
  fastboot('Fastboot'),
  unauthorized('未授权'),
  edl('EDL');

  const DeviceMode(this.label);
  final String label;
}

class DeviceInfo {
  const DeviceInfo({
    required this.mode,
    this.serial,
    this.multiple = false,
    this.model,
    this.brand,
    this.manufacturer,
    this.device,
    this.androidVersion,
    this.buildId,
    this.romVersion,
    this.slot,
    this.unlocked,
    this.edlPort,
  });

  static const disconnected = DeviceInfo(mode: DeviceMode.none);

  final DeviceMode mode;
  final String? serial;

  /// 同时连接了多台设备
  final bool multiple;
  final String? model;
  final String? brand;
  final String? manufacturer;
  final String? device;
  final String? androidVersion;
  final String? buildId;
  final String? romVersion;
  final String? slot;

  /// 仅 fastboot 下可读
  final bool? unlocked;

  /// 仅 edl 下可读：QDLoader 9008 占用的 COM 端口，如 COM5
  final String? edlPort;

  /// 是否为一加设备。品牌或厂商任一包含 OnePlus 即可；两者都读不到时返回 null（例如首次以 Fastboot 连接）。
  /// 同属 OPlus 的 OPPO / realme 不算 —— 它们的解锁和刷机流程与一加不同。
  bool? get isOnePlus {
    if (brand == null && manufacturer == null) return null;
    return '${brand ?? ''} ${manufacturer ?? ''}'.toLowerCase().contains('oneplus');
  }

  /// 用于判断设备连接状态是否变化（不含详情）
  String get connectionKey => '${mode.name}|${serial ?? ''}|${multiple ? 1 : 0}';

  DeviceInfo copyWith({
    String? model,
    String? brand,
    String? manufacturer,
    String? device,
    String? androidVersion,
    String? buildId,
    String? romVersion,
    String? slot,
    bool? unlocked,
    String? edlPort,
  }) =>
      DeviceInfo(
        mode: mode,
        serial: serial,
        multiple: multiple,
        model: model ?? this.model,
        brand: brand ?? this.brand,
        manufacturer: manufacturer ?? this.manufacturer,
        device: device ?? this.device,
        androidVersion: androidVersion ?? this.androidVersion,
        buildId: buildId ?? this.buildId,
        romVersion: romVersion ?? this.romVersion,
        slot: slot ?? this.slot,
        unlocked: unlocked ?? this.unlocked,
        edlPort: edlPort ?? this.edlPort,
      );
}

enum RebootTarget {
  system('系统'),
  recovery('Recovery'),
  bootloader('Fastboot'),
  edl('EDL（9008）');

  const RebootTarget(this.label);
  final String label;
}

enum PatchTarget { auto, boot, initBoot }

// ───────────── 9008 救砖 ─────────────

/// qdl 的目标存储类型
enum EdlStorage {
  ufs,
  emmc,
  nand,
  nvme,
  spinor;

  static EdlStorage? tryParse(Object? name) {
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

/// 检测到的一台 9008 设备
class EdlDevice {
  const EdlDevice({required this.port, required this.name});

  /// 设备管理器里的 COM 端口，如 COM5
  final String port;

  /// 设备名称，如「Qualcomm HS-USB QDLoader 9008」
  final String name;
}

/// 9008 刷写需要的一整套文件，全部由用户自备：
/// 工具箱只做校验、排序、日志和风险提示，不打包也不下载这些文件。
class EdlProfile {
  const EdlProfile({
    required this.programmer,
    this.vipDir,
    this.xmls = const [],
    required this.imagesDir,
    this.storage = EdlStorage.ufs,
    this.protectLun5 = true,
    this.allowMissing = false,
    this.skipReset = false,
    this.dryRunOnly = false,
  });

  /// 设备编程器（devprg*.mbn / prog_firehose_ddr.elf）
  final String programmer;

  /// 预签名 VIP 摘要表所在目录，留空表示设备不需要（未启用安全启动）
  final String? vipDir;

  /// rawprogram*.xml / patch*.xml
  final List<String> xmls;

  /// 散包镜像所在目录（qdl --include）
  final String imagesDir;
  final EdlStorage storage;

  /// 保护 LUN5：跳过 rawprogram5 / patch5
  final bool protectLun5;

  /// 散包里缺少某些镜像时跳过而不中止（qdl --allow-missing）
  final bool allowMissing;

  /// 刷完不重启，把设备留在 9008
  final bool skipReset;

  /// 只做预检（qdl --dry-run），不连设备、不刷写
  final bool dryRunOnly;
}

/// 检测 / 自检的结果，回填到界面上
class EdlState {
  const EdlState({this.ports = const [], this.qdlList, this.chipInfo, this.saharaOk = false, this.command});

  final List<EdlDevice> ports;

  /// qdl list 的原始输出
  final String? qdlList;

  /// qdl chipinfo 的原始输出（Sahara 只读）
  final String? chipInfo;

  /// Sahara 能否读到芯片信息
  final bool saharaOk;

  /// 传给 qdl 的最终参数，便于用户核对
  final String? command;
}

// ───────────── Root 方案目录 ─────────────

/// 修补方式：Magisk 系（含 Kitsune / Alpha）、APatch、KernelSU 系（含 Next / SukiSU）
enum RootFamily {
  magisk('Magisk 系'),
  apatch('APatch'),
  ksu('KernelSU 系');

  const RootFamily(this.label);
  final String label;

  static RootFamily? tryParse(Object? name) {
    for (final f in values) {
      if (f.name == name) return f;
    }
    return null;
  }
}

class SchemeApk {
  const SchemeApk({this.bundled = false, this.url, this.sha256, this.size});

  /// 内置于工具箱中（离线可用）
  final bool bundled;
  final String? url;
  final String? sha256;

  /// 字节数，仅用于显示
  final int? size;

  Map<String, Object?> toJson() => {
        if (bundled) 'bundled': true,
        if (url != null) 'url': url,
        if (sha256 != null) 'sha256': sha256,
        if (size != null) 'size': size,
      };
}

class RootScheme {
  const RootScheme({
    required this.id,
    required this.name,
    required this.family,
    required this.version,
    required this.package,
    required this.apk,
    this.homepage,
    this.note,
  });

  final String id;
  final String name;
  final RootFamily family;
  final String version;

  /// 管理器 App 的包名
  final String package;
  final SchemeApk apk;
  final String? homepage;
  final String? note;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'family': family.name,
        'version': version,
        'package': package,
        'apk': apk.toJson(),
        if (homepage != null) 'homepage': homepage,
        if (note != null) 'note': note,
      };
}

class Catalog {
  const Catalog({required this.schemes, this.updated});

  static const schemaVersion = 1;

  final String? updated;
  final List<RootScheme> schemes;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        if (updated != null) 'updated': updated,
        'schemes': [for (final s in schemes) s.toJson()],
      };
}

/// builtin=内置目录，remote=远程目录（已合并内置），cache=远程目录的本地缓存
enum CatalogSource {
  builtin('内置目录'),
  remote('远程目录'),
  cache('远程目录（缓存）');

  const CatalogSource(this.label);
  final String label;
}

class CatalogState {
  const CatalogState({required this.schemes, required this.source, this.error});

  final List<RootScheme> schemes;
  final CatalogSource source;
  final String? error;
}

/// Root 选项里表示「自定义 APK」的方案 id
const customSchemeId = 'custom';

class RootOptions {
  const RootOptions({
    required this.rom,
    required this.schemeId,
    this.customApk,
    this.customFamily,
    this.target = PatchTarget.auto,
    this.superkey,
    this.patchOnly = false,
    this.flashOther = true,
    this.uninstallOthers = true,
  });

  /// 本地 ROM 路径，或 http(s) URL（payload-dumper-rust 支持按需读取）
  final String rom;

  /// 目录中的方案 id；为 [customSchemeId] 时使用 customApk + customFamily
  final String schemeId;
  final String? customApk;
  final RootFamily? customFamily;
  final PatchTarget target;

  /// APatch 必填的超级密钥
  final String? superkey;

  /// 只生成修补后的镜像，不刷入
  final bool patchOnly;

  /// 同时刷入 ROM 中原厂的另一个分区，清除之前装过的其它 Root
  final bool flashOther;

  /// 卸载其它 Root 管理器 App
  final bool uninstallOthers;
}

class AppEntry {
  const AppEntry({required this.package, required this.label, required this.cloned});

  final String package;
  final String label;

  /// 已在双开空间（用户 999）中
  final bool cloned;

  AppEntry withCloned(bool cloned) => AppEntry(package: package, label: label, cloned: cloned);
}

// ───────────── 操作 ─────────────

sealed class OperationRequest {
  const OperationRequest();

  /// 写入日志的操作名
  String get description;
}

class RebootRequest extends OperationRequest {
  const RebootRequest(this.target);
  final RebootTarget target;
  @override
  String get description => '重启到 ${target.label}';
}

class UnlockRequest extends OperationRequest {
  const UnlockRequest();
  @override
  String get description => '解锁 Bootloader';
}

class RelockRequest extends OperationRequest {
  const RelockRequest();
  @override
  String get description => '上锁 Bootloader';
}

class SwitchSlotRequest extends OperationRequest {
  const SwitchSlotRequest();
  @override
  String get description => '切换 A/B 槽位';
}

class RootRequest extends OperationRequest {
  const RootRequest(this.options);
  final RootOptions options;
  @override
  String get description => 'Root（${options.schemeId}）';
}

class ListAppsRequest extends OperationRequest {
  const ListAppsRequest();
  @override
  String get description => '读取应用列表';
}

class CloneAppRequest extends OperationRequest {
  const CloneAppRequest(this.package, {required this.enable});
  final String package;
  final bool enable;
  @override
  String get description => enable ? '双开 $package' : '移除双开 $package';
}

class InstallPlayRequest extends OperationRequest {
  const InstallPlayRequest(this.apk);
  final String apk;
  @override
  String get description => '安装 Play 商店';
}

class OtaUpdatesRequest extends OperationRequest {
  const OtaUpdatesRequest({required this.disable});
  final bool disable;
  @override
  String get description => disable ? '禁用系统更新' : '恢复系统更新';
}

class EdlDetectRequest extends OperationRequest {
  const EdlDetectRequest();
  @override
  String get description => '查找 9008 设备';
}

class EdlProbeRequest extends OperationRequest {
  const EdlProbeRequest(this.profile);
  final EdlProfile profile;
  @override
  String get description => '9008 预检（只读）';
}

class EdlFlashRequest extends OperationRequest {
  const EdlFlashRequest(this.profile);
  final EdlProfile profile;
  @override
  String get description => profile.dryRunOnly ? '9008 预检（只读）' : '9008 刷写';
}

class EdlResetRequest extends OperationRequest {
  const EdlResetRequest();
  @override
  String get description => '退出 9008';
}

enum LogLevel { info, cmd, ok, warn, error, step }

class LogEntry {
  const LogEntry(this.time, this.level, this.text);

  final DateTime time;
  final LogLevel level;
  final String text;
}

/// 写日志的回调，命令层和业务层都用它向界面输出
typedef LogSink = void Function(LogLevel level, String text);

class OperationResult {
  const OperationResult({required this.ok, required this.message, this.outputPath, this.apps, this.edl});

  const OperationResult.fail(this.message)
      : ok = false,
        outputPath = null,
        apps = null,
        edl = null;

  final bool ok;
  final String message;

  /// 修补后镜像的保存位置等附加产物
  final String? outputPath;

  /// listApps 的结果
  final List<AppEntry>? apps;

  /// 9008 检测 / 自检的结果
  final EdlState? edl;
}

// ───────────── 设置与更新 ─────────────

class Settings {
  const Settings({this.catalogUrl = '', this.updateRepo = ''});

  /// 远程方案目录（只含数据：URL + sha256），留空则只用内置目录
  final String catalogUrl;

  /// 检查新版本用的 GitHub 仓库，形如 owner/repo
  final String updateRepo;

  factory Settings.fromJson(Map<String, Object?> json, {Settings defaults = const Settings()}) => Settings(
        catalogUrl: json['catalogUrl'] is String ? json['catalogUrl'] as String : defaults.catalogUrl,
        updateRepo: json['updateRepo'] is String ? json['updateRepo'] as String : defaults.updateRepo,
      );

  Map<String, Object?> toJson() => {'catalogUrl': catalogUrl, 'updateRepo': updateRepo};

  Settings copyWith({String? catalogUrl, String? updateRepo}) =>
      Settings(catalogUrl: catalogUrl ?? this.catalogUrl, updateRepo: updateRepo ?? this.updateRepo);
}

class UpdateInfo {
  const UpdateInfo({required this.current, this.latest, this.url, this.hasUpdate = false, this.error});

  final String current;
  final String? latest;
  final String? url;
  final bool hasUpdate;
  final String? error;
}
