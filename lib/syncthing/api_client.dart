import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Syncthing REST API 客户端。
///
/// 这是「壳」与 syncthing 之间唯一的通信层（除配置引导外）。
/// 升级 syncthing 后如有 API 变化，只需要调整本文件与 models/ 下的模型，
/// UI 层不直接感知 REST 细节。
class ApiClient {
  ApiClient({required this.baseUrl, required this.apiKey});

  final String baseUrl;
  final String apiKey;

  final http.Client _http = http.Client();

  Map<String, String> _h({bool json = false}) => {
        'X-API-Key': apiKey,
        if (json) 'Content-Type': 'application/json',
      };

  Future<dynamic> get(String path,
      {Map<String, dynamic>? query, Duration? timeout}) async {
    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: query?.map((k, v) => MapEntry(k, v.toString())),
    );
    final res = await _http
        .get(uri, headers: _h())
        .timeout(timeout ?? const Duration(seconds: 15));
    return _decode(res, 'GET $path');
  }

  /// 长轮询专用：返回原始字符串（事件流为 JSON 数组）。
  Future<String> getRaw(String path, {Map<String, dynamic>? query, Duration? timeout}) async {
    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: query?.map((k, v) => MapEntry(k, v.toString())),
    );
    final res = await _http
        .get(uri, headers: _h())
        .timeout(timeout ?? const Duration(seconds: 90));
    if (res.statusCode != 200) {
      throw ApiException(res.statusCode, res.body, 'GET $path');
    }
    return res.body;
  }

  Future<dynamic> post(String path, {Object? body, Map<String, dynamic>? query}) async =>
      _send('POST', path, body, query);

  Future<dynamic> put(String path, {Object? body, Map<String, dynamic>? query}) async =>
      _send('PUT', path, body, query);

  Future<dynamic> patch(String path, {Object? body, Map<String, dynamic>? query}) async =>
      _send('PATCH', path, body, query);

  Future<dynamic> delete(String path, {Map<String, dynamic>? query}) async =>
      _send('DELETE', path, null, query);

  Future<dynamic> _send(String method, String path, Object? body,
      Map<String, dynamic>? query) async {
    var uri = Uri.parse('$baseUrl$path');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(
        queryParameters: query.map((k, v) => MapEntry(k, v.toString())),
      );
    }
    final request = http.Request(method, uri)
      ..headers.addAll(_h(json: body != null));
    if (body != null) request.body = jsonEncode(body);
    final res = await http.Response.fromStream(
        await _http.send(request).timeout(const Duration(seconds: 20)));
    return _decode(res, '$method $path');
  }

  dynamic _decode(http.BaseResponse res, String what) {
    final body = res is http.Response ? res.body : '';
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, body, what);
    }
    if (body.isEmpty) return null;
    return jsonDecode(body);
  }

  Future<bool> ping() async {
    try {
      final r = await get('/rest/system/ping', timeout: const Duration(seconds: 3));
      return r is Map && r['ping'] == 'pong';
    } catch (_) {
      return false;
    }
  }

  void close() => _http.close();
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.body, [this.context]);

  final int statusCode;
  final String body;
  final String? context;

  @override
  String toString() {
    final buf = StringBuffer('HTTP $statusCode');
    if (context != null) buf.write(' ($context)');
    if (body.isNotEmpty && body.length < 300) buf.write(': $body');
    return buf.toString();
  }
}
