import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 壳自身的偏好（与 syncthing 配置无关）：主题模式、开机自启等。
class AppPrefs extends ChangeNotifier {
  AppPrefs(this._prefs);

  final SharedPreferences _prefs;

  static Future<AppPrefs> load() async => AppPrefs(await SharedPreferences.getInstance());

  /// system / light / dark
  String get themeMode => _prefs.getString('themeMode') ?? 'system';

  set themeMode(String v) {
    _prefs.setString('themeMode', v);
    notifyListeners();
  }

  bool get startOnBoot => _prefs.getBool('startOnBoot') ?? true;

  set startOnBoot(bool v) {
    _prefs.setBool('startOnBoot', v);
    notifyListeners();
  }

  /// 打开 App 时是否自动启动 Syncthing 服务。
  bool get autoStartOnOpen => _prefs.getBool('autoStartOnOpen') ?? true;

  set autoStartOnOpen(bool v) {
    _prefs.setBool('autoStartOnOpen', v);
    notifyListeners();
  }

  /// 首次启动引导已完成。
  bool get onboardingDone => _prefs.getBool('onboardingDone') ?? false;

  set onboardingDone(bool v) {
    _prefs.setBool('onboardingDone', v);
    notifyListeners();
  }

  /// 上一次展示给用户的 syncthing 版本（用于检测二进制更新后的提示）。
  String get lastSyncthingVersion => _prefs.getString('lastSyncthingVersion') ?? '';

  set lastSyncthingVersion(String v) {
    _prefs.setString('lastSyncthingVersion', v);
    notifyListeners();
  }

  static String prettyJson(Map<String, dynamic> json) =>
      const JsonEncoder.withIndent('  ').convert(json);
}
