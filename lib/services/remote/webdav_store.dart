import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

import 'remote_store.dart';
import '../sync_control.dart';
import '../diagnostics.dart';

/// How the probe proved a guarded manifest replacement is possible.
enum _Publication {
  /// The server honors tagged `If: <uri> ([etag])` preconditions on MOVE.
  etag,

  /// The server enforces exclusive WebDAV locks; publication serializes on one.
  lock,
}

/// WebDAV implementation of [RemoteStore] — dumb blob storage. The server only
/// ever sees opaque bytes: content-addressed blobs + the encrypted manifest.
class WebDAVStore implements RemoteStore, StreamingRemoteStore {
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
  _Publication? _publication;

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

  Uri _uri(String path) => Uri.parse(joinPath(baseUrl, path));

  void _expect(Response<dynamic> response, List<int> statuses) {
    if (statuses.contains(response.statusCode)) return;
    if (response.statusCode == 412 || response.statusCode == 423) {
      throw RemoteRevisionChanged();
    }
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      type: DioExceptionType.badResponse,
    );
  }

  @override
  Future<RemoteManifestSnapshot> readManifest(SyncControl control) async {
    await _checkPublication(control);
    final response = await _c.c.req<List<int>>(_c, 'GET', _path(RemoteStore.manifestName),
        cancelToken: control.network,
        optionsHandler: (o) => o.responseType = ResponseType.bytes);
    if (response.statusCode == 404) return const RemoteManifestSnapshot(null, null);
    _expect(response, [200]);
    final revision = response.headers.value('etag');
    if (revision == null || revision.startsWith('W/')) {
      throw UnsafeRemotePublication('missing-strong-etag');
    }
    return RemoteManifestSnapshot(Uint8List.fromList(response.data!), revision);
  }

  @override
  Future<void> publishManifest(Uint8List bytes, String? revision, SyncControl control) async {
    await _checkPublication(control);
    final canonical = _path(RemoteStore.manifestName);
    await _ensureParent(canonical, cancelToken: control.network);
    final capabilities = await _c.c.wdOptions(_c, canonical, cancelToken: control.network);
    _expect(capabilities, [200, 204]);
    if (capabilities.headers.value('dav') == null) throw UnsafeRemotePublication();
    final temporary = '$canonical.${const Uuid().v4()}.partial';
    try {
      final response = await _c.c.req(_c, 'PUT', temporary, data: bytes,
        cancelToken: control.network,
        optionsHandler: (o) => o.headers!['content-length'] = bytes.length);
    _expect(response, [200, 201, 204]);
      if (_publication == _Publication.lock) {
        await _publishUnderLock(temporary, canonical, revision, control);
      } else {
        await _move(temporary, canonical, control, revision: revision, overwrite: revision != null);
      }
    } finally {
      await _removeStaging(temporary);
    }
  }

  Future<void> _removeStaging(String path) async {
    final token = CancelToken();
    try {
      final response = await _c.c.req(_c, 'DELETE', path, cancelToken: token)
          .timeout(const Duration(seconds: 2));
      _expect(response, [200, 204, 404]);
    } catch (e, st) {
      Diagnostics.failure('sync.remoteCleanup', e, st);
    } finally {
      token.cancel();
    }
  }

  Future<void> _checkPublication(SyncControl control) async {
    if (_publication != null) return;
    final prefix = _path('.latch-probe-${const Uuid().v4()}');
    final source = '$prefix-source';
    final destination = '$prefix-destination';
    await _ensureParent(source, cancelToken: control.network);
    final capabilities = await _c.c.wdOptions(_c, basePath, cancelToken: control.network);
    _expect(capabilities, [200, 204]);
    if (capabilities.headers.value('dav') == null) throw UnsafeRemotePublication();
    try {
      await _putProbe(source, control);
      await _putProbe(destination, control);
      final etag = await _strongEtag(destination, control);
      // Both publication paths rely on an atomic first creation.
      var guardedCreate = false;
      try {
        await _move(source, destination, control);
      } on RemoteRevisionChanged {
        guardedCreate = true;
      }
      if (!guardedCreate) throw UnsafeRemotePublication('ignored-publication-precondition');
      // Prefer server-side ETag preconditions when the server really honors
      // them. x/net/webdav (rclone, many Go DAV servers) treats bracketed
      // entity-tags as lock tokens and 412s every guarded MOVE, so the lock
      // path must be probed with an actual exclusion test.
      if (await _etagGuardsWork(source, destination, etag, control)) {
        _publication = _Publication.etag;
      } else if (await _locksWork(source, destination, control)) {
        _publication = _Publication.lock;
      } else {
        throw UnsafeRemotePublication('unsupported-publication-guard');
      }
    } finally {
      await _removeStaging(source);
      await _removeStaging(destination);
    }
  }

  /// True when the probe proved publication serializes on exclusive locks.
  @visibleForTesting
  bool get usesLockPublication => _publication == _Publication.lock;

  Future<void> _putProbe(String path, SyncControl control) async {
    final response = await _c.c.req(_c, 'PUT', path, data: Uint8List.fromList([1, 2, 3]),
        cancelToken: control.network,
        optionsHandler: (o) => o.headers!['content-length'] = 3);
    _expect(response, [200, 201, 204]);
  }

  Future<String> _strongEtag(String path, SyncControl control) async {
    final response = await _c.c.req<List<int>>(_c, 'GET', path,
        cancelToken: control.network,
        optionsHandler: (o) => o.responseType = ResponseType.bytes);
    _expect(response, [200]);
    final etag = response.headers.value('etag');
    if (etag == null || etag.startsWith('W/')) throw UnsafeRemotePublication('missing-strong-etag');
    return etag;
  }

  /// Matching ETags must be accepted; mismatched ones must fail 412/423.
  Future<bool> _etagGuardsWork(
      String source, String destination, String etag, SyncControl control) async {
    try {
      await _move(source, destination, control, revision: etag, overwrite: true);
    } on RemoteRevisionChanged {
      return false;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.badResponse) return false;
      rethrow;
    }
    await _putProbe(source, control);
    try {
      await _move(source, destination, control,
          revision: '"latch-mismatch-${const Uuid().v4()}"', overwrite: true);
    } on RemoteRevisionChanged {
      return true;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.badResponse) return false;
      rethrow;
    }
    return false;
  }

  /// A lock only counts if it excludes a token-less MOVE and authorizes a
  /// token-tagged one. Both directions are verified against the same resource.
  Future<bool> _locksWork(String source, String destination, SyncControl control) async {
    await _putProbe(source, control);
    await _putProbe(destination, control);
    _LockHandle? handle;
    try {
      try {
        handle = await _lock(destination, control);
      } on RemoteRevisionChanged {
        return false;
      }
      var excluded = false;
      try {
        await _move(source, destination, control, overwrite: true);
      } on RemoteRevisionChanged {
        excluded = true;
      } on DioException catch (e) {
        if (e.type == DioExceptionType.badResponse) return false;
        rethrow;
      }
      if (!excluded) return false;
      await _putProbe(source, control);
      try {
        await _move(source, destination, control, overwrite: true, lockToken: handle.token);
      } on RemoteRevisionChanged {
        return false;
      } on DioException catch (e) {
        if (e.type == DioExceptionType.badResponse) return false;
        rethrow;
      }
      return true;
    } finally {
      if (handle != null) await _unlock(destination, handle, control);
    }
  }

  Future<void> _publishUnderLock(
      String source, String destination, String? revision, SyncControl control) async {
    if (revision == null) {
      // First publication is an atomic create; the server rejects an existing
      // destination (verified by the probe).
      await _move(source, destination, control);
      return;
    }
    final handle = await _lock(destination, control);
    var published = false;
    try {
      // Another publisher may have landed between readManifest and the lock.
      final current = await _etagOrNull(destination, control);
      if (current != revision) throw RemoteRevisionChanged();
      await _move(source, destination, control, lockToken: handle.token, overwrite: true);
      published = true;
    } finally {
      if (!published && handle.created) {
        // LOCK materialized an empty manifest for a resource that vanished;
        // remove the stub or every later read sees an unreadable 200 body.
        try {
          final response = await _c.c.req(_c, 'DELETE', destination,
              cancelToken: control.network,
              optionsHandler: (o) => o.headers!['if'] = '<${_uri(destination)}> (${handle.token})');
          _expect(response, [200, 204, 404]);
        } catch (e, st) {
          Diagnostics.failure('sync.remoteLockCleanup', e, st);
        }
      }
      await _unlock(destination, handle, control);
    }
  }

  Future<String?> _etagOrNull(String path, SyncControl control) async {
    final response = await _c.c.req<List<int>>(_c, 'GET', path,
        cancelToken: control.network,
        optionsHandler: (o) => o.responseType = ResponseType.bytes);
    if (response.statusCode == 404) return null;
    _expect(response, [200]);
    final etag = response.headers.value('etag');
    if (etag == null || etag.startsWith('W/')) throw UnsafeRemotePublication('missing-strong-etag');
    return etag;
  }

  /// Acquires an exclusive write lock. 423 means another publisher holds it.
  Future<_LockHandle> _lock(String path, SyncControl control) async {
    final response = await _c.c.req(_c, 'LOCK', path,
        data: _exclusiveLockBody,
        cancelToken: control.network,
        optionsHandler: (o) {
          o.headers!['content-type'] = 'application/xml; charset=utf-8';
          o.headers!['timeout'] = 'Second-60';
          o.headers!['depth'] = '0';
        });
    if (response.statusCode == 423) throw RemoteRevisionChanged();
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw UnsafeRemotePublication('missing-lock-capability');
    }
    final token = response.headers.value('lock-token');
    if (token == null || token.isEmpty) throw UnsafeRemotePublication('missing-lock-token');
    return _LockHandle(token, created: response.statusCode == 201);
  }

  /// Best effort: a dangling lock expires on its own via the Timeout header.
  Future<void> _unlock(String path, _LockHandle handle, SyncControl control) async {
    try {
      final response = await _c.c.req(_c, 'UNLOCK', path,
          cancelToken: control.network,
          optionsHandler: (o) => o.headers!['lock-token'] = handle.token);
      if (![200, 204, 404, 409].contains(response.statusCode)) {
        Diagnostics.failure('sync.remoteUnlock', 'unexpected status ${response.statusCode}',
            StackTrace.current);
      }
    } catch (e, st) {
      Diagnostics.failure('sync.remoteUnlock', e, st);
    }
  }

  Future<void> _move(String source, String destination, SyncControl control,
      {String? revision, bool overwrite = false, String? lockToken}) async {
    final response = await _c.c.req(_c, 'MOVE', source, cancelToken: control.network,
        optionsHandler: (o) {
      o.headers!['destination'] = _uri(destination).toString();
      o.headers!['overwrite'] = overwrite ? 'T' : 'F';
      if (lockToken != null) {
        o.headers!['if'] = '<${_uri(destination)}> ($lockToken)';
      } else if (revision != null) {
        o.headers!['if'] = '<${_uri(destination)}> ([$revision])';
      }
    });
    _expect(response, [201, 204]);
  }

  Stream<List<int>> _cancellable(Stream<List<int>> source, SyncControl control) {
    late StreamSubscription<List<int>> subscription;
    late StreamController<List<int>> output;
    var closed = false;
    output = StreamController<List<int>>(
      onListen: () {
        subscription = source.listen(output.add, onError: output.addError, onDone: () {
          closed = true;
          output.close();
        });
        control.network.whenCancel.then((_) async {
          if (closed) return;
          closed = true;
          output.addError(SyncCancelled());
          await subscription.cancel();
          await output.close();
        });
      },
      onPause: () => subscription.pause(),
      onResume: () => subscription.resume(),
      onCancel: () { closed = true; return subscription.cancel(); },
    );
    return output.stream;
  }

  Future<Response<ResponseBody>> _readStream(String name, SyncControl control) =>
      _c.c.req<ResponseBody>(_c, 'GET', _path(name), cancelToken: control.network,
          optionsHandler: (o) {
        o.responseType = ResponseType.stream;
        o.headers!['accept-encoding'] = 'identity';
      });

  @override
  Future<int?> blobLength(String name, SyncControl control) async {
    final response = await _c.c.req(_c, 'HEAD', _path(name), cancelToken: control.network);
    if ([404, 405, 501].contains(response.statusCode)) return null;
    _expect(response, [200]);
    return int.tryParse(response.headers.value('content-length') ?? '');
  }

  @override
  Future<bool> verifyBlob(String name, String hash, SyncControl control) async {
    final response = await _readStream(name, control);
    if (response.statusCode == 404) {
      await response.data!.stream.drain<void>();
      return false;
    }
    _expect(response, [200]);
    return (await sha256.bind(_cancellable(response.data!.stream, control)).first).toString() == hash;
  }

  @override
  Future<void> uploadFile(String name, File file, String hash, SyncControl control,
      void Function(int, int) progress) async {
    final canonical = _path(name);
    await _ensureParent(canonical, cancelToken: control.network);
    // Authenticate before opening a single-use body stream.
    final probe = await _c.c.wdOptions(_c, canonical, cancelToken: control.network);
    _expect(probe, [200, 204]);
    final temporaryName = '$name.${const Uuid().v4()}.partial';
    final temporary = _path(temporaryName);
    final length = await file.length();
    final headers = <String, dynamic>{'content-length': length};
    final authorization = _c.auth.authorize('PUT', temporary);
    if (authorization != null) headers['authorization'] = authorization;
    try {
      final response = await _c.c.requestUri(_uri(temporary),
        data: file.openRead(), cancelToken: control.network,
        options: Options(method: 'PUT', headers: headers), onSendProgress: progress);
    _expect(response, [200, 201, 204]);
    if (!await verifyBlob(temporaryName, hash, control)) {
      throw const FormatException('Uploaded blob hash mismatch');
    }
    // Only a complete, verified body may replace a legacy partial canonical blob.
      await _move(temporary, canonical, control, overwrite: true);
    } finally {
      await _removeStaging(temporary);
    }
  }

  @override
  Future<bool> downloadFile(String name, File destination, SyncControl control,
      void Function(int, int) progress) async {
    final response = await _readStream(name, control);
    if (response.statusCode == 404) {
      await response.data!.stream.drain<void>();
      return false;
    }
    _expect(response, [200]);
    final total = int.tryParse(response.headers.value('content-length') ?? '') ?? -1;
    final sink = await destination.open(mode: FileMode.write);
    var received = 0;
    try {
      await for (final chunk in _cancellable(response.data!.stream, control)) {
        control.check();
        await sink.writeFrom(chunk);
        received += chunk.length;
        progress(received, total);
      }
      await sink.flush();
      return true;
    } finally {
      await sink.close();
    }
  }

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
  Future<void> _ensureParent(String fullPath, {CancelToken? cancelToken}) async {
    final slash = fullPath.lastIndexOf('/');
    if (slash <= 0) return;
    await _c.mkdirAll(fullPath.substring(0, slash), cancelToken);
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

class _LockHandle {
  _LockHandle(this.token, {required this.created});
  final String token;
  final bool created;
}

const _exclusiveLockBody = '<?xml version="1.0" encoding="utf-8"?>'
    '<D:lockinfo xmlns:D="DAV:">'
    '<D:lockscope><D:exclusive/></D:lockscope>'
    '<D:locktype><D:write/></D:locktype>'
    '<D:owner><D:href>latch</D:href></D:owner>'
    '</D:lockinfo>';
