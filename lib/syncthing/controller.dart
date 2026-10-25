import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/app_prefs.dart';
import '../core/native_bridge.dart';
import 'api_client.dart';
import 'models.dart';

/// 全局状态与操作中枢：连接生命周期、轮询、事件流、配置写操作。
///
/// UI 只通过本类读写 syncthing；REST 细节全部封装在 ApiClient / models。
class SyncthingController extends ChangeNotifier {
  SyncthingController({required this.prefs}) {
    native.init();
    native.states.listen(_onServiceState);
    native.logs.listen(_onProcessLog);
  }

  final AppPrefs prefs;
  final NativeBridge native = NativeBridge.instance;

  ApiClient? api;

  // ---- 生命周期状态 ----
  ServiceRunState serviceState = ServiceRunState.stopped;
  String? serviceError;
  bool apiReady = false;
  bool bootstrapping = false;
  ServiceInfo? info;

  // ---- 数据快照 ----
  Config? config;
  SystemStatus? status;
  Connections? connections = Connections.fromJson({});
  SystemVersion? version;
  Map<String, FolderStatus> folderStatuses = {};
  Map<String, Map<String, Completion>> completions = {}; // folder → device → %
  Map<String, DeviceStats> deviceStats = {};
  Map<String, List<FolderErrorEntry>> folderErrors = {}; // folder → 失败项
  List<PendingDevice> pendingDevices = [];
  Map<String, List<PendingFolder>> pendingFolders = {}; // deviceID → 待定文件夹
  List<RecentChange> recentChanges = [];

  /// 进程 stdout 日志行（含时间戳）。
  final List<ProcessLogLine> processLog = [];
  List<LogEntry> systemErrors = [];

  String? lastApiError;
  bool configNeedsRestart = false;

  // ---- 内部 ----
  Timer? _fastTimer;
  Timer? _slowTimer;
  int _lastEventId = 0;
  bool _eventsRunning = false;
  bool _disposed = false;

  bool get isRunning =>
      serviceState == ServiceRunState.running ||
      serviceState == ServiceRunState.starting;

  String get myID => status?.myID ?? '';

  DeviceConfig? get ownDevice {
    final id = myID;
    return id.isEmpty ? config?.devices.firstOrNull : config?.device(id);
  }

  // =========================================================================
  // 生命周期
  // =========================================================================

  /// 应用启动时调用：读取服务信息（首次会生成配置），按设置决定是否自动启动。
  Future<void> bootstrap() async {
    if (bootstrapping) return;
    bootstrapping = true;
    notifyListeners();
    try {
      info = await native.getServiceInfo();
      api = ApiClient(baseUrl: info!.baseUrl, apiKey: info!.apiKey);
      serviceState = (await native.state()).toRunState();
      if (prefs.autoStartOnOpen && serviceState == ServiceRunState.stopped) {
        await native.start();
      }
      _startLoops();
    } catch (e) {
      serviceError = '初始化失败: $e';
      serviceState = ServiceRunState.error;
    } finally {
      bootstrapping = false;
      notifyListeners();
    }
  }

  void _onServiceState(ServiceState s) {
    serviceState = s.runState;
    serviceError = s.message;
    if (s.runState == ServiceRunState.running) {
      _startLoops();
    } else {
      apiReady = false;
      // syncthing 重启后事件 ID 从 0 重新计数，必须重置并重新追赶，
      // 否则旧 since 值会让长轮询永远等不到事件（事件驱动全部失效）。
      _lastEventId = 0;
      // 累计字节数随重启归零，速率差分基准也要重置
      _ratePrevIn = -1;
      _ratePrevOut = -1;
      _ratePrevAt = null;
      connections?.inRate = 0;
      connections?.outRate = 0;
      _stopLoops();
    }
    notifyListeners();
    if (s.runState == ServiceRunState.running) {
      unawaited(refreshAll());
    }
  }

  void _onProcessLog(String raw) {
    if (raw.trim().isEmpty) return;
    final line = ProcessLogLine.parse(raw);
    processLog.add(line);
    if (processLog.length > 1000) processLog.removeRange(0, processLog.length - 1000);
    // stdout 中出现 API 就绪标记时可以立即探测
    if (!apiReady && (raw.contains('Access the GUI') || raw.contains('GUI and API listening'))) {
      unawaited(_probeReady());
    }
    notifyListeners();
  }

  Future<void> start() => native.start();

  /// 停止：REST 优雅关闭（等待落盘）→ 超时后服务兜底 SIGTERM。
  Future<void> stop() async {
    try {
      await api?.post('/rest/system/shutdown');
    } catch (_) {
      await native.stop();
      return;
    }
    // 等待进程自行退出（服务 watchdog 会把状态置为 stopped）
    for (var i = 0;
        i < 50 && serviceState != ServiceRunState.stopped;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (serviceState != ServiceRunState.stopped) {
      await native.stop();
    }
  }

  Future<void> restart() async {
    try {
      await api?.post('/rest/system/restart');
    } catch (_) {
      await stop();
      await Future<void>.delayed(const Duration(seconds: 2));
      await start();
    }
  }

  // =========================================================================
  // 轮询与事件
  // =========================================================================

  void _startLoops() {
    _fastTimer ??= Timer.periodic(const Duration(seconds: 5), (_) => _fastPoll());
    _slowTimer ??= Timer.periodic(const Duration(seconds: 30), (_) => _slowPoll());
    _fastTimer?.isActive;
    unawaited(_fastPoll());
    unawaited(_slowPoll());
    unawaited(_eventLoop());
  }

  void _stopLoops() {
    _fastTimer?.cancel();
    _fastTimer = null;
    _slowTimer?.cancel();
    _slowTimer = null;
  }

  Future<void> _probeReady() async {
    if (await api?.ping() == true) {
      apiReady = true;
      notifyListeners();
      unawaited(refreshAll());
    }
  }

  Future<void> _fastPoll() async {
    final client = api;
    if (client == null || !isRunning) return;
    if (!apiReady) {
      await _probeReady();
      return;
    }
    try {
      final results = await Future.wait([
        client.get('/rest/system/status'),
        client.get('/rest/system/connections'),
      ]);
      status = SystemStatus.fromJson(results[0] as Map<String, dynamic>);
      connections = Connections.fromJson(results[1] as Map<String, dynamic>);
      _computeRates();
      await _pollFolderStatuses();
      lastApiError = null;
      notifyListeners();
    } catch (e) {
      lastApiError = e.toString();
      if (e is ApiException && e.statusCode == 0) {
        // 连不上：进程可能已退出
        apiReady = false;
      }
      notifyListeners();
    }
  }

  // ---- 速率差分（v2 API 只有累计字节，1.25 起移除 *BytesPerSec 字段）----
  int _ratePrevIn = -1;
  int _ratePrevOut = -1;
  DateTime? _ratePrevAt;

  void _computeRates() {
    final c = connections;
    if (c == null) return;
    final now = DateTime.now();
    final inT = c.totalInBytes;
    final outT = c.totalOutBytes;
    if (_ratePrevAt == null || _ratePrevIn < 0) {
      // 首次采样或服务重启后：只记录基准，速率清零
      _ratePrevIn = inT;
      _ratePrevOut = outT;
      _ratePrevAt = now;
      c.inRate = 0;
      c.outRate = 0;
      return;
    }
    final dt = now.difference(_ratePrevAt!).inMicroseconds / 1e6;
    if (dt < 0.5) return; // 间隔太短，沿用上次速率
    c.inRate = (((inT - _ratePrevIn) / dt).round()).clamp(0, 1 << 40);
    c.outRate = (((outT - _ratePrevOut) / dt).round()).clamp(0, 1 << 40);
    _ratePrevIn = inT;
    _ratePrevOut = outT;
    _ratePrevAt = now;
  }

  Future<void> _pollFolderStatuses() async {
    final client = api;
    final cfg = config;
    if (client == null || cfg == null) return;
    for (final f in cfg.folders) {
      try {
        final r = await client
            .get('/rest/db/status', query: {'folder': f.id});
        folderStatuses[f.id] = FolderStatus.fromJson(r as Map<String, dynamic>);
      } catch (_) {}
    }
  }

  Future<void> _slowPoll() async {
    final client = api;
    if (client == null || !apiReady) return;
    try {
      await refreshConfig();
      await _pollCompletions();
      await _pollPending();
      await _pollStats();
      await _pollErrors();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshAll() async {
    await _fastPoll();
    await _slowPoll();
  }

  Future<void> refreshConfig() async {
    final client = api;
    if (client == null) return;
    final r = await client.get('/rest/config');
    config = Config(r as Map<String, dynamic>);
    final v = await client.get('/rest/system/version');
    version = SystemVersion.fromJson(v as Map<String, dynamic>);
    final insync = await client.get('/rest/config/restart-required');
    configNeedsRestart = (insync is Map && insync['restartRequired'] == true) ||
        (insync is bool && insync);
    notifyListeners();
  }

  Future<void> _pollCompletions() async {
    final client = api;
    final cfg = config;
    if (client == null || cfg == null) return;
    final newCompletions = <String, Map<String, Completion>>{};
    for (final f in cfg.folders) {
      final perDevice = <String, Completion>{};
      for (final d in f.devices) {
        if (d.deviceID == myID) continue;
        try {
          final r = await client.get('/rest/db/completion',
              query: {'folder': f.id, 'device': d.deviceID});
          perDevice[d.deviceID] =
              Completion.fromJson(r as Map<String, dynamic>);
        } catch (_) {}
      }
      newCompletions[f.id] = perDevice;
    }
    completions = newCompletions;
  }

  Future<void> _pollPending() async {
    final client = api;
    if (client == null) return;
    final pd = await client.get('/rest/cluster/pending/devices');
    pendingDevices = (pd as List? ?? [])
        .map((e) => PendingDevice.fromJson(e as Map<String, dynamic>))
        .toList();
    final pf = await client.get('/rest/cluster/pending/folders');
    final map = <String, List<PendingFolder>>{};
    for (final e in (pf as List? ?? [])) {
      final p = PendingFolder.fromJson(e as Map<String, dynamic>);
      map.putIfAbsent(p.deviceID, () => []).add(p);
    }
    pendingFolders = map;
  }

  Future<void> _pollStats() async {
    final client = api;
    if (client == null) return;
    final r = await client.get('/rest/stats/device');
    deviceStats = (r as Map? ?? {}).map(
      (k, v) => MapEntry(
          k.toString(), DeviceStats.fromJson(v as Map<String, dynamic>)),
    );
  }

  Future<void> _pollErrors() async {
    final client = api;
    if (client == null) return;
    final r = await client.get('/rest/system/error');
    systemErrors = ErrorListResponse.fromJson(r as Map<String, dynamic>).errors;
  }

  /// 事件长轮询主循环。崩溃自动重启（下一轮 fast poll 拉起）。
  Future<void> _eventLoop() async {
    if (_eventsRunning || _disposed) return;
    _eventsRunning = true;
    try {
      if (_lastEventId == 0) {
        // 只从最新事件开始（catch up），不回放历史。
        // 注意：服务可能尚未就绪（bootstrap 早于进程拉起），必须捕获连接错误，
        // 否则未处理异常会杀死整个循环（真机新装首启曾命中）。
        if (!apiReady || !isRunning) return;
        try {
          final latest = await api?.get('/rest/events',
              query: {'since': 0, 'limit': 1},
              timeout: const Duration(seconds: 20));
          if (latest is List && latest.isNotEmpty) {
            _lastEventId = (latest.last as Map)['id'] as int? ?? 0;
          }
        } catch (_) {
          return; // 未就绪/网络错误：退出，等下一次 _startLoops 重试
        }
      }
      while (!_disposed && apiReady && isRunning) {
        List<dynamic>? events;
        try {
          final body = await api?.getRaw('/rest/events', query: {
            'since': _lastEventId,
            'timeout': 50,
          }, timeout: const Duration(seconds: 70));
          events = body == null || body.isEmpty ? <dynamic>[] : jsonDecode(body) as List;
        } catch (_) {
          await Future<void>.delayed(const Duration(seconds: 3));
          continue;
        }
        for (final e in events) {
          final ev = SyncthingEvent.fromJson(e as Map<String, dynamic>);
          _lastEventId = ev.id > _lastEventId ? ev.id : _lastEventId;
          _handleEvent(ev);
        }
      }
    } finally {
      _eventsRunning = false;
    }
  }

  void _handleEvent(SyncthingEvent ev) {
    switch (ev.type) {
      case 'ItemFinished':
      case 'LocalChangeDetected':
      case 'RemoteChangeDetected':
        final change = RecentChange.fromEvent(ev);
        if (change != null) {
          recentChanges.insert(0, change);
          if (recentChanges.length > 100) {
            recentChanges.removeRange(100, recentChanges.length);
          }
        }
      case 'ConfigSaved':
        unawaited(refreshConfig());
      case 'FolderSummary':
      case 'StateChanged':
      case 'FolderCompletion':
        final folder = ev.data['folder'] as String?;
        if (folder != null) {
          unawaited(_refreshFolder(folder));
        }
        if (ev.type == 'FolderCompletion') {
          unawaited(_pollCompletions());
        }
      case 'FolderErrors':
        final folder = ev.data['folder'] as String?;
        if (folder != null) unawaited(refreshFolderErrors(folder));
      case 'DeviceConnected':
      case 'DeviceDisconnected':
      case 'DeviceRejected':
      case 'ClusterConfigReceived':
        unawaited(_fastPoll());
        if (ev.type == 'DeviceRejected' || ev.type == 'ClusterConfigReceived') {
          unawaited(_pollPending());
        }
      case 'SaveConflict':
      case 'FolderRejected':
        unawaited(_pollPending());
    }
    notifyListeners();
  }

  Future<void> _refreshFolder(String folderId) async {
    final client = api;
    if (client == null || !apiReady) return;
    try {
      final r = await client.get('/rest/db/status', query: {'folder': folderId});
      folderStatuses[folderId] = FolderStatus.fromJson(r as Map<String, dynamic>);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshFolderErrors(String folderId) async {
    final client = api;
    if (client == null) return;
    try {
      final r = await client.get('/rest/folder/errors', query: {'folder': folderId});
      folderErrors[folderId] = FolderErrorsLike.parse(r);
      notifyListeners();
    } catch (_) {}
  }

  // =========================================================================
  // 配置写操作（全部写后刷新）
  // =========================================================================

  Future<void> saveFolder(FolderConfig folder) async {
    final existing = config?.folder(folder.id) != null;
    if (existing) {
      await api!.put('/rest/config/folders/${folder.id}', body: folder.toJson());
    } else {
      await api!.post('/rest/config/folders', body: folder.toJson());
    }
    await refreshConfig();
    await _pollFolderStatuses();
  }

  Future<void> deleteFolder(String id) async {
    await api!.delete('/rest/config/folders/$id');
    folderStatuses.remove(id);
    await refreshConfig();
  }

  Future<void> saveDevice(DeviceConfig device) async {
    final existing = config?.device(device.deviceID) != null;
    if (existing) {
      await api!
          .put('/rest/config/devices/${device.deviceID}', body: device.toJson());
    } else {
      await api!.post('/rest/config/devices', body: device.toJson());
    }
    await refreshConfig();
  }

  Future<void> deleteDevice(String id) async {
    await api!.delete('/rest/config/devices/$id');
    await refreshConfig();
  }

  Future<void> patchOptions(Map<String, dynamic> patch) async {
    await api!.patch('/rest/config/options', body: patch);
    await refreshConfig();
  }

  Future<void> putOptions(Map<String, dynamic> options) async {
    await api!.put('/rest/config/options', body: options);
    await refreshConfig();
  }

  Future<void> putGui(Map<String, dynamic> gui) async {
    await api!.put('/rest/config/gui', body: gui);
    await refreshConfig();
  }

  /// 高级模式：整份配置 JSON 写回。
  Future<void> putRawConfig(Map<String, dynamic> cfg) async {
    await api!.put('/rest/config', body: cfg);
    await refreshConfig();
  }

  // =========================================================================
  // 模板（新建文件夹/设备时用 syncthing 自己的默认值，升级后字段自动跟随）
  // =========================================================================

  Map<String, dynamic>? _folderTemplate;
  Map<String, dynamic>? _deviceTemplate;

  /// 默认文件夹模板（来自 /rest/config/defaults/folder），失败时用内置兜底。
  Future<Map<String, dynamic>> folderTemplate() async {
    if (_folderTemplate != null) return _folderTemplate!;
    try {
      final r = await api!.get('/rest/config/defaults/folder');
      _folderTemplate = r as Map<String, dynamic>;
    } catch (_) {
      _folderTemplate = FolderConfig.create('').toJson();
    }
    return _folderTemplate!;
  }

  /// 默认设备模板（来自 /rest/config/defaults/device）。
  Future<Map<String, dynamic>> deviceTemplate() async {
    if (_deviceTemplate != null) return _deviceTemplate!;
    try {
      final r = await api!.get('/rest/config/defaults/device');
      _deviceTemplate = r as Map<String, dynamic>;
    } catch (_) {
      _deviceTemplate = DeviceConfig.create('').toJson();
    }
    return _deviceTemplate!;
  }

  // =========================================================================
  // 动作
  // =========================================================================

  Future<void> rescanFolder(String id, {String? subpath}) async {
    await api!.post('/rest/db/scan',
        body: subpath == null ? {'folder': id} : {'folder': id, 'sub': subpath});
  }

  Future<void> rescanAll() async {
    for (final f in config?.folders ?? <FolderConfig>[]) {
      if (!f.paused) {
        try {
          await rescanFolder(f.id);
        } catch (_) {}
      }
    }
  }

  Future<void> overrideFolder(String id) => api!.post('/rest/db/override', body: {'folder': id});

  Future<void> revertFolder(String id) => api!.post('/rest/db/revert', body: {'folder': id});

  Future<void> pauseFolder(String id, bool paused) async {
    final f = config?.folder(id);
    if (f == null) return;
    f.paused = paused;
    await saveFolder(f);
  }

  Future<void> pauseDevice(String id, bool paused) async {
    final d = config?.device(id);
    if (d == null) return;
    d.paused = paused;
    await saveDevice(d);
  }

  Future<void> clearErrors() async {
    await api!.post('/rest/system/error/clear');
    await _pollErrors();
  }

  Future<void> acceptPendingDevice(String deviceID) async {
    final d = DeviceConfig.create(deviceID);
    final pd = pendingDevices.where((p) => p.deviceID == deviceID).firstOrNull;
    if (pd != null && pd.name.isNotEmpty) d.name = pd.name;
    await saveDevice(d);
    await _pollPending();
  }

  Future<void> dismissPendingDevice(String deviceID) async {
    await api!.delete('/rest/cluster/pending/devices', query: {'device': deviceID});
    await _pollPending();
  }

  Future<void> acceptPendingFolder(String folderId, String fromDeviceID,
      {String? label, String path = ''}) async {
    final f = FolderConfig.create(folderId);
    f.label = label ?? '';
    f.path = path;
    f.devices = [
      FolderDeviceRef(deviceID: myID),
      FolderDeviceRef(deviceID: fromDeviceID),
    ];
    await saveFolder(f);
    await _pollPending();
  }

  Future<void> dismissPendingFolder(String folderId, String fromDeviceID) async {
    await api!.delete('/rest/cluster/pending/folders',
        query: {'folder': folderId, 'device': fromDeviceID});
    await _pollPending();
  }

  /// 设置 usage report 同意状态（0 拒绝 / 1 同意）。
  Future<void> setUsageReport(bool accepted) =>
      patchOptions({'urAccepted': accepted ? 1 : 0});

  // ---- 文件夹内浏览 / 忽略 / 版本 ----

  Future<List<BrowseEntry>> browse(String folder, String prefix) async {
    // v2 返回对象数组：{name, type: FILE_INFO_TYPE_*, modTime, size, children?}
    // levels=1 每次只取一层（官方文档提示此调用开销大）
    final r = await api!.get('/rest/db/browse', query: {
      'folder': folder,
      if (prefix.isNotEmpty) 'prefix': prefix,
      'levels': 1,
    });
    return (r as List? ?? const [])
        .map((e) => BrowseEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<String>> getIgnores(String folder) async {
    final r = await api!.get('/rest/db/ignores', query: {'folder': folder});
    return ((r as Map?)?['ignore'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
  }

  Future<void> setIgnores(String folder, List<String> lines) async {
    await api!.post('/rest/db/ignores',
        body: {'ignore': lines}, query: {'folder': folder});
  }

  /// 测试忽略规则：返回 (匹配的规则, 是否忽略)。
  Future<({List<String> matched, bool ignored})> matchIgnores(
      String folder, String pattern) async {
    final r = await api!.post(
      '/rest/db/ignores?check',
      body: {'patterns': [pattern]},
      query: {'folder': folder},
    );
    final m = r as Map? ?? {};
    return (
      matched: (m['matched'] as List? ?? []).map((e) => e.toString()).toList(),
      ignored: m['ignored'] as bool? ?? false,
    );
  }

  /// 文件的历史版本（versioning 恢复界面）。返回 文件路径 → 版本列表。
  Future<Map<String, List<FileVersion>>> folderVersions(String folder) async {
    final r = await api!.get('/rest/folder/versions', query: {'folder': folder});
    return (r as Map? ?? {}).map((k, v) => MapEntry(
          k.toString(),
          (v as List? ?? [])
              .map((e) => FileVersion.fromJson(e as Map<String, dynamic>))
              .toList(),
        ));
  }

  /// 恢复选中的版本。versions: 文件路径 → 要恢复到的 versionTime（null=跳过）。
  Future<void> restoreVersions(
      String folder, Map<String, int?> versions) async {
    await api!.post('/rest/folder/versions',
        body: {'restores': versions}, query: {'folder': folder});
  }

  Future<String> validateDeviceId(String id) async {
    final r = await api!.get('/rest/svc/deviceid', query: {'id': id});
    final m = r as Map? ?? {};
    if (m['error'] != null && (m['error'] as String).isNotEmpty) {
      throw Exception(m['error']);
    }
    return m['id'] as String? ?? id;
  }

  Future<Map<String, dynamic>> usageReportPreview() async {
    final r = await api!.get('/rest/svc/report');
    return (r as Map?)?.cast<String, dynamic>() ?? {};
  }

  Future<List<String>> logLevels() async {
    final r = await api!.get('/rest/system/loglevels');
    final m = (r as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    return (m['enabled'] as List? ?? const []).map((e) => e.toString()).toList();
  }

  Future<void> setLogLevel(String name, bool enabled) async {
    await api!.post('/rest/system/loglevels',
        body: {'enabled': [if (enabled) name], 'disabled': [if (!enabled) name]});
  }

  Future<List<String>> browseFsPath(String current) async {
    final r = await api!
        .get('/rest/system/browse', query: {'current': current});
    return (r as List? ?? []).map((e) => e.toString()).toList();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopLoops();
    api?.close();
    super.dispose();
  }
}

extension on String {
  ServiceRunState toRunState() => switch (this) {
        'starting' => ServiceRunState.starting,
        'running' => ServiceRunState.running,
        'error' => ServiceRunState.error,
        _ => ServiceRunState.stopped,
      };
}

/// 最近更改条目（Local/RemoteChangeDetected 事件）。
class RecentChange {
  RecentChange({
    required this.time,
    required this.folderId,
    required this.folderLabel,
    required this.action,
    required this.type,
    required this.path,
    required this.byDevice,
    required this.local,
  });

  final DateTime time;
  final String folderId;
  final String folderLabel;

  /// added / modified / deleted / conflicted-copy? (mapped)
  final String action;

  /// file / dir / symlink
  final String type;
  final String path;
  final String byDevice;
  final bool local;

  static RecentChange? fromEvent(SyncthingEvent ev) {
    final d = ev.data;
    final path = d['path'] as String?;
    if (path == null) return null;
    final action = d['action'] as String? ?? d['modType'] as String? ?? '';
    final mapAction = {
      'add': 'added',
      'touch': 'added',
      'update': 'modified',
      'delete': 'deleted',
    };
    return RecentChange(
      time: ev.time,
      folderId: d['folder'] as String? ?? '',
      folderLabel: d['folderLabel'] as String? ?? d['label'] as String? ?? '',
      action: mapAction[action] ?? action,
      type: d['type'] as String? ?? (d['itemType'] as String? ?? 'file'),
      path: path,
      byDevice: d['device'] as String? ?? (d['modifiedBy'] as String? ?? ''),
      local: ev.type == 'LocalChangeDetected' || ev.type == 'ItemFinished',
    );
  }
}

/// 进程 stdout 日志行（已结构化解析 v2 格式：
/// `2026-10-25 01:08:21 INF 消息 (k=v ... log.pkg=包名)`）。
class ProcessLogLine {
  ProcessLogLine._(this.time, this.level, this.pkg, this.text);

  /// 原始时间戳（无则取本地时间）
  final DateTime time;

  /// INF / WRN / ERR / DBG / ''（无法识别时）
  final String level;

  /// 输出该日志的 syncthing 内部包（log.pkg）
  final String pkg;

  /// 正文（已去掉时间戳/等级前缀与 log.pkg 后缀）
  final String text;

  static final _re = RegExp(
      r'^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) (INF|WRN|ERR|DBG|WARNING|ERROR|INFO|DEBUG) (.*)$');

  static ProcessLogLine parse(String raw) {
    var time = DateTime.now();
    var level = '';
    var rest = raw;
    final m = _re.firstMatch(raw);
    if (m != null) {
      time = DateTime.tryParse(m.group(1)!) ?? time;
      level = switch (m.group(2) ?? '') {
        'WARNING' => 'WRN',
        'ERROR' => 'ERR',
        'INFO' => 'INF',
        'DEBUG' => 'DBG',
        final l => l,
      };
      rest = m.group(3)!;
    }
    var pkg = '';
    final pkgMatch = RegExp(r'log\.pkg=([A-Za-z0-9._-]+)\)?').firstMatch(rest);
    if (pkgMatch != null) {
      pkg = pkgMatch.group(1)!;
      rest = rest.replaceFirst(RegExp(r'\s*\(?log\.pkg=[A-Za-z0-9._-]+\)?'), '');
    }
    return ProcessLogLine._(time, level, pkg, rest.trim());
  }

  String get timeLabel {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  /// 完整可复制文本。
  String get display =>
      '${time.toIso8601String().substring(0, 19)} ${level.isEmpty ? '---' : level} $text${pkg.isEmpty ? '' : ' ($pkg)'}';
}

/// /rest/folder/errors 兼容 v1(list) 与 v2({data, errors}) 两种形状。
class FolderErrorsLike {
  static List<FolderErrorEntry> parse(dynamic r) {
    if (r is List) {
      return r
          .map((e) => FolderErrorEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    final m = r as Map? ?? {};
    final list = m['errors'] as List? ?? [];
    return list
        .map((e) => FolderErrorEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
