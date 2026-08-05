import 'package:flutter/foundation.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

import 'remote_store.dart';

/// WebDAV implementation of [RemoteStore] — dumb blob storage. The server only
/// ever sees opaque bytes: content-addressed blobs + the encrypted manifest.
class WebDAVStore implements RemoteStore {
  WebDAVStore({
    required this.baseUrl,
    this.username = '',
    this.password = '',
    this.basePath = '/locker',
  });

  /// Server root, e.g. `https://nas.local/dav`.
  final String baseUrl;

  final String username;
  final String password;

  /// Vault root path on the server, e.g. `/locker`.
  final String basePath;

  webdav.Client? _client;

  webdav.Client get _c {
    if (_client != null) return _client!;
    final c = webdav.newClient(baseUrl, user: username, password: password);
    // ponytail: generous timeouts; .local NAS hosts + cold servers need room.
    c.setConnectTimeout(15000);
    c.setSendTimeout(30000);
    c.setReceiveTimeout(30000);
    _client = c;
    return c;
  }

  /// Join [base] and [name] with exactly one `/`.
  static String joinPath(String base, String name) {
    final b = base.replaceAll(RegExp(r'/$'), '');
    final n = name.replaceAll(RegExp(r'^/'), '');
    return '$b/$n';
  }

  String _path(String name) => joinPath(basePath, name);

  @override
  Future<void> testConnection() => _c.ping();

  @override
  Future<Uint8List?> getManifest() => _readOrNull(RemoteStore.manifestName);

  @override
  Future<void> putManifest(Uint8List bytes) =>
      _c.write(_path(RemoteStore.manifestName), bytes);

  @override
  Future<Uint8List?> getBlob(String name) => _readOrNull(name);

  @override
  Future<void> putBlob(String name, Uint8List bytes) =>
      _c.write(_path(name), bytes);

  @override
  Future<void> deleteBlob(String name) => _c.remove(_path(name));

  @override
  Future<List<String>> listBlobs() async {
    final out = <String>[];
    await _walk(basePath.isEmpty ? '/' : basePath, out);
    return out;
  }

  Future<void> _walk(String dir, List<String> out) async {
    final files = await _c.readDir(dir);
    for (final f in files) {
      if (f.isDir == true) {
        await _walk(f.path ?? '', out);
      } else {
        out.add(f.path ?? '');
      }
    }
  }

  /// Absent file (404) and reachability errors both come back null.
  /// ponytail: conflates the two; v1 treats them the same, and the caller's
  /// testConnection gate separates "server down" from "nothing synced yet".
  Future<Uint8List?> _readOrNull(String name) async {
    try {
      return Uint8List.fromList(await _c.read(_path(name)));
    } catch (e) {
      debugPrint('WebDAV read($name): $e');
      return null;
    }
  }
}
