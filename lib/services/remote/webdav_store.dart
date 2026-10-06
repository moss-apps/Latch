import 'package:dio/dio.dart' show DioException;
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
    // generous timeouts; .local NAS hosts + cold servers need room.
    c.setConnectTimeout(15000);
    // dio's send timeout is wall clock for the whole body; first-sync blobs
    // are whole media files that can take minutes each over Wi-Fi.
    c.setSendTimeout(600000);
    c.setReceiveTimeout(600000);
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
  Future<void> putManifest(Uint8List bytes) async {
    await _ensureParent(_path(RemoteStore.manifestName));
    await _c.write(_path(RemoteStore.manifestName), bytes);
  }

  @override
  Future<Uint8List?> getBlob(String name) => _readOrNull(name);

  @override
  Future<void> putBlob(String name, Uint8List bytes) async {
    final path = _path(name);
    await _ensureParent(path);
    // write() maps the bytes to a stream of one-byte events; hand over plain
    // chunks instead or big uploads crawl through the event loop.
    await _c.c.wdWriteWithStream(_c, path, _chunks(bytes), bytes.length);
  }

  /// Zero-copy 512 KiB views; mirrors writeFromFile's chunked streaming.
  static Stream<List<int>> _chunks(Uint8List bytes) async* {
    const size = 512 * 1024;
    for (var i = 0; i < bytes.length; i += size) {
      final end = i + size < bytes.length ? i + size : bytes.length;
      yield Uint8List.sublistView(bytes, i, end);
    }
  }

  // Spec-strict servers (rclone, mod_dav) 409 a nested PUT whose parent
  // collection doesn't exist; Nextcloud auto-creates and masks it. Idempotent.
  Future<void> _ensureParent(String fullPath) async {
    final slash = fullPath.lastIndexOf('/');
    if (slash <= 0) return;
    await _c.mkdirAll(fullPath.substring(0, slash));
  }

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

  /// True only when the server explicitly confirmed the resource is missing.
  @visibleForTesting
  static bool isNotFound(Object error) =>
      error is DioException && error.response?.statusCode == 404;

  /// Reads [read], returning null only on a confirmed 404.
  ///
  /// Transport, authentication, and server failures are rethrown so callers
  /// cannot mistake them for an absent manifest or blob.
  @visibleForTesting
  static Future<Uint8List?> readOrNull(
    Future<List<int>> Function() read,
  ) async {
    try {
      return Uint8List.fromList(await read());
    } on DioException catch (e) {
      if (isNotFound(e)) return null;
      rethrow;
    }
  }

  /// Throws on anything other than a confirmed 404; see [readOrNull].
  Future<Uint8List?> _readOrNull(String name) {
    return readOrNull(() => _c.read(_path(name)));
  }
}
