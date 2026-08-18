import 'dart:convert';

import 'package:http/http.dart' as http;

/// Authenticated HTTP client for the embedded PocketBase sidecar.
///
/// Every request carries the X-Locker-Token handshake token; without it the
/// sidecar answers 401 (see pocketbase/cmd/locker-pb/main.go).
class PbClient {
  PbClient({required int port, required String token})
      : baseUrl = 'http://127.0.0.1:$port',
        _token = token;

  static const tokenHeader = 'X-Locker-Token';

  final String baseUrl;
  final String _token;
  final _http = http.Client();

  Uri _uri(String path, {Map<String, String>? query}) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Map<String, String> get _headers => {tokenHeader: _token};

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) async {
    final res = await _http.get(_uri(path, query: query), headers: _headers);
    return _decode(res);
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final res = await _http.post(
      _uri(path, query: query),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode(body ?? {}),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final res = await _http.patch(
      _uri(path, query: query),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode(body ?? {}),
    );
    return _decode(res);
  }

  Future<void> delete(String path, {Map<String, String>? query}) async {
    final res = await _http.delete(_uri(path, query: query), headers: _headers);
    if (res.statusCode >= 400) {
      throw http.ClientException(
        'DELETE $path → ${res.statusCode}: ${res.body}',
        _uri(path),
      );
    }
  }

  /// True once the sidecar answers /api/health with 200 (i.e. token accepted).
  Future<bool> health() async {
    final res = await _http.get(
      _uri('/api/health'),
      headers: _headers,
    ).timeout(const Duration(seconds: 2));
    return res.statusCode == 200;
  }

  Map<String, dynamic> _decode(http.Response res) {
    if (res.statusCode >= 400) {
      throw http.ClientException(
        '${res.request?.method} ${res.request?.url.path} → '
        '${res.statusCode}: ${res.body}',
        res.request?.url,
      );
    }
    final body = res.body;
    return body.isEmpty ? <String, dynamic>{} : jsonDecode(body) as Map<String, dynamic>;
  }

  void close() => _http.close();
}
