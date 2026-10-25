/// Syncthing 配置与运行状态的 Dart 模型。
///
/// 设计原则（与升级友好性直接相关）：
/// - 配置类（FolderConfig / DeviceConfig / GuiConfig / OptionsConfig / Config）
///   以 `raw` JSON 为唯一事实源，字段用类型化 getter/setter 读写 raw。
///   这样未知/新增字段在「读取→编辑→写回」全链路无损保留，
///   Syncthing 升级引入新配置项时本壳不会丢失它们。
/// - 状态类（SystemStatus / FolderStatus 等）是不可变快照，构造即解析，容错。
/// - 所有 fromJson 均不抛异常：类型不符/缺失时用默认值。
library;

import 'dart:convert';

// ---------------------------------------------------------------------------
// 配置（/rest/config 及其子对象）— raw 为事实源
// ---------------------------------------------------------------------------

class FolderDeviceRef {
  FolderDeviceRef({required this.deviceID, this.introducedBy = ''});

  final String deviceID;
  String introducedBy;

  factory FolderDeviceRef.fromJson(Map<String, dynamic> j) => FolderDeviceRef(
        deviceID: j['deviceID'] as String? ?? '',
        introducedBy: j['introducedBy'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'deviceID': deviceID,
        'introducedBy': introducedBy,
      };
}

class VersioningConfig {
  VersioningConfig(Map<String, dynamic> j) : raw = j;

  final Map<String, dynamic> raw;

  /// '', 'trashcan', 'simple', 'snapshot', 'staggered', 'external'
  String get type => raw['type'] as String? ?? '';
  set type(String v) => raw['type'] = v;

  /// 返回「活」的参数表：首次访问把 raw 中的 Map 转换为 Map<String,String>
  /// 并写回，之后返回同一实例——UI 直接 `params[k]=v` 修改能落到 raw。
  /// 注意：不能用 `p?.map(...)`——p 是 dynamic 会丢失泛型推断得到
  /// Map<dynamic,dynamic>（实测踩坑），必须显式循环。
  Map<String, String> get params {
    final p = raw['params'];
    if (p is Map<String, String>) return p;
    final converted = <String, String>{};
    if (p is Map) {
      for (final e in p.entries) {
        converted[e.key.toString()] = e.value.toString();
      }
    }
    raw['params'] = converted;
    return converted;
  }

  set params(Map<String, String> v) => raw['params'] = v;

  bool get enabled => type.isNotEmpty && type != 'none';

  factory VersioningConfig.empty() => VersioningConfig({'type': '', 'params': {}});
}

class FolderConfig {
  FolderConfig(this.raw);

  final Map<String, dynamic> raw;

  static FolderConfig create(String id) => FolderConfig({
        'id': id,
        'label': '',
        'filesystemType': 'basic',
        'type': 'sendreceive',
        'devices': [],
        'rescanIntervalS': 3600,
        'fsWatcherEnabled': true,
        'fsWatcherDelayS': 10,
        'ignorePerms': false,
        'autoNormalize': true,
        'minDiskFree': {'value': 1, 'unit': '%'},
        'versioning': {'type': '', 'params': {}},
        'copiers': 0,
        'pullerMaxPendingKiB': 0,
        'hashers': 0,
        'order': 'random',
        'maxConflicts': 10,
        'disableSparseFiles': false,
        'disableTempIndexes': false,
        'paused': false,
        'weakHashThresholdPct': 25,
        'markerName': '.stfolder',
        'copyOwnership': false,
        'modTimeWindowS': 0,
        'maxConcurrentWrites': 2,
        'detectRenames': false,
      });

  String get id => raw['id'] as String? ?? '';
  set id(String v) => raw['id'] = v;

  String get label => raw['label'] as String? ?? '';
  set label(String v) => raw['label'] = v;

  String get path => raw['path'] as String? ?? '';
  set path(String v) => raw['path'] = v;

  /// sendreceive / sendonly / receiveonly
  String get type => raw['type'] as String? ?? 'sendreceive';
  set type(String v) => raw['type'] = v;

  List<FolderDeviceRef> get devices => (raw['devices'] as List? ?? [])
      .map((e) => FolderDeviceRef.fromJson(e as Map<String, dynamic>))
      .toList();
  set devices(List<FolderDeviceRef> v) =>
      raw['devices'] = v.map((d) => d.toJson()).toList();

  bool deviceShared(String deviceID) =>
      devices.any((d) => d.deviceID == deviceID);

  int get rescanIntervalS => _int(raw['rescanIntervalS'], 3600);
  set rescanIntervalS(int v) => raw['rescanIntervalS'] = v;

  bool get fsWatcherEnabled => _bool(raw['fsWatcherEnabled'], true);
  set fsWatcherEnabled(bool v) => raw['fsWatcherEnabled'] = v;

  int get fsWatcherDelayS => _int(raw['fsWatcherDelayS'], 10);
  set fsWatcherDelayS(int v) => raw['fsWatcherDelayS'] = v;

  bool get ignorePerms => _bool(raw['ignorePerms'], false);
  set ignorePerms(bool v) => raw['ignorePerms'] = v;

  bool get autoNormalize => _bool(raw['autoNormalize'], true);
  set autoNormalize(bool v) => raw['autoNormalize'] = v;

  VersioningConfig get versioning =>
      VersioningConfig(raw['versioning'] as Map<String, dynamic>? ?? {'type': '', 'params': {}});

  /// random / alphabetic / smallestFirst / largestFirst / oldestFirst / newestFirst
  String get order => raw['order'] as String? ?? 'random';
  set order(String v) => raw['order'] = v;

  bool get ignoreDelete => _bool(raw['ignoreDelete'], false);
  set ignoreDelete(bool v) => raw['ignoreDelete'] = v;

  int get maxConflicts => _int(raw['maxConflicts'], 10);
  set maxConflicts(int v) => raw['maxConflicts'] = v;

  bool get disableSparseFiles => _bool(raw['disableSparseFiles'], false);
  set disableSparseFiles(bool v) => raw['disableSparseFiles'] = v;

  bool get disableTempIndexes => _bool(raw['disableTempIndexes'], false);
  set disableTempIndexes(bool v) => raw['disableTempIndexes'] = v;

  bool get paused => _bool(raw['paused'], false);
  set paused(bool v) => raw['paused'] = v;

  bool get copyOwnership => _bool(raw['copyOwnership'], false);
  set copyOwnership(bool v) => raw['copyOwnership'] = v;

  bool get detectRenames => _bool(raw['detectRenames'], false);
  set detectRenames(bool v) => raw['detectRenames'] = v;

  int get maxConcurrentWrites => _int(raw['maxConcurrentWrites'], 2);
  set maxConcurrentWrites(int v) => raw['maxConcurrentWrites'] = v;

  String get displayName => label.isEmpty ? id : label;

  Map<String, dynamic> toJson() => raw;
}

class DeviceConfig {
  DeviceConfig(this.raw);

  final Map<String, dynamic> raw;

  static DeviceConfig create(String deviceID) => DeviceConfig({
        'deviceID': deviceID,
        'name': '',
        'addresses': ['dynamic'],
        'compression': 'metadata',
        'certName': '',
        'introducer': false,
        'skipIntroductionRemovals': false,
        'introducedBy': '',
        'paused': false,
        'allowedNetworks': [],
        'autoAcceptFolders': false,
        'maxSendKbps': 0,
        'maxRecvKbps': 0,
      });

  String get deviceID => raw['deviceID'] as String? ?? '';
  String get name => raw['name'] as String? ?? '';
  set name(String v) => raw['name'] = v;

  List<String> get addresses => (raw['addresses'] as List? ?? const ['dynamic'])
      .map((e) => e.toString())
      .toList();
  set addresses(List<String> v) => raw['addresses'] = v;

  /// metadata / always / never
  String get compression => raw['compression'] as String? ?? 'metadata';
  set compression(String v) => raw['compression'] = v;

  String get certName => raw['certName'] as String? ?? '';
  set certName(String v) => raw['certName'] = v;

  bool get introducer => _bool(raw['introducer'], false);
  set introducer(bool v) => raw['introducer'] = v;

  bool get skipIntroductionRemovals =>
      _bool(raw['skipIntroductionRemovals'], false);
  set skipIntroductionRemovals(bool v) => raw['skipIntroductionRemovals'] = v;

  String get introducedBy => raw['introducedBy'] as String? ?? '';

  bool get paused => _bool(raw['paused'], false);
  set paused(bool v) => raw['paused'] = v;

  List<String> get allowedNetworks =>
      (raw['allowedNetworks'] as List? ?? []).map((e) => e.toString()).toList();
  set allowedNetworks(List<String> v) => raw['allowedNetworks'] = v;

  bool get autoAcceptFolders => _bool(raw['autoAcceptFolders'], false);
  set autoAcceptFolders(bool v) => raw['autoAcceptFolders'] = v;

  int get maxSendKbps => _int(raw['maxSendKbps'], 0);
  set maxSendKbps(int v) => raw['maxSendKbps'] = v;

  int get maxRecvKbps => _int(raw['maxRecvKbps'], 0);
  set maxRecvKbps(int v) => raw['maxRecvKbps'] = v;

  String get displayName => name.isEmpty ? deviceID : name;

  Map<String, dynamic> toJson() => raw;
}

class GuiConfig {
  GuiConfig(this.raw);

  final Map<String, dynamic> raw;

  bool get enabled => _bool(raw['enabled'], true);
  set enabled(bool v) => raw['enabled'] = v;

  String get address => raw['address'] as String? ?? '127.0.0.1:8384';
  set address(String v) => raw['address'] = v;

  String get user => raw['user'] as String? ?? '';
  set user(String v) => raw['user'] = v;

  String get password => raw['password'] as String? ?? '';
  set password(String v) => raw['password'] = v;

  String get apiKey => raw['apiKey'] as String? ?? '';

  String get theme => raw['theme'] as String? ?? 'default';

  bool get debugging => _bool(raw['debugging'], false);
  set debugging(bool v) => raw['debugging'] = v;

  bool get insecureAdminAccess => _bool(raw['insecureAdminAccess'], false);
  set insecureAdminAccess(bool v) => raw['insecureAdminAccess'] = v;

  Map<String, dynamic> toJson() => raw;
}

class OptionsConfig {
  OptionsConfig(this.raw);

  final Map<String, dynamic> raw;

  List<String> get listenAddresses =>
      (raw['listenAddresses'] as List? ?? ['dynamic'])
          .map((e) => e.toString())
          .toList();
  set listenAddresses(List<String> v) => raw['listenAddresses'] = v;

  bool get globalAnnounceEnabled => _bool(raw['globalAnnounceEnabled'], true);
  set globalAnnounceEnabled(bool v) => raw['globalAnnounceEnabled'] = v;

  bool get localAnnounceEnabled => _bool(raw['localAnnounceEnabled'], true);
  set localAnnounceEnabled(bool v) => raw['localAnnounceEnabled'] = v;

  int get localAnnouncePort => _int(raw['localAnnouncePort'], 21027);
  set localAnnouncePort(int v) => raw['localAnnouncePort'] = v;

  bool get relaysEnabled => _bool(raw['relaysEnabled'], true);
  set relaysEnabled(bool v) => raw['relaysEnabled'] = v;

  int get relayReconnectIntervalM => _int(raw['relayReconnectIntervalM'], 10);
  set relayReconnectIntervalM(int v) => raw['relayReconnectIntervalM'] = v;

  int get startupDelay => _int(raw['startupDelay'], 0);
  set startupDelay(int v) => raw['startupDelay'] = v;

  bool get natEnabled => _bool(raw['natEnabled'], true);
  set natEnabled(bool v) => raw['natEnabled'] = v;

  /// v2: -1 未决定 / 0 拒绝 / 1 同意 usage report
  int get urAccepted => _int(raw['urAccepted'], -1);
  set urAccepted(int v) => raw['urAccepted'] = v;

  int get maxSendKbps => _int(raw['maxSendKbps'], 0);
  set maxSendKbps(int v) => raw['maxSendKbps'] = v;

  int get maxRecvKbps => _int(raw['maxRecvKbps'], 0);
  set maxRecvKbps(int v) => raw['maxRecvKbps'] = v;

  bool get restartOnWakeup => _bool(raw['restartOnWakeup'], true);
  set restartOnWakeup(bool v) => raw['restartOnWakeup'] = v;

  bool get limitBandwidthInLan => _bool(raw['limitBandwidthInLan'], false);
  set limitBandwidthInLan(bool v) => raw['limitBandwidthInLan'] = v;

  int get progressUpdateIntervalS => _int(raw['progressUpdateIntervalS'], 5);
  set progressUpdateIntervalS(int v) => raw['progressUpdateIntervalS'] = v;

  bool get crashesEnabled => _bool(raw['crashesEnabled'], false);
  set crashesEnabled(bool v) => raw['crashesEnabled'] = v;

  bool get upgraderEnabled => _bool(raw['upgraderEnabled'], false);
  set upgraderEnabled(bool v) => raw['upgraderEnabled'] = v;

  Map<String, dynamic> toJson() => raw;
}

class Config {
  Config(this.raw);

  final Map<String, dynamic> raw;

  factory Config.empty() => Config({
        'version': 0,
        'folders': [],
        'devices': [],
        'gui': {},
        'options': {},
        'defaults': {},
      });

  int get version => _int(raw['version'], 0);

  List<FolderConfig> get folders => (raw['folders'] as List? ?? [])
      .map((e) => FolderConfig(e as Map<String, dynamic>))
      .toList();
  set folders(List<FolderConfig> v) =>
      raw['folders'] = v.map((f) => f.toJson()).toList();

  List<DeviceConfig> get devices => (raw['devices'] as List? ?? [])
      .map((e) => DeviceConfig(e as Map<String, dynamic>))
      .toList();
  set devices(List<DeviceConfig> v) =>
      raw['devices'] = v.map((d) => d.toJson()).toList();

  GuiConfig get gui => GuiConfig(raw['gui'] as Map<String, dynamic>? ?? {});
  set gui(GuiConfig v) => raw['gui'] = v.toJson();

  OptionsConfig get options =>
      OptionsConfig(raw['options'] as Map<String, dynamic>? ?? {});

  Map<String, dynamic> get defaults =>
      (raw['defaults'] as Map? ?? {}).cast<String, dynamic>();

  DeviceConfig? device(String id) {
    for (final d in devices) {
      if (d.deviceID == id) return d;
    }
    return null;
  }

  FolderConfig? folder(String id) {
    for (final f in folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// 本机设备（config.devices 中第一个非 introduced 的，即自身）
  DeviceConfig? get ownDevice {
    for (final d in devices) {
      if (d.introducedBy.isEmpty) return d;
    }
    return devices.isEmpty ? null : devices.first;
  }

  Map<String, dynamic> toJson() => raw;
}

// ---------------------------------------------------------------------------
// 运行状态（不可变快照）
// ---------------------------------------------------------------------------

class SystemStatus {
  SystemStatus.fromJson(Map<String, dynamic> j)
      : myID = j['myID'] as String? ?? '',
        alloc = _int(j['alloc'], 0),
        sys = _int(j['sys'], 0),
        goroutines = _int(j['goroutines'], 0),
        cpuPercent = _dbl(j['cpuPercent'], 0),
        discoveryEnabled = _bool(j['discoveryEnabled'], false),
        discoveryErrors =
            (j['discoveryErrors'] as Map? ?? {}).cast<String, dynamic>(),
        discoveryStatus =
            (j['discoveryStatus'] as Map? ?? {}).cast<String, dynamic>(),
        connectionServiceStatus =
            (j['connectionServiceStatus'] as Map? ?? {}).cast<String, dynamic>(),
        lastDialStatus =
            (j['lastDialStatus'] as Map? ?? {}).cast<String, dynamic>(),
        pathSeparator = j['pathSeparator'] as String? ?? '/',
        startTime = DateTime.tryParse(j['startTime'] as String? ?? ''),
        uptimeS = _int(j['uptime'], 0),
        tilde = j['tilde'] as String? ?? '',
        version = j['version'] as String? ?? '';

  final String myID;
  final int alloc;
  final int sys;
  final int goroutines;
  final double cpuPercent;
  final bool discoveryEnabled;
  final Map<String, dynamic> discoveryErrors;
  final Map<String, dynamic> discoveryStatus;
  final Map<String, dynamic> connectionServiceStatus;
  final Map<String, dynamic> lastDialStatus;
  final String pathSeparator;
  final DateTime? startTime;
  final int uptimeS;
  final String tilde;
  final String version;

  Duration? get uptime => startTime == null
      ? (uptimeS > 0 ? Duration(seconds: uptimeS) : null)
      : DateTime.now().difference(startTime!);
}

class DeviceConnection {
  DeviceConnection.fromJson(Map<String, dynamic> j)
      : connected = _bool(j['connected'], false),
        paused = _bool(j['paused'], false),
        address = j['address'] as String? ?? '',
        type = j['type'] as String? ?? '',
        clientVersion = j['clientVersion'] as String? ?? '',
        inBytesTotal = _int(j['inBytesTotal'], 0),
        outBytesTotal = _int(j['outBytesTotal'], 0),
        at = DateTime.tryParse(j['at'] as String? ?? ''),
        startedAt = DateTime.tryParse(j['startedAt'] as String? ?? ''),
        crypto = j['crypto'] as String? ?? '',
        isLocal = _bool(j['isLocal'], false),
        typeIsActive = _bool(j['typeIsActive'], false);

  final bool connected;
  final bool paused;
  final String address;
  final String type;

  /// 连接类型: tcp-client / tcp-server / relay-client / relay-server / quic-* / ...
  final String clientVersion;
  final int inBytesTotal;
  final int outBytesTotal;
  final DateTime? at;
  final DateTime? startedAt;
  final String crypto;
  final bool isLocal;
  final bool typeIsActive;

  bool get isRelay => type.startsWith('relay');
}

class Connections {
  Connections.fromJson(Map<String, dynamic> j)
      : total = (j['total'] as Map? ?? {}).cast<String, dynamic>(),
        connections = (j['connections'] as Map? ?? {}).map(
          (k, v) => MapEntry(
            k.toString(),
            v is Map<String, dynamic>
                ? DeviceConnection.fromJson(v)
                : DeviceConnection.fromJson({}),
          ),
        );

  final Map<String, dynamic> total;
  final Map<String, DeviceConnection> connections;

  /// v2 的 total 只有累计值（inBytesTotal/outBytesTotal，1.25 起
  /// 移除了 *BytesPerSec 字段），当前速率由 controller 差分计算后写入：
  int inRate = 0;
  int outRate = 0;

  int get totalInBytes => _i(total['inBytesTotal']);
  int get totalOutBytes => _i(total['outBytesTotal']);

  int get totalInRate => inRate;
  int get totalOutRate => outRate;
}

int _i(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

/// /rest/db/status 的返回（单个文件夹的当前状态）
class FolderStatus {
  FolderStatus.fromJson(Map<String, dynamic> j)
      : state = j['state'] as String? ?? '',
        stateChanged = DateTime.tryParse(j['stateChanged'] as String? ?? ''),
        error = j['error'] as String? ?? '',
        invalid = j['invalid'] as String? ?? '',
        globalFiles = _int(j['globalFiles'], 0),
        globalDirectories = _int(j['globalDirectories'], 0),
        globalSymlinks = _int(j['globalSymlinks'], 0),
        globalDeleted = _int(j['globalDeleted'], 0),
        globalBytes = _int(j['globalBytes'], 0),
        localFiles = _int(j['localFiles'], 0),
        localDirectories = _int(j['localDirectories'], 0),
        localSymlinks = _int(j['localSymlinks'], 0),
        localDeleted = _int(j['localDeleted'], 0),
        localBytes = _int(j['localBytes'], 0),
        needFiles = _int(j['needFiles'], 0),
        needDirectories = _int(j['needDirectories'], 0),
        needSymlinks = _int(j['needSymlinks'], 0),
        needDeletes = _int(j['needDeletes'], 0),
        needBytes = _int(j['needBytes'], 0),
        inSyncBytes = _int(j['inSyncBytes'], 0),
        inSyncFiles = _int(j['inSyncFiles'], 0),
        receiveOnlyChangedFiles = _int(j['receiveOnlyChangedFiles'], 0),
        receiveOnlyChangedDirs = _int(j['receiveOnlyChangedDirs'], 0),
        receiveOnlyChangedSymlinks = _int(j['receiveOnlyChangedSymlinks'], 0),
        receiveOnlyChangedDeleted = _int(j['receiveOnlyChangedDeleted'], 0),
        receiveOnlyChangedBytes = _int(j['receiveOnlyChangedBytes'], 0),
        sequence = _int(j['sequence'], 0),
        errors = _int(j['errors'], 0),
        pullErrors = _int(j['pullErrors'], 0),
        scanPercentage = _dblOrNull(j['scanPercentage']);

  /// idle / scanning / syncing / error / ...
  final String state;
  final DateTime? stateChanged;
  final String error;
  final String invalid;
  final int globalFiles;
  final int globalDirectories;
  final int globalSymlinks;
  final int globalDeleted;
  final int globalBytes;
  final int localFiles;
  final int localDirectories;
  final int localSymlinks;
  final int localDeleted;
  final int localBytes;
  final int needFiles;
  final int needDirectories;
  final int needSymlinks;
  final int needDeletes;
  final int needBytes;
  final int inSyncBytes;
  final int inSyncFiles;

  /// receive-only 文件夹的本地改动（可 override / revert）
  final int receiveOnlyChangedFiles;
  final int receiveOnlyChangedDirs;
  final int receiveOnlyChangedSymlinks;
  final int receiveOnlyChangedDeleted;
  final int receiveOnlyChangedBytes;
  final int sequence;
  final int errors;
  final int pullErrors;
  final double? scanPercentage;

  int get receiveOnlyTotalItems =>
      receiveOnlyChangedFiles +
      receiveOnlyChangedDirs +
      receiveOnlyChangedSymlinks +
      receiveOnlyChangedDeleted;

  int get globalTotalItems =>
      globalFiles + globalDirectories + globalSymlinks + globalDeleted;

  int get needTotalItems =>
      needFiles + needDirectories + needSymlinks + needDeletes;

  double get completion {
    if (globalBytes == 0) return 100;
    if (needBytes <= 0) return 100;
    return ((globalBytes - needBytes) / globalBytes * 100).clamp(0, 100);
  }
}

class FolderErrorEntry {
  FolderErrorEntry.fromJson(Map<String, dynamic> j)
      : path = j['path'] as String? ?? '',
        error = j['error'] as String? ?? '';

  final String path;
  final String error;
}

class Completion {
  Completion.fromJson(Map<String, dynamic> j)
      : completion = _dbl(j['completion'], 100),
        globalBytes = _int(j['globalBytes'], 0),
        needBytes = _int(j['needBytes'], 0),
        needDeletes = _int(j['needDeletes'], 0),
        needItems = _int(j['needItems'], 0),
        remoteSequence = _int(j['remoteSequence'], 0);

  final double completion;
  final int globalBytes;
  final int needBytes;
  final int needDeletes;
  final int needItems;
  final int remoteSequence;
}

class DeviceStats {
  DeviceStats.fromJson(Map<String, dynamic> j)
      : lastSeen = DateTime.tryParse(j['lastSeen'] as String? ?? ''),
        lastConnectionDurationS = _int(j['lastConnectionDurationS'], 0),
        total = (j['total'] as Map? ?? {}).cast<String, dynamic>();

  final DateTime? lastSeen;
  final int lastConnectionDurationS;
  final Map<String, dynamic> total;
}

class PendingDevice {
  PendingDevice.fromJson(Map<String, dynamic> j)
      : deviceID = j['deviceID'] as String? ?? '',
        name = j['name'] as String? ?? '',
        address = j['address'] as String? ?? '',
        time = DateTime.tryParse(j['time'] as String? ?? '');

  final String deviceID;
  final String name;
  final String address;
  final DateTime? time;
}

class PendingFolder {
  PendingFolder.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String? ?? '',
        label = j['label'] as String? ?? '',
        receivingDeviceID = j['receivingDeviceID'] as String? ?? '',
        deviceID = j['deviceID'] as String? ?? '',
        receiveEncrypted = _bool(j['receiveEncrypted'], false);

  final String id;
  final String label;
  final String receivingDeviceID;
  final String deviceID;
  final bool receiveEncrypted;
}

// ---------------------------------------------------------------------------
// 事件（长轮询 /rest/events）
// ---------------------------------------------------------------------------

class SyncthingEvent {
  SyncthingEvent.fromJson(Map<String, dynamic> j)
      : id = _int(j['id'], 0),
        type = j['type'] as String? ?? '',
        time = DateTime.tryParse(j['time'] as String? ?? '') ?? DateTime.now(),
        data = (j['data'] as Map? ?? {}).cast<String, dynamic>();

  final int id;
  final String type;
  final DateTime time;
  final Map<String, dynamic> data;
}

/// /rest/system/log 返回 {messages: [{when, message}]}
class LogResponse {
  LogResponse.fromJson(Map<String, dynamic> j)
      : messages = (j['messages'] as List? ?? [])
            .map((e) => LogEntry.fromJson(e as Map<String, dynamic>))
            .toList();

  final List<LogEntry> messages;
}

class LogEntry {
  LogEntry.fromJson(Map<String, dynamic> j)
      : when = DateTime.tryParse(j['when'] as String? ?? '') ?? DateTime.now(),
        message = j['message'] as String? ?? '';

  final DateTime when;
  final String message;
}

/// /rest/system/error 返回 {errors: [{when, message}]}
class ErrorListResponse {
  ErrorListResponse.fromJson(Map<String, dynamic> j)
      : errors = (j['errors'] as List? ?? [])
            .map((e) => LogEntry.fromJson(e as Map<String, dynamic>))
            .toList();

  final List<LogEntry> errors;
}

/// /rest/db/browse 的条目（文件浏览器）。v2 返回对象数组，
/// type 为 FILE_INFO_TYPE_FILE / FILE_INFO_TYPE_DIRECTORY / ..._SYMLINK。
class BrowseEntry {
  BrowseEntry.fromJson(Map<String, dynamic> j)
      : name = j['name'] as String? ?? '',
        type = _browseType(j['type'] as String? ?? ''),
        size = _int(j['size'], 0),
        modTime = DateTime.tryParse(j['modTime'] as String? ?? '');

  final String name;

  /// file / directory / symlink / other（已归一化）
  final String type;
  final int size;
  final DateTime? modTime;

  bool get isDir => type == 'directory';

  static String _browseType(String raw) {
    if (raw.contains('DIRECTORY')) return 'directory';
    if (raw.contains('SYMLINK')) return 'symlink';
    if (raw.contains('FILE')) return 'file';
    return raw.isNotEmpty ? raw.toLowerCase() : 'other';
  }
}

/// /rest/folder/versions 的文件版本
class FileVersion {
  FileVersion.fromJson(Map<String, dynamic> j)
      : versionTime = _int(j['versionTime'], 0),
        modTime = _int(j['modTime'], 0),
        size = _int(j['size'], 0),
        deleted = _bool(j['deleted'], false),
        valid = _bool(j['valid'], false);

  final int versionTime;
  final int modTime;
  final int size;
  final bool deleted;
  final bool valid;
}

class SystemVersion {
  SystemVersion.fromJson(Map<String, dynamic> j)
      : version = j['version'] as String? ?? '',
        codename = j['codename'] as String? ?? '',
        longVersion = j['longVersion'] as String? ?? '',
        isBeta = _bool(j['isBeta'], false),
        isCandidate = _bool(j['isCandidate'], false),
        date = j['date'] as String? ?? '',
        tags = (j['tags'] as List? ?? []).map((e) => e.toString()).toList();

  final String version;
  final String codename;
  final String longVersion;
  final bool isBeta;
  final bool isCandidate;
  final String date;
  final List<String> tags;
}

class SystemPaths {
  SystemPaths.fromJson(Map<String, dynamic> j) : raw = j;

  final Map<String, dynamic> raw;

  String get base => raw['base'] as String? ?? '';
  String get config => raw['config'] as String? ?? '';
  String get data => raw['data'] as String? ?? '';
  String get database => raw['database'] as String? ?? '';
}

// ---------------------------------------------------------------------------
// 解析助手
// ---------------------------------------------------------------------------

int _int(dynamic v, int def) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v) ?? def;
  return def;
}

bool _bool(dynamic v, bool def) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == 'true';
  return def;
}

double _dbl(dynamic v, double def) => v is num ? v.toDouble() : def;

double? _dblOrNull(dynamic v) => v is num ? v.toDouble() : null;

/// 便捷：把 JSON 字符串解析成 Map（失败返回 null）。
Map<String, dynamic>? tryParseJsonMap(String s) {
  try {
    final v = jsonDecode(s);
    return v is Map<String, dynamic> ? v : null;
  } catch (_) {
    return null;
  }
}
