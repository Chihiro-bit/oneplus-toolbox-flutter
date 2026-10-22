import 'dart:async';
import 'dart:typed_data';

import 'package:toolbox_commands/toolbox_commands.dart';
import 'package:toolbox_core/toolbox_core.dart';

import 'catalog_repository.dart';
import 'device_probe.dart';
import 'environment.dart';
import 'history.dart';
import 'known.dart';
import 'logfile.dart';
import 'ops/apps.dart' as apps;
import 'ops/appbackup.dart' as appbackup;
import 'ops/backup.dart' as backup;
import 'ops/basic.dart' as basic;
import 'ops/bootdiag.dart' as bootdiag;
import 'ops/context.dart';
import 'ops/diagnostics.dart' as diagnostics;
import 'ops/drivers.dart' as drivers;
import 'ops/edl.dart' as edl_op;
import 'ops/install.dart' as install;
import 'ops/media.dart' as media_op;
import 'ops/modules.dart' as modules;
import 'ops/network.dart' as network_op;
import 'ops/permissions.dart' as permissions;
import 'ops/rescue.dart' as rescue;
import 'ops/root.dart' as root_op;
import 'ops/shizuku.dart' as shizuku_op;
import 'ops/wireless.dart' as wireless_op;
import 'settings_store.dart';
import 'update_checker.dart' as update;

/// 界面与业务层之间唯一的接口，对应 TS 版主进程的 IPC 处理（src/main/index.ts）。
///
/// - 设备状态、日志、步骤提示、应用图标都以广播流推送
/// - 同一时间只允许一个操作，执行期间暂停设备轮询，由操作自己上报设备状态
class ToolboxService {
  ToolboxService(this.env)
      : tools = ToolPaths(env.binDir),
        _settings = SettingsStore(env.dataDir, defaultUpdateRepo: env.defaultUpdateRepo) {
    _catalog = CatalogRepository(env.dataDir, _settings);
    _probe = DeviceProbe(tools, KnownStore(env.dataDir));
    _history = FlashHistory(dataDir: env.dataDir, documentsDir: env.documentsDir);
    _logFile = LogFile(env.documentsDir);
  }

  final ToolboxEnvironment env;
  final ToolPaths tools;
  final SettingsStore _settings;
  late final CatalogRepository _catalog;
  late final DeviceProbe _probe;
  late final FlashHistory _history;
  late final LogFile _logFile;
  final _icons = apps.AppIconLoader();

  final _deviceCtrl = StreamController<DeviceInfo>.broadcast();
  final _logCtrl = StreamController<LogEntry>.broadcast();
  final _stepCtrl = StreamController<String>.broadcast();
  final _iconCtrl = StreamController<Map<String, Uint8List>>.broadcast();

  DeviceInfo _device = DeviceInfo.disconnected;
  CancelToken? _busy;
  Timer? _pollTimer;
  bool _disposed = false;
  String _lastKey = '';

  /// 当前设备状态
  DeviceInfo get device => _device;

  /// 设备状态变化（连接状态变化时先推一次基本信息，读到详情后再推一次）
  Stream<DeviceInfo> get deviceChanges => _deviceCtrl.stream;

  Stream<LogEntry> get logs => _logCtrl.stream;

  /// 当前操作的步骤提示
  Stream<String> get steps => _stepCtrl.stream;

  /// 应用图标分批到达：包名 → 图片字节（PNG / WebP / JPEG）
  Stream<Map<String, Uint8List>> get appIcons => _iconCtrl.stream;

  bool get busy => _busy != null;

  /// 开始轮询设备。先订阅各个流再调用，否则会错过启动时的日志。
  void start() {
    _logFile.prune();
    final missing = tools.missing();
    if (missing.isNotEmpty) {
      _log(LogLevel.error, '缺少工具：${missing.join(', ')}。开发环境请先运行 melos run fetch-tools');
    }
    _poll();
  }

  // ───────────── 设备轮询 ─────────────

  Future<void> _poll() async {
    if (_disposed) return;
    if (_busy == null) {
      try {
        final d = await _probe.detect();
        final key = d.connectionKey;
        if (key != _lastKey) {
          _lastKey = key;
          _setDevice(d);
          // 状态变化后补全详情（型号、版本、槽位、解锁状态）
          if (_busy == null) {
            final full = await _probe.describe(d);
            if (_lastKey == key && _busy == null) _setDevice(full);
          }
        }
      } catch (_) {
        // 轮询失败忽略，下一轮再试
      }
    }
    if (!_disposed) _pollTimer = Timer(const Duration(seconds: 2), _poll);
  }

  void _setDevice(DeviceInfo d) {
    _device = d;
    if (!_disposed) _deviceCtrl.add(d);
  }

  void _log(LogLevel level, String text) {
    final entry = LogEntry(DateTime.now(), level, text);
    if (!_disposed) _logCtrl.add(entry);
    _logFile.append(entry);
  }

  // ───────────── 操作 ─────────────

  /// 执行一个操作。预期内的失败、取消和意外错误都转成 ok=false 的结果，不会抛出。
  Future<OperationResult> run(OperationRequest req) async {
    if (_busy != null) return const OperationResult.fail('已有操作正在进行');
    final cancel = _busy = CancelToken();
    _log(LogLevel.step, '── 开始：${req.description} ──');
    final ctx = OpContext(
      cancel: cancel,
      log: _log,
      step: (t) {
        if (!_disposed) _stepCtrl.add(t);
        _log(LogLevel.step, t);
      },
      device: _setDevice,
      tools: tools,
      probe: _probe,
      env: env,
      history: _history,
      logFile: _logFile,
    );
    try {
      final result = await _dispatch(req, ctx);
      _log(result.ok ? LogLevel.ok : LogLevel.error, result.message);
      // 应用列表显示后在后台补全图标（TS 的 index.ts 对这三个请求都会触发）
      if (result.ok && (req is ListAppsRequest || req is ListSystemAppsRequest || req is ListUserAppsRequest)) {
        unawaited(_loadIcons());
      }
      return result;
    } catch (e) {
      final message = switch (e) {
        CancelledException() => '操作已取消',
        OpException(:final message) => message,
        _ => '发生错误：$e',
      };
      _log(LogLevel.error, message);
      return OperationResult.fail(message);
    } finally {
      _busy = null;
      _lastKey = ''; // 操作结束后强制刷新一次设备状态
    }
  }

  Future<OperationResult> _dispatch(OperationRequest req, OpContext ctx) {
    // 9008 关闭时界面上没有入口，这里再兜一层，防止旧界面或脚本调用
    if (!Features.edl &&
        (req is EdlDetectRequest ||
            req is EdlProbeRequest ||
            req is EdlFlashRequest ||
            req is EdlResetRequest ||
            (req is RebootRequest && req.target == RebootTarget.edl))) {
      throw const OpException('9008 / EDL 相关功能暂时停用');
    }
    return switch (req) {
      RebootRequest(:final target) => basic.reboot(target, ctx),
      UnlockRequest() => basic.setLock(ctx, unlock: true),
      RelockRequest() => basic.setLock(ctx, unlock: false),
      SwitchSlotRequest() => basic.switchSlot(ctx),
      RootRequest(:final options) => root_op.root(options, ctx, catalog: _catalog, env: env),
      UnrootRequest(:final options) => rescue.unroot(options, ctx),
      RestoreStockRequest(:final options) => rescue.restoreStock(options, ctx),
      UndoFlashRequest() => rescue.undoFlash(ctx),
      ModulesRequest(:final action) => rescue.modules(action, ctx),
      BackupPartitionsRequest(:final options) => backup.backupPartitions(options, ctx),
      BootCollectRequest(:final waitAdb) => bootdiag.bootCollect(ctx, waitAdb: waitAdb),
      SnapshotUpdateRequest(:final action) => bootdiag.snapshotUpdate(action, ctx),
      ListAppsRequest() => apps.listApps(ctx, _icons),
      ListSystemAppsRequest() => apps.listSystemApps(ctx),
      ListUserAppsRequest() => apps.listUserApps(ctx),
      DebloatRequest(:final package, :final remove, :final root) =>
        apps.debloat(package, ctx, remove: remove, root: root),
      FreezeAppRequest(:final package, :final freeze) => apps.freezeApp(package, ctx, freeze: freeze),
      CloneAppRequest(:final package, :final enable) => apps.cloneApp(package, ctx, enable: enable),
      AppPermissionsRequest(:final package) => permissions.appPermissions(package, ctx),
      GrantPermissionRequest(:final package, :final permission, :final grant) =>
        permissions.grantPermission(package, permission, ctx, grant: grant),
      BackupAppRequest(:final package, :final label, :final withData) =>
        appbackup.backupApp(package, label, ctx, withData: withData),
      RestoreAppRequest(:final dir) => appbackup.restoreApp(dir, ctx),
      InstallPlayRequest(:final apk) => apps.installPlay(apk, ctx),
      OtaUpdatesRequest(:final disable) => apps.otaUpdates(ctx, disable: disable),
      EdlDetectRequest() => edl_op.edlDetect(ctx),
      EdlProbeRequest(:final profile) => edl_op.edlProbe(profile, ctx),
      EdlFlashRequest(:final profile) => edl_op.edlFlash(profile, ctx),
      EdlResetRequest() => edl_op.edlReset(ctx),
      ScreenshotRequest() => media_op.screenshot(ctx),
      ListRemoteRequest(:final path) => media_op.listRemote(path, ctx),
      PushFilesRequest(:final files, :final to) => media_op.pushFiles(files, to, ctx),
      PullFileRequest(:final path) => media_op.pullFile(path, ctx),
      WirelessOpRequest(:final request) => wireless_op.wireless(request, ctx),
      ShizukuRequest(:final action) => shizuku_op.shizuku(action, ctx),
      InstallModulesRequest(:final files) => modules.installModules(files, ctx),
      NetworkOpRequest(:final request) => network_op.network(request, ctx),
      DriverCheckRequest() => drivers.driverCheck(ctx),
      ExportDiagnosticsRequest() => diagnostics.exportDiagnostics(ctx, catalog: _catalog),
      InstallAppsRequest(:final files) => install.installApps(files, ctx),
      // 这里不需要 TS 版 ops/index.ts 末尾那种「主进程不认识这个操作」的兜底分支：
      // OperationRequest 是 sealed 的，子类在编译期就已确定，漏掉任何一个都会编译不过。
    };
  }

  // ───────────── 投屏（独立进程，不走操作队列） ─────────────

  /// 投屏窗口是否还开着
  bool get mirrorRunning => media_op.mirrorRunning;

  /// 打开 scrcpy 投屏窗口。独立于操作队列（投屏期间可以照常做别的事），关掉窗口即结束。
  Future<OperationResult> startMirror(MirrorOptions options) => media_op.startMirror(options, tools, _probe, _log);

  /// 关掉投屏窗口
  void stopMirror() => media_op.stopMirror();

  /// 应用列表显示后在后台补全图标，独立于操作队列，失败只会少几个图标
  Future<void> _loadIcons() async {
    try {
      await _icons.load(tools.adb, (batch) {
        if (!_disposed) _iconCtrl.add(batch);
      });
    } catch (_) {}
  }

  /// 取消正在进行的操作
  void cancel() => _busy?.cancel();

  // ───────────── 方案目录、设置、更新 ─────────────

  Future<CatalogState> catalog({bool refresh = false}) => _catalog.get(refresh: refresh);

  Settings get settings => _settings.load();

  /// 窗口选择只保存本地偏好，不触发远程目录刷新。
  void rememberCloseBehavior(CloseBehavior behavior) => _settings.save(settings.copyWith(closeBehavior: behavior));

  /// 保存设置并按新地址重新读取方案目录。格式不正确时抛出 [SettingsException]。
  Future<Settings> saveSettings(Settings s) async {
    final saved = _settings.save(s);
    await _catalog.get(refresh: true);
    return saved;
  }

  Future<UpdateInfo> checkUpdate() => update.checkUpdate(current: env.appVersion, repo: _settings.load().updateRepo);

  // ───────────── 刷写记录与日志 ─────────────

  /// 这台设备的刷写记录（旧的在前）
  List<FlashRecord> history(String serial) => _history.history(serial);

  /// 还能撤销的最近一次刷写
  FlashRecord? undoableFlash(String serial) => _history.undoable(serial);

  /// 日志文件夹
  String get logDir => _logFile.dir;

  /// 连着多台设备时，选择要操作的那一台
  void selectDevice(String? serial) {
    _probe.selectDevice(serial);
    _lastKey = ''; // 下一轮轮询立即刷新
  }

  // ───────────── 退出 ─────────────

  /// 停止轮询、取消操作，并关闭 adb server，避免残留进程占用 5037 端口
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pollTimer?.cancel();
    _busy?.cancel();
    media_op.stopMirror();
    Adb(tools.adb).killServerSync();
    _deviceCtrl.close();
    _logCtrl.close();
    _stepCtrl.close();
    _iconCtrl.close();
  }
}
