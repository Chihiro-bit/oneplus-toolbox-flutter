// 各层共用的类型，对应 TS 版的 src/shared/types.ts

import 'network.dart';

// ───────────── 设备 ─────────────

/// none=未连接，system=开机(adb)，recovery=Recovery(adb)，fastboot=Bootloader 里的 Fastboot，
/// fastbootd=用户空间 Fastboot（刷逻辑分区、取消未合并的更新时用），unauthorized=adb 未授权，edl=高通 9008 深刷
enum DeviceMode {
  none('未连接'),
  system('开机'),
  recovery('Recovery'),
  fastboot('Fastboot'),
  fastbootd('fastbootd'),
  unauthorized('未授权'),
  edl('EDL');

  const DeviceMode(this.label);
  final String label;
}

/// 连着多台设备时，左下角选择框里的一项
class DeviceRef {
  const DeviceRef({required this.serial, required this.mode, this.label});

  final String serial;
  final DeviceMode mode;

  /// 仅 edl：设备管理器里的名称
  final String? label;

  Map<String, Object?> toJson() => {
        'serial': serial,
        'mode': mode.name,
        if (label != null) 'label': label,
      };
}

class DeviceInfo {
  const DeviceInfo({
    required this.mode,
    this.serial,
    this.multiple = false,
    this.devices = const [],
    this.selected,
    this.needsPick = false,
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
    this.root,
  });

  static const disconnected = DeviceInfo(mode: DeviceMode.none);

  final DeviceMode mode;
  final String? serial;

  /// 同时连接了多台设备
  final bool multiple;

  /// 连着多台时的全部设备，供界面选择
  final List<DeviceRef> devices;

  /// 连着多台时选中的序列号（可能不在线，例如正卡在开机）
  final String? selected;

  /// 连着多台、但当前显示的这台不是选中的：操作会被拒绝
  final bool needsPick;
  final String? model;
  final String? brand;
  final String? manufacturer;
  final String? device;
  final String? androidVersion;
  final String? buildId;
  final String? romVersion;
  final String? slot;

  /// 仅 fastboot / fastbootd 下可读
  final bool? unlocked;

  /// 仅 edl 下可读：QDLoader 9008 占用的 COM 端口，如 COM5
  final String? edlPort;

  /// 仅开机下可读：Root 状态，如「Magisk 30.7」「未 Root」
  final String? root;

  /// 是否为一加设备。品牌或厂商任一包含 OnePlus 即可；两者都读不到时返回 null（例如首次以 Fastboot 连接）。
  /// 同属 OPlus 的 OPPO / realme 不算 —— 它们的解锁和刷机流程与一加不同。
  bool? get isOnePlus {
    if (brand == null && manufacturer == null) return null;
    return '${brand ?? ''} ${manufacturer ?? ''}'.toLowerCase().contains('oneplus');
  }

  /// 用于判断设备连接状态是否变化（不含详情）
  String get connectionKey => '${mode.name}|${serial ?? ''}|${multiple ? 1 : 0}|${selected ?? ''}|${needsPick ? 1 : 0}';

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
    String? root,
  }) =>
      DeviceInfo(
        mode: mode,
        serial: serial,
        multiple: multiple,
        devices: devices,
        selected: selected,
        needsPick: needsPick,
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
        root: root ?? this.root,
      );
}

enum RebootTarget {
  system('系统'),
  recovery('Recovery'),
  bootloader('Fastboot'),
  fastbootd('fastbootd'),
  edl('EDL（9008）');

  const RebootTarget(this.label);
  final String label;
}

enum PatchTarget { auto, boot, initBoot }

// ───────────── 救援与恢复 ─────────────

class UnrootOptions {
  const UnrootOptions({
    required this.rom,
    this.uninstallManagers = false,
    this.allowUnverified = false,
  });

  /// 与手机系统版本一致的全量包：本地路径或 http(s) URL
  final String rom;

  /// 刷完开机后卸载 Root 管理器 App
  final bool uninstallManagers;

  /// Fastboot 下读不到手机的系统版本时，仍然继续（只给警告）
  final bool allowUnverified;
}

/// 可以从 ROM 刷回的原厂分区
enum StockPartition {
  initBoot('init_boot'),
  boot('boot'),
  vendorBoot('vendor_boot'),
  dtbo('dtbo'),
  vbmeta('vbmeta'),
  vbmetaSystem('vbmeta_system'),
  vbmetaVendor('vbmeta_vendor');

  const StockPartition(this.id);
  final String id;

  static StockPartition? tryParse(Object? id) {
    for (final p in values) {
      if (p.id == id || p.name == id) return p;
    }
    return null;
  }
}

class RestoreOptions {
  const RestoreOptions({
    required this.rom,
    required this.partitions,
    this.allowUnverified = false,
  });

  final String rom;
  final List<StockPartition> partitions;
  final bool allowUnverified;
}

/// device=已 Root 时用 dd 从手机读出分区，rom=从 ROM 提取原厂镜像
enum BackupSource { device, rom }

class BackupOptions {
  const BackupOptions({required this.source, this.rom});

  final BackupSource source;
  final String? rom;
}

/// 设备管理器里和手机有关的一项
class DriverEntry {
  const DriverEntry({
    required this.name,
    required this.instanceId,
    required this.ok,
    this.className,
    this.problem,
    this.hint,
  });

  final String name;
  final String instanceId;
  final bool ok;
  final String? className;

  /// 异常说明，如「没有安装驱动（代码 28）」
  final String? problem;

  /// 该装哪个驱动
  final String? hint;
}

/// 手机内置存储里的一项
class RemoteEntry {
  const RemoteEntry({required this.name, required this.dir, required this.size, required this.mtime});

  final String name;
  final bool dir;
  final int size;

  /// 修改时间（毫秒）
  final int mtime;
}

// ───────────── 投屏 ─────────────

/// 独立屏幕（虚拟显示器）的分辨率：auto=跟随手机屏幕
enum DisplaySize {
  auto('跟随手机屏幕', null),
  fullHd('1080p 横屏', '1920x1080/240'),
  hd('720p 横屏（更流畅）', '1280x720/160');

  const DisplaySize(this.label, this.arg);
  final String label;
  final String? arg;
}

class MirrorDisplayOptions {
  const MirrorDisplayOptions({
    this.app,
    this.size = DisplaySize.auto,
    this.keepApp = false,
    this.audioOnPhone = false,
  });

  /// 启动到虚拟屏上的应用包名；为空时显示系统的副屏桌面
  final String? app;
  final DisplaySize size;

  /// 关掉窗口后把应用移回手机屏幕（会跳到手机前台）；否则关掉
  final bool keepApp;

  /// 声音留在手机上；否则转到电脑
  final bool audioOnPhone;
}

class MirrorOptions {
  const MirrorOptions({
    this.turnScreenOff = false,
    this.stayAwake = false,
    this.alwaysOnTop = false,
    this.display,
  });

  final bool turnScreenOff;
  final bool stayAwake;

  /// 投屏窗口始终显示在其它窗口上面
  final bool alwaysOnTop;

  /// 投到手机上新建的虚拟屏幕，而不是镜像手机屏幕：电脑上和手机上各用各的应用
  final MirrorDisplayOptions? display;
}

// ───────────── 无线调试 ─────────────

sealed class WirelessRequest {
  const WirelessRequest();
}

class WirelessPairRequest extends WirelessRequest {
  const WirelessPairRequest({required this.host, required this.port, required this.code});

  final String host;
  final String port;
  final String code;
}

class WirelessConnectRequest extends WirelessRequest {
  const WirelessConnectRequest({required this.host, required this.port});

  final String host;
  final String port;
}

class WirelessDisconnectRequest extends WirelessRequest {
  const WirelessDisconnectRequest();
}

/// 插线时一键 `adb tcpip 5555` 切到无线
class WirelessFromUsbRequest extends WirelessRequest {
  const WirelessFromUsbRequest();
}

// ───────────── 刷写记录 ─────────────

/// root=刷入修补镜像，unroot=刷回原厂 boot / init_boot，restore=从 ROM 刷回指定的原厂分区，undo=撤销上一次刷写
enum FlashKind { root, unroot, restore, undo }

/// patched=修补后的镜像，stock=ROM / 手机里的原厂镜像
enum FlashSource { patched, stock }

class FlashPartition {
  const FlashPartition({required this.name, required this.source, required this.sha256});

  final String name;
  final FlashSource source;
  final String sha256;

  Map<String, Object?> toJson() => {'name': name, 'source': source.name, 'sha256': sha256};

  static FlashPartition fromJson(Map<String, Object?> json) => FlashPartition(
        name: json['name'] as String? ?? '',
        source: FlashSource.values.firstWhere(
          (s) => s.name == json['source'],
          orElse: () => FlashSource.stock,
        ),
        sha256: json['sha256'] as String? ?? '',
      );
}

/// 刷写时手机的系统版本；ro.build.date.utc 用来判断手机后来有没有升级过
class FlashBuild {
  const FlashBuild({this.buildId, this.romVersion, this.buildDateUtc});

  final String? buildId;
  final String? romVersion;
  final String? buildDateUtc;

  Map<String, Object?> toJson() => {
        if (buildId != null) 'buildId': buildId,
        if (romVersion != null) 'romVersion': romVersion,
        if (buildDateUtc != null) 'buildDateUtc': buildDateUtc,
      };

  static FlashBuild fromJson(Map<String, Object?> json) => FlashBuild(
        buildId: json['buildId'] as String?,
        romVersion: json['romVersion'] as String?,
        buildDateUtc: json['buildDateUtc'] as String?,
      );
}

/// 被覆盖分区的原厂镜像备份，撤销时刷回
class FlashBackup {
  const FlashBackup({required this.path, required this.sha256});

  final String path;
  final String sha256;

  Map<String, Object?> toJson() => {'path': path, 'sha256': sha256};

  static FlashBackup fromJson(Map<String, Object?> json) => FlashBackup(
        path: json['path'] as String? ?? '',
        sha256: json['sha256'] as String? ?? '',
      );
}

enum FlashStatus { started, ok, failed }

class FlashRecord {
  const FlashRecord({
    required this.id,
    required this.time,
    required this.serial,
    required this.kind,
    this.scheme,
    this.slot,
    required this.build,
    this.partitions = const [],
    this.backups = const {},
    required this.status,
    this.undone = false,
  });

  final String id;

  /// 毫秒时间戳
  final int time;
  final String serial;
  final FlashKind kind;

  /// Root 方案名
  final String? scheme;

  /// 刷写的槽位（a / b）
  final String? slot;
  final FlashBuild build;
  final List<FlashPartition> partitions;
  final Map<String, FlashBackup> backups;
  final FlashStatus status;

  /// 已经被撤销
  final bool undone;

  FlashRecord copyWith({FlashStatus? status, bool? undone}) => FlashRecord(
        id: id,
        time: time,
        serial: serial,
        kind: kind,
        scheme: scheme,
        slot: slot,
        build: build,
        partitions: partitions,
        backups: backups,
        status: status ?? this.status,
        undone: undone ?? this.undone,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'time': time,
        'serial': serial,
        'kind': kind.name,
        if (scheme != null) 'scheme': scheme,
        if (slot != null) 'slot': slot,
        'build': build.toJson(),
        'partitions': [for (final p in partitions) p.toJson()],
        'backups': {for (final e in backups.entries) e.key: e.value.toJson()},
        'status': status.name,
        if (undone) 'undone': true,
      };

  static FlashRecord fromJson(Map<String, Object?> json) => FlashRecord(
        id: json['id'] as String? ?? '',
        time: json['time'] is num ? (json['time'] as num).toInt() : 0,
        serial: json['serial'] as String? ?? '',
        kind: FlashKind.values.firstWhere((k) => k.name == json['kind'], orElse: () => FlashKind.root),
        scheme: json['scheme'] as String?,
        slot: json['slot'] as String?,
        build: FlashBuild.fromJson(json['build'] is Map ? Map<String, Object?>.from(json['build'] as Map) : const {}),
        partitions: [
          for (final p in (json['partitions'] as List? ?? const []))
            if (p is Map) FlashPartition.fromJson(Map<String, Object?>.from(p)),
        ],
        backups: {
          for (final e
              in (json['backups'] is Map ? (json['backups'] as Map).entries : const <MapEntry<Object?, Object?>>[]))
            if (e.value is Map) '${e.key}': FlashBackup.fromJson(Map<String, Object?>.from(e.value as Map)),
        },
        status: FlashStatus.values.firstWhere((s) => s.name == json['status'], orElse: () => FlashStatus.started),
        undone: json['undone'] == true,
      );
}

// ───────────── 开机诊断 ─────────────

class SlotState {
  const SlotState({this.successful, this.unbootable, this.retryCount});

  final bool? successful;
  final bool? unbootable;
  final int? retryCount;

  bool get isEmpty => successful == null && unbootable == null && retryCount == null;
}

/// 开机诊断采集到的设备状态。读不到的字段留空，规则按「未知」处理
class BootState {
  const BootState({
    required this.mode,
    this.serial,
    this.currentSlot,
    this.slots = const {},
    this.unlocked,
    this.criticalUnlocked,
    this.snapshotStatus,
    this.adbDuringBoot,
    this.bootCompleted,
    this.crashLog,
    this.root,
    this.notes = const [],
  });

  /// 采集时手机所处的模式
  final DeviceMode mode;
  final String? serial;

  /// 'a' / 'b'
  final String? currentSlot;

  /// 槽位名 → 状态
  final Map<String, SlotState> slots;
  final bool? unlocked;

  /// oem device-info 的 Device critical unlocked（只有 bootloader 下能读）
  final bool? criticalUnlocked;

  /// snapshot-update-status：none / snapshotted / merging 等
  final String? snapshotStatus;

  /// 卡开机时，开机过程中 adb 连上过
  final bool? adbDuringBoot;

  /// sys.boot_completed = 1
  final bool? bootCompleted;

  /// logcat -b crash 的最后几十行
  final String? crashLog;
  final String? root;

  /// 采集过程中的说明，例如哪些字段读不到
  final List<String> notes;
}

/// 用户看到的现象
enum BootSymptom {
  logo('一直停在开机 logo / 开机动画'),
  bootloop('进系统几秒后自动重启，反复循环'),
  crashdump('黑屏出现 QUALCOMM CrashDump Mode'),
  destroyed('出现 The current image have been destroyed'),
  recovery('自动进入 Recovery，提示无法启动系统');

  const BootSymptom(this.label);
  final String label;
}

/// 出问题前最后做的操作（用户选择；有刷写记录时预先选好）
enum LastAction {
  root('Root'),
  module('装模块'),
  ota('系统更新'),
  flash('刷系统'),
  unknown('不清楚');

  const LastAction(this.label);
  final String label;
}

/// disable=给每个模块写 disable 文件（可恢复），enable=删掉 disable 文件，remove=magisk --remove-modules（删除）
enum ModuleAction {
  disable('禁用全部模块'),
  enable('重新启用全部模块'),
  remove('删除全部 Magisk 模块');

  const ModuleAction(this.label);
  final String label;
}

// ───────────── 应用 ─────────────

class AppEntry {
  const AppEntry({
    required this.package,
    required this.label,
    this.cloned = false,
    this.system = false,
    this.removed = false,
    this.disabled = false,
    this.protected = false,
  });

  final String package;
  final String label;

  /// 已在双开空间（用户 999）中
  final bool cloned;

  /// 以下仅系统应用列表有：预装应用
  final bool system;

  /// 已对当前用户卸载（pm uninstall --user 0）
  final bool removed;

  /// 已停用
  final bool disabled;

  /// 系统必需组件，不允许卸载
  final bool protected;

  AppEntry withCloned(bool cloned) => copyWith(cloned: cloned);

  AppEntry copyWith({bool? cloned, bool? removed, bool? disabled}) => AppEntry(
        package: package,
        label: label,
        cloned: cloned ?? this.cloned,
        system: system,
        removed: removed ?? this.removed,
        disabled: disabled ?? this.disabled,
        protected: protected,
      );

  /// [package] 在 [others] 里是否存在（系统应用和用户应用列表合并时用）
  static List<AppEntry> merge(List<AppEntry> list, AppEntry entry) {
    final i = list.indexWhere((a) => a.package == entry.package);
    if (i < 0) {
      list.add(entry);
      return list;
    }
    final old = list[i];
    list[i] = AppEntry(
      package: entry.package,
      label: old.label.isNotEmpty ? old.label : entry.label,
      cloned: old.cloned || entry.cloned,
      system: old.system || entry.system,
      removed: old.removed || entry.removed,
      disabled: old.disabled || entry.disabled,
      protected: old.protected || entry.protected,
    );
    return list;
  }
}

/// status=只读状态，start=启动（没装时先下载安装），autostart=为免 Root 开机自启做好电脑这边能做的准备
enum ShizukuAction {
  status('检查 Shizuku 状态'),
  start('启动 Shizuku'),
  autostart('设置开机自启');

  const ShizukuAction(this.label);
  final String label;
}

class ShizukuState {
  const ShizukuState({
    required this.installed,
    this.version,
    required this.running,
    this.sdk,
    this.secureSettings,
    this.bootReceiver,
  });

  final bool installed;
  final String? version;

  /// shizuku_server 进程在运行
  final bool running;

  /// ro.build.version.sdk；免 Root 开机自启需要 33（Android 13）及以上
  final int? sdk;

  /// Shizuku 已获得 WRITE_SECURE_SETTINGS（开机自启时用它打开无线调试）
  final bool? secureSettings;

  /// Shizuku 的开机广播接收器没有被关掉
  final bool? bootReceiver;
}

/// 应用申请了、可以用 adb 授予的权限
class AppPermission {
  const AppPermission({required this.name, required this.label, required this.desc, required this.granted});

  final String name;
  final String label;
  final String desc;
  final bool granted;
}

/// 应用备份目录里的 backup.json
class AppBackupManifest {
  const AppBackupManifest({
    required this.package,
    required this.label,
    this.versionName,
    this.versionCode,
    required this.apk,
    this.data = const [],
    required this.time,
    this.model,
  });

  final String package;
  final String label;
  final String? versionName;
  final String? versionCode;

  /// 安装包文件名：单个 APK 是 app.apk，有分包时打成 app.apks
  final String apk;

  /// 应用数据的压缩包（需要 Root）：data.tgz 是 /data/data，data_de.tgz 是 /data/user_de/0
  final List<String> data;
  final int time;
  final String? model;

  Map<String, Object?> toJson() => {
        'package': package,
        'label': label,
        if (versionName != null) 'versionName': versionName,
        if (versionCode != null) 'versionCode': versionCode,
        'apk': apk,
        'data': data,
        'time': time,
        if (model != null) 'model': model,
      };

  static AppBackupManifest fromJson(Map<String, Object?> json) => AppBackupManifest(
        package: json['package'] as String? ?? '',
        label: json['label'] as String? ?? '',
        versionName: json['versionName'] as String?,
        versionCode: json['versionCode'] as String?,
        apk: json['apk'] as String? ?? '',
        data: [for (final d in (json['data'] as List? ?? const [])) '$d'],
        time: json['time'] is num ? (json['time'] as num).toInt() : 0,
        model: json['model'] as String?,
      );
}

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

class UnrootRequest extends OperationRequest {
  const UnrootRequest(this.options);
  final UnrootOptions options;
  @override
  String get description => '刷回原厂镜像';
}

class RestoreStockRequest extends OperationRequest {
  const RestoreStockRequest(this.options);
  final RestoreOptions options;
  @override
  String get description => '刷回原厂分区';
}

class UndoFlashRequest extends OperationRequest {
  const UndoFlashRequest();
  @override
  String get description => '撤销上一次刷写';
}

class BackupPartitionsRequest extends OperationRequest {
  const BackupPartitionsRequest(this.options);
  final BackupOptions options;
  @override
  String get description => options.source == BackupSource.device ? '备份关键分区' : '从 ROM 保存原厂镜像';
}

class DriverCheckRequest extends OperationRequest {
  const DriverCheckRequest();
  @override
  String get description => '检查驱动';
}

class ScreenshotRequest extends OperationRequest {
  const ScreenshotRequest();
  @override
  String get description => '截图';
}

class WirelessOpRequest extends OperationRequest {
  const WirelessOpRequest(this.request);
  final WirelessRequest request;
  @override
  String get description => '无线调试';
}

class ListRemoteRequest extends OperationRequest {
  const ListRemoteRequest(this.path);
  final String path;
  @override
  String get description => '浏览 $path';
}

class PushFilesRequest extends OperationRequest {
  const PushFilesRequest({required this.files, required this.to});
  final List<String> files;
  final String to;
  @override
  String get description => files.length == 1 ? '发送 1 个文件' : '发送 ${files.length} 个文件';
}

class PullFileRequest extends OperationRequest {
  const PullFileRequest(this.path);
  final String path;
  @override
  String get description => '接收 $path';
}

class BootCollectRequest extends OperationRequest {
  const BootCollectRequest({required this.waitAdb});
  final bool waitAdb;
  @override
  String get description => '开机诊断：读取设备状态';
}

enum SnapshotUpdateAction { cancel, merge }

class SnapshotUpdateRequest extends OperationRequest {
  const SnapshotUpdateRequest(this.action);
  final SnapshotUpdateAction action;
  @override
  String get description => action == SnapshotUpdateAction.cancel ? '取消未合并的更新' : '继续合并更新';
}

class ModulesRequest extends OperationRequest {
  const ModulesRequest(this.action);
  final ModuleAction action;
  @override
  String get description => action.label;
}

class InstallAppsRequest extends OperationRequest {
  const InstallAppsRequest(this.files);
  final List<String> files;
  @override
  String get description => files.length == 1 ? '安装 1 个应用' : '安装 ${files.length} 个应用';
}

class ExportDiagnosticsRequest extends OperationRequest {
  const ExportDiagnosticsRequest();
  @override
  String get description => '导出诊断信息';
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

class ListSystemAppsRequest extends OperationRequest {
  const ListSystemAppsRequest();
  @override
  String get description => '读取预装应用';
}

class DebloatRequest extends OperationRequest {
  const DebloatRequest(this.package, {required this.remove});
  final String package;
  final bool remove;
  @override
  String get description => remove ? '卸载 $package' : '恢复 $package';
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

class ShizukuRequest extends OperationRequest {
  const ShizukuRequest(this.action);
  final ShizukuAction action;
  @override
  String get description => action.label;
}

class ListUserAppsRequest extends OperationRequest {
  const ListUserAppsRequest();
  @override
  String get description => '读取可投屏的应用列表';
}

class FreezeAppRequest extends OperationRequest {
  const FreezeAppRequest(this.package, {required this.freeze});
  final String package;
  final bool freeze;
  @override
  String get description => freeze ? '冻结 $package' : '解冻 $package';
}

class AppPermissionsRequest extends OperationRequest {
  const AppPermissionsRequest(this.package);
  final String package;
  @override
  String get description => '读取 $package 的权限';
}

class GrantPermissionRequest extends OperationRequest {
  const GrantPermissionRequest(this.package, {required this.permission, required this.grant});
  final String package;
  final String permission;
  final bool grant;
  @override
  String get description => grant ? '授予 $permission' : '撤销 $permission';
}

class NetworkOpRequest extends OperationRequest {
  const NetworkOpRequest(this.request);
  final NetworkRequest request;
  @override
  String get description => switch (request) {
        NetworkStatusRequest() => '读取联网设置',
        NetworkCaptiveRequest(fix: true) => '修复联网检测地址',
        NetworkCaptiveRequest() => '恢复默认联网检测地址',
        NetworkDnsRequest() => '设置私人 DNS',
      };
}

class BackupAppRequest extends OperationRequest {
  const BackupAppRequest({required this.package, required this.label, required this.withData});
  final String package;
  final String label;
  final bool withData;
  @override
  String get description => '备份：$label';
}

class RestoreAppRequest extends OperationRequest {
  const RestoreAppRequest(this.dir);
  final String dir;
  @override
  String get description => '恢复应用';
}

class InstallModulesRequest extends OperationRequest {
  const InstallModulesRequest(this.files);
  final List<String> files;
  @override
  String get description => files.length == 1 ? '安装 1 个模块' : '安装 ${files.length} 个模块';
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
  const OperationResult({
    required this.ok,
    required this.message,
    this.outputPath,
    this.apps,
    this.edl,
    this.remote,
    this.drivers,
    this.bootState,
    this.shizuku,
    this.permissions,
    this.network,
  });

  const OperationResult.fail(this.message)
      : ok = false,
        outputPath = null,
        apps = null,
        edl = null,
        remote = null,
        drivers = null,
        bootState = null,
        shizuku = null,
        permissions = null,
        network = null;

  final bool ok;
  final String message;

  /// 修补后镜像的保存位置等附加产物
  final String? outputPath;

  /// listApps 的结果
  final List<AppEntry>? apps;

  /// 9008 检测 / 自检的结果
  final EdlState? edl;

  /// listRemote 的结果
  final RemoteListing? remote;

  /// driverCheck 的结果
  final List<DriverEntry>? drivers;

  /// bootCollect 的结果
  final BootState? bootState;

  /// shizuku 的结果
  final ShizukuState? shizuku;

  /// appPermissions / grantPermission 的结果
  final List<AppPermission>? permissions;

  /// network 的结果
  final NetworkState? network;
}

class RemoteListing {
  const RemoteListing({required this.path, required this.entries});

  final String path;
  final List<RemoteEntry> entries;
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
  const UpdateInfo({
    required this.current,
    this.latest,
    this.url,
    this.hasUpdate = false,
    this.canAuto = false,
    this.error,
  });

  final String current;
  final String? latest;
  final String? url;
  final bool hasUpdate;

  /// 安装版可以自动下载替换；便携版只能去发布页下载
  final bool canAuto;
  final String? error;
}
