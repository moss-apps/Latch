import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/vaulted_file.dart';
import 'package:locker/services/pb/cipher_codec.dart';
import 'package:locker/services/pb/daos/vault_file_dao.dart';
import 'package:locker/services/pb/pb_client.dart';
import 'package:locker/services/pb/pocketbase_store.dart';

/// In-process stand-in for the sidecar's REST surface (token gate, CRUD,
/// pagination). Speaks exactly what PbClient + the DAOs use.
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
      final seg = req.uri.pathSegments; // api collections {c} records [id]
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
          if (rows.remove(id!) == null) {
            _json(res, 404, {'error': 'missing'});
          } else {
            _json(res, 204, {});
          }
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

VaultedFile _file(String name) => VaultedFile(
      id: '11111111-2222-3333-4444-555555555555-$name',
      originalName: name,
      vaultPath: '/vault/ab/cd/$name.enc',
      type: VaultedFileType.image,
      mimeType: 'image/jpeg',
      fileSize: 1234,
      dateAdded: DateTime.utc(2026, 1, 2, 3, 4, 5),
      tags: const ['secret-tag'],
      isEncrypted: true,
      modifiedAt: DateTime.utc(2026, 2, 3, 4, 5, 6),
    );

void main() {
  final key = Uint8List.fromList(List.filled(32, 7));

  test('CipherCodec hides plaintext and rejects wrong key / tamper', () {
    final codec = CipherCodec(key);
    final env = codec.seal('passport.jpg');

    expect(env.contains('passport'), isFalse);
    expect(codec.open(env), 'passport.jpg');

    expect(
      () => CipherCodec(Uint8List.fromList(List.filled(32, 8))).open(env),
      throwsA(anything), // GCM tag must fail on wrong key
    );
    final bytes = base64Decode(env);
    bytes[bytes.length - 1] ^= 0xFF;
    expect(() => codec.open(base64Encode(bytes)), throwsA(anything));
  });

  test('VaultFileDao round-trip: cipher_meta is ciphertext at rest, '
      'plaintext after read', () async {
    final pb = _FakePb();
    final port = await pb.start();
    addTearDown(pb.stop);
    final dao = VaultFileDao(PbClient(port: port, token: pb.token), key);

    final file = _file('passport.jpg');
    await dao.put(file);

    final row = pb.db['vault_files']!.values.single;
    expect(row['blob_ref'], file.vaultPath);
    expect(row['modified_at'], file.modifiedAt!.millisecondsSinceEpoch);
    expect(jsonEncode(row['cipher_meta']).contains('passport'), isFalse);

    final back = (await dao.list()).single;
    expect(jsonEncode(back.toJson()), jsonEncode(file.toJson()));
  });

  test('PocketBaseStore save reconciles ghosts; tag rides cipher_name; '
      'empty albums seed defaults', () async {
    final pb = _FakePb();
    final port = await pb.start();
    addTearDown(pb.stop);
    final store = PocketBaseStore(
      client: PbClient(port: port, token: pb.token),
      masterKey: key,
    );

    final f1 = _file('a.jpg');
    final f2 = _file('b.jpg');
    store.cachedFiles = [f1, f2];
    await store.saveFileIndex();
    expect(pb.db['vault_files']!.length, 2);

    store.cachedFiles = [f1]; // b deleted from cache
    await store.saveFileIndex();
    expect(await store.loadFileIndex(forceReload: true), [f1]);

    store.cachedTags = const [TagInfo(name: 'work', colorValue: 42)];
    await store.saveTags();
    final tagRow = pb.db['tags']!.values.single;
    expect(tagRow['cipher_name'].toString().contains('work'), isFalse);
    expect((await store.loadTags(forceReload: true)).single.colorValue, 42);

    expect((await store.loadAlbums()).map((a) => a.id), contains('favorites'));
    expect(pb.db['albums']!.length, 2);
  });
}
