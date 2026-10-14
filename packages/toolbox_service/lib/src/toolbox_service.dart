import 'dart:async';
import 'dart:typed_data';

import 'package:toolbox_commands/toolbox_commands.dart';
import 'package:toolbox_core/toolbox_core.dart';

import 'catalog_repository.dart';
import 'device_probe.dart';
import 'environment.dart';
import 'ops/apps.dart' as apps;
import 'ops/basic.dart' as basic;
import 'ops/context.dart';
import 'ops/root.dart' as root_op;
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
    _probe = DeviceProbe(tools);
  }

  final ToolboxEnvironment env;
  final ToolPaths tools;
  final SettingsStore _settings;
  late final CatalogRepository _catalog;
  late final DeviceProbe _probe;
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
    if (!_disposed) _logCtrl.add(LogEntry(DateTime.now(), level, text));
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
    );
    try {
      final result = await _dispatch(req, ctx);
      _log(result.ok ? LogLevel.ok : LogLevel.error, result.message);
      if (req is ListAppsRequest && result.ok) unawaited(_loadIcons());
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

  Future<OperationResult> _dispatch(OperationRequest req, OpContext ctx) => switch (req) {
        RebootRequest(:final target) => basic.reboot(target, ctx),
        UnlockRequest() => basic.setLock(ctx, unlock: true),
        RelockRequest() => basic.setLock(ctx, unlock: false),
        SwitchSlotRequest() => basic.switchSlot(ctx),
        RootRequest(:final options) => root_op.root(options, ctx, catalog: _catalog, env: env),
        ListAppsRequest() => apps.listApps(ctx, _icons),
        CloneAppRequest(:final package, :final enable) => apps.cloneApp(package, ctx, enable: enable),
        InstallPlayRequest(:final apk) => apps.installPlay(apk, ctx),
        OtaUpdatesRequest(:final disable) => apps.otaUpdates(ctx, disable: disable),
      };

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

  /// 保存设置并按新地址重新读取方案目录。格式不正确时抛出 [SettingsException]。
  Future<Settings> saveSettings(Settings s) async {
    final saved = _settings.save(s);
    await _catalog.get(refresh: true);
    return saved;
  }

  Future<UpdateInfo> checkUpdate() => update.checkUpdate(current: env.appVersion, repo: _settings.load().updateRepo);

  // ───────────── 退出 ─────────────

  /// 停止轮询、取消操作，并关闭 adb server，避免残留进程占用 5037 端口
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pollTimer?.cancel();
    _busy?.cancel();
    Adb(tools.adb).killServerSync();
    _deviceCtrl.close();
    _logCtrl.close();
    _stepCtrl.close();
    _iconCtrl.close();
  }
}
