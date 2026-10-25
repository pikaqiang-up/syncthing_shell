import 'dart:async';
import 'package:flutter/services.dart';

/// 原生（Kotlin）桥接层：服务生命周期、权限、目录选择。
class NativeBridge {
  static const _method = MethodChannel('app.syncthing/native');
  static const _events = EventChannel('app.syncthing/events');

  static final NativeBridge instance = NativeBridge._();

  NativeBridge._();

  final _stateCtrl = StreamController<ServiceState>.broadcast();
  final _logCtrl = StreamController<String>.broadcast();

  /// 服务状态流（含订阅时立即回放的当前状态）。
  Stream<ServiceState> get states => _stateCtrl.stream;

  /// syncthing 进程 stdout 日志行。
  Stream<String> get logs => _logCtrl.stream;

  ServiceInfo? _info;

  void init() {
    _events.receiveBroadcastStream().listen((msg) {
      final map = msg as Map;
      switch (map['type']) {
        case 'state':
          _stateCtrl.add(ServiceState(
            map['state'] as String? ?? 'stopped',
            message: map['message'] as String?,
          ));
        case 'log':
          _logCtrl.add(map['line'] as String? ?? '');
      }
    });
  }

  /// 获取（并在首次运行时引导生成）服务信息。可能耗时数秒。
  Future<ServiceInfo> getServiceInfo() async {
    final raw = await _method.invokeMapMethod<String, dynamic>('getServiceInfo');
    _info = ServiceInfo.fromMap(raw!);
    return _info!;
  }

  ServiceInfo? get cachedInfo => _info;

  Future<void> start() => _method.invokeMethod('start');

  Future<void> stop() => _method.invokeMethod('stop');

  Future<String> state() async => await _method.invokeMethod('state') as String;

  /// SAF 目录选择；返回真实路径（仅主存储），取消/失败返回 null。
  Future<String?> pickDirectory() async =>
      await _method.invokeMethod<String>('pickDirectory');

  Future<bool> requestNotificationPermission() async =>
      await _method.invokeMethod('requestNotificationPermission') as bool;

  Future<bool> isAllFilesAccessGranted() async =>
      await _method.invokeMethod('isAllFilesAccessGranted') as bool;

  /// 跳到系统设置授予“所有文件访问”权限；返回授予结果。
  Future<bool> requestAllFilesAccess() async =>
      await _method.invokeMethod('requestAllFilesAccess') as bool;

  Future<bool> isIgnoringBatteryOptimizations() async =>
      await _method.invokeMethod('isIgnoringBatteryOptimizations') as bool;

  Future<void> requestIgnoreBatteryOptimizations() =>
      _method.invokeMethod('requestIgnoreBatteryOptimizations');

  Future<bool> openWebUi(String url) async =>
      await _method.invokeMethod('openWebUi', {'url': url}) as bool;
}

enum ServiceRunState { stopped, starting, running, error }

class ServiceState {
  ServiceState(this.state, {this.message});

  final String state;

  final String? message;

  ServiceRunState get runState => switch (state) {
        'starting' => ServiceRunState.starting,
        'running' => ServiceRunState.running,
        'error' => ServiceRunState.error,
        _ => ServiceRunState.stopped,
      };
}

class ServiceInfo {
  ServiceInfo({
    required this.binaryPath,
    required this.homeDir,
    required this.apiPort,
    required this.apiKey,
    required this.guiAddress,
  });

  final String binaryPath;
  final String homeDir;
  final int apiPort;
  final String apiKey;
  final String guiAddress;

  String get baseUrl => 'http://127.0.0.1:$apiPort';

  String get webUiUrl => 'http://127.0.0.1:$apiPort';

  factory ServiceInfo.fromMap(Map<String, dynamic> map) => ServiceInfo(
        binaryPath: map['binaryPath'] as String,
        homeDir: map['homeDir'] as String,
        apiPort: map['apiPort'] as int,
        apiKey: map['apiKey'] as String,
        guiAddress: map['guiAddress'] as String,
      );
}
