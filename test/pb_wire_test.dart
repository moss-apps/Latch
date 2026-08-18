import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/vaulted_file.dart';
import 'package:locker/services/pb/pb_client.dart';
import 'package:locker/services/pb/pocketbase_store.dart';
import 'package:locker/services/remote/remote_store.dart';
import 'package:locker/services/sync_service.dart';
import 'package:locker/services/vault_store.dart';

/// P4.4 scripted end-to-end: seed vault → PB rows appear (ciphertext at
/// rest) → runSync pushes blobs + encrypted manifest over the unchanged
/// WebDAV-style path. Plus the PB-dead fallback path.

class _FakePb {
  final token = 'f' * 64;
  final db = <String, Map<String, Map<String, dynamic>>>{};
  HttpServer? _server;

  Future<int> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle);
    return _server!.port;
  }

  Future<void> stop() => _server!.close(force: true);

  void _handle(HttpRequest req) async {
    final res = req.response;
    try {
      if (req.headers.value(PbClient.tokenHeader) != token) {
        _json(res, 401, {'error': 'unauthorized'});
        return;
      }
      final seg = req.uri.pathSegments;
      final rows = db.putIfAbsent(seg[2], () => {});
      final id = seg.length > 4 ? seg[4] : null;

      switch (req.method) {
        case 'POST':
          final body = await _body(req);
          if (rows.containsKey(body['id'])) {
            _json(res, 400, {'error': 'duplicate id'});
          } else {
            rows[body['id'] as String] = body;
            _json(res, 200, body);
          }
        case 'PATCH':
          final body = await _body(req);
          final row = rows[id!];
          if (row == null) {
            _json(res, 404, {'error': 'missing'});
          } else {
            row.addAll(body..remove('id'));
            _json(res, 200, row);
          }
        case 'DELETE':
          rows.remove(id!) == null
              ? _json(res, 404, {'error': 'missing'})
              : _json(res, 204, {});
        case 'GET':
          if (id != null) {
            final row = rows[id];
            row == null
                ? _json(res, 404, {'error': 'missing'})
                : _json(res, 200, row);
          } else {
            final q = req.uri.queryParameters;
            final page = int.parse(q['page'] ?? '1');
            final perPage = int.parse(q['perPage'] ?? '30');
            final all = rows.values.toList();
            _json(res, 200, {
              'items': all.skip((page - 1) * perPage).take(perPage).toList(),
              'totalItems': all.length,
              'totalPages': (all.length / perPage).ceil(),
            });
          }
        default:
          _json(res, 405, {});
      }
    } catch (e) {
      _json(res, 500, {'error': '$e'});
    }
  }

  static Future<Map<String, dynamic>> _body(HttpRequest req) async =>
      jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;

  static void _json(HttpResponse res, int status, Object? body) {
    res.statusCode = status;
    res.write(jsonEncode(body));
    res.close();
  }
}

class _MemRemote implements RemoteStore {
  final blobs = <String, Uint8List>{};
  Uint8List? manifest;

  @override
  Future<void> testConnection() async {}

  @override
  Future<Uint8List?> getManifest() async => manifest;

  @override
  Future<void> putManifest(Uint8List bytes) async => manifest = bytes;

  @override
  Future<void> putBlob(String name, Uint8List bytes) async =>
      blobs[name] = bytes;

  @override
  Future<Uint8List?> getBlob(String name) async => blobs[name];

  @override
  Future<void> deleteBlob(String name) async => blobs.remove(name);

  @override
  Future<List<String>> listBlobs() async => blobs.keys.toList();
}

void main() {
  final key = Uint8List.fromList(List.filled(32, 7));

  test('P4.4 e2e: seed vault → PB rows appear → runSync pushes blobs + '
      'encrypted manifest', () async {
    final pb = _FakePb();
    final port = await pb.start();
    addTearDown(pb.stop);

    final store = VaultStore();
    store.pbStore = PocketBaseStore(
      client: PbClient(port: port, token: pb.token),
      masterKey: key,
    );

    // Seed the vault the way FileService would: mutate the cache, then save.
    final tmp = Directory.systemTemp.createTempSync('locker_p4');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final blob = Uint8List.fromList(List.generate(64, (i) => i));
    final path = '${tmp.path}/deadbeef.enc';
    await File(path).writeAsBytes(blob);
    final file = VaultedFile(
      id: '11111111-2222-3333-4444-555555555555',
      originalName: 'passport.jpg',
      vaultPath: path,
      type: VaultedFileType.image,
      mimeType: 'image/jpeg',
      fileSize: blob.length,
      dateAdded: DateTime.utc(2026, 1, 2, 3, 4, 5),
      tags: const ['secret-tag'],
      isEncrypted: true,
      modifiedAt: DateTime.utc(2026, 2, 3, 4, 5, 6),
    );
    store.cachedFiles = [file];
    await store.saveFileIndex();

    // PB rows appeared, ciphertext at rest.
    final row = pb.db['vault_files']!.values.single;
    expect(row['blob_ref'], path);
    expect(jsonEncode(row['cipher_meta']).contains('passport'), isFalse);

    // Sync reads the local index from the active store (P4.3), pushes blob +
    // encrypted manifest over the unchanged remote path.
    final remote = _MemRemote();
    final result = await SyncService.runSync(
      local: await store.loadFileIndex(forceReload: true),
      masterKey: key,
      remote: remote,
      deviceId: 'device-1',
    );
    expect(result.blobsPushed, 1);
    expect(remote.blobs.length, 1);
    final manifest =
        SyncService.decryptManifest(remote.manifest!, key);
    expect(manifest.entries.single.id, file.id);
    expect(manifest.entries.single.originalName, 'passport.jpg');

    // A fresh read (cache-free) round-trips through PB.
    store.cachedFiles = null;
    expect(
      jsonEncode((await store.loadFileIndex(forceReload: true)).single.toJson()),
      jsonEncode(file.toJson()),
    );
  });

  test('PB-dead fallback: load falls back to the legacy path, never throws',
      () async {
    final pb = _FakePb();
    final port = await pb.start();
    await pb.stop(); // dead port

    final store = VaultStore();
    store.pbStore = PocketBaseStore(
      client: PbClient(port: port, token: pb.token),
      masterKey: key,
    );

    // Legacy path in a bare test env has no secure storage → empty index,
    // but the PB failure is swallowed, not propagated.
    expect(await store.loadFileIndex(forceReload: true), isEmpty);
  });
}
