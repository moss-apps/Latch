import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/crypto/key_derivation.dart';
import 'package:locker/crypto/key_wrap.dart';
import 'package:locker/models/remote_manifest.dart';
import 'package:locker/services/desktop_link/restore_controller.dart';
import 'package:locker/services/desktop_link/transfer_client.dart';
import 'package:locker/services/encryption_service.dart';
import 'package:locker/services/sync_service.dart';
import 'package:locker/services/vault_store.dart';
import 'package:pointycastle/export.dart' show InvalidCipherTextException;

/// Stub latchd: push (PUT) set while [restoreMode] is false, restore (GET)
/// set once it flips — mirroring the P6.3 receiver modes.
class StubDesktop {
  StubDesktop._(this._server, this.token);

  final HttpServer _server;
  final String token;

  final blobs = <String, Uint8List>{};
  Map<String, dynamic>? keybundle;
  Uint8List? manifest;
  final order = <String>[];
  bool restoreMode = false;

  static Future<StubDesktop> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final random = Random.secure();
    final token = List<int>.generate(32, (_) => random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final stub = StubDesktop._(server, token);
    server.listen(stub._handle);
    return stub;
  }

  Uri get base => Uri.parse('http://127.0.0.1:${_server.port}');
  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    if (req.headers.value(HttpHeaders.authorizationHeader) != 'Bearer $token') {
      _json(req, HttpStatus.unauthorized, {'error': 'unauthorized'});
      return;
    }
    final segments = req.uri.pathSegments;

    if (req.method == 'GET' && segments.length == 1 && segments[0] == 'info') {
      order.add('info');
      _json(req, HttpStatus.ok, {
        'app': 'latchd',
        'protocol': 2,
        'mode': restoreMode ? 'restore' : 'push',
        'hasManifest': manifest != null,
        'hasKeybundle': keybundle != null,
        'hashes': blobs.keys.toList(),
      });
      return;
    }

    if (!restoreMode && req.method == 'PUT' && segments.length == 1) {
      final bytes = await _body(req);
      order.add(segments[0]);
      switch (segments[0]) {
        case 'keybundle':
          keybundle = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
          _json(req, HttpStatus.ok, {'stored': 'keybundle'});
        case 'manifest':
          manifest = bytes;
          _json(req, HttpStatus.ok, {'stored': 'manifest'});
        default:
          _json(req, HttpStatus.notFound, {'error': 'unknown route'});
      }
      return;
    }
    if (!restoreMode &&
        req.method == 'PUT' &&
        segments.length == 2 &&
        segments[0] == 'blob') {
      final sha = segments[1];
      final bytes = await _body(req);
      if (sha256.convert(bytes).toString() != sha) {
        _json(req, HttpStatus.unprocessableEntity, {'error': 'mismatch'});
        return;
      }
      order.add('blob');
      blobs[sha] = bytes;
      _json(req, HttpStatus.ok, {'stored': sha});
      return;
    }

    if (restoreMode && req.method == 'GET') {
      if (segments.length == 1 && segments[0] == 'keybundle') {
        if (keybundle == null) {
          _json(req, HttpStatus.notFound, {'error': 'no keybundle'});
          return;
        }
        order.add('get:keybundle');
        _bytes(req, Uint8List.fromList(utf8.encode(jsonEncode(keybundle))));
        return;
      }
      if (segments.length == 1 && segments[0] == 'manifest') {
        if (manifest == null) {
          _json(req, HttpStatus.notFound, {'error': 'no manifest'});
          return;
        }
        order.add('get:manifest');
        _bytes(req, manifest!);
        return;
      }
      if (segments.length == 2 && segments[0] == 'blob') {
        final blob = blobs[segments[1]];
        if (blob == null) {
          _json(req, HttpStatus.notFound, {'error': 'blob not in backup'});
          return;
        }
        order.add('get:blob');
        _bytes(req, blob);
        return;
      }
    }

    _json(req, HttpStatus.notFound, {'error': 'unknown route'});
  }

  Future<Uint8List> _body(HttpRequest req) async {
    final body = await req.fold<List<int>>([], (acc, c) => acc..addAll(c));
    return Uint8List.fromList(body);
  }

  void _json(HttpRequest req, int status, Map<String, dynamic> body) {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    req.response.close();
  }

  void _bytes(HttpRequest req, Uint8List bytes) {
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.binary
      ..add(bytes);
    req.response.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The binding fakes HttpClient (every request 400s); the stub desktop
  // is a real loopback server, so restore the real implementation.
  HttpOverrides.global = null;

  // P6.3 verification (docs/desktop_backup.md): build a backup by pushing
  // from a test vault, wipe the vault, restore via pre-vault pull, unlock
  // with the original password, index matches.
  test('desktop backup restore end-to-end', () async {
    const secureChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    final storage = <String, String>{};
    final tmpDir = Directory.systemTemp.createTempSync('locker_restore_e2e');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (call) async {
      final args = (call.arguments ?? {}) as Map;
      final key = args['key'] as String?;
      switch (call.method) {
        case 'read':
          return storage[key];
        case 'write':
          storage[key!] = args['value'] as String;
          return null;
        case 'delete':
          storage.remove(key);
          return null;
        case 'deleteAll':
          storage.clear();
          return null;
        case 'containsKey':
          return storage.containsKey(key);
        case 'readAll':
          return storage;
        default:
          return null;
      }
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tmpDir.path;
      }
      return null;
    });

    final stub = await StubDesktop.start();
    final pushClient = DesktopPushClient();
    final restoreClient = DesktopRestoreClient();
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, null);
      pushClient.close();
      restoreClient.close();
      await stub.close();
      try {
        tmpDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    // 1. Build a test vault: master key wrapped with the original vault
    //    password, plus a manifest v2 with three encrypted blobs.
    const originalPassword = 'correct horse battery staple';
    final crypto = EncryptionService.instance;
    await crypto.setPendingCredential(originalPassword);
    final master = await crypto.getMasterKey();
    final keybundle = await crypto.exportKeybundle();
    expect(keybundle, isNotNull, reason: 'test vault must be on wrapped keys');

    final entries = <ManifestEntry>[];
    final blobs = <String, Uint8List>{};
    final specs = [
      ('pic-1.jpg', 'image', 'image/jpeg', 120),
      ('notes.txt', 'document', 'text/plain', 64),
      ('clip.mp4', 'video', 'video/mp4', 256),
    ];
    for (var i = 0; i < specs.length; i++) {
      final (name, type, mime, size) = specs[i];
      final content =
          Uint8List.fromList(List<int>.generate(size, (n) => (n + i * 7) % 251));
      final sha = sha256.convert(content).toString();
      blobs[sha] = content;
      entries.add(ManifestEntry(
        id: 'file-$i',
        contentHash: sha,
        modifiedAt: DateTime.utc(2026, 9, 1, 12, i),
        originalName: name,
        type: type,
        mimeType: mime,
        fileSize: content.length,
        dateAdded: DateTime.utc(2026, 8, 30),
        dateModified: DateTime.utc(2026, 9, 1, 12, i),
        isEncrypted: true,
        encryptionIv: base64Encode(KeyDerivation.generateIV()),
        encryptionAlgorithm: 'aes256Ctr',
        keyDerivationSalt: base64Encode(KeyDerivation.generateFileSalt()),
        kdfIterations: 100000,
      ));
    }
    final manifestBytes = SyncService.encryptManifest(
      RemoteManifest(
        deviceId: 'test-vault',
        generatedAt: DateTime.utc(2026, 9, 7),
        entries: entries,
      ),
      master,
    );

    // 2. Push it to the desktop (backup built).
    final report = await pushClient.push(
      base: stub.base,
      token: stub.token,
      snapshot: DesktopVaultSnapshot(
        fileCount: blobs.length,
        totalBytes: blobs.values.fold<int>(0, (n, b) => n + b.length),
        manifestBytes: manifestBytes,
        blobs: blobs,
        keybundle: keybundle,
      ),
    );
    expect(report.pushed, 3);
    expect(stub.order.last, 'manifest');
    expect(stub.keybundle, isNotNull);
    expect(stub.manifest, isNotNull);

    // 3. Wipe the phone (only the test's temp vault + secure storage).
    final vaultDir = Directory('${tmpDir.path}/.locker_vault');
    if (vaultDir.existsSync()) vaultDir.deleteSync(recursive: true);
    storage.clear();
    expect(storage, isEmpty);

    // 4. Desktop opens a restore session; the phone checks it.
    stub.restoreMode = true;
    final info = await restoreClient.check(base: stub.base, token: stub.token);
    expect(info.isRestoreSession, isTrue);
    expect(info.hasManifest, isTrue);
    expect(info.hasKeybundle, isTrue);
    expect(info.blobCount, 3);

    // 5. Pre-vault pull: wrong password cannot unwrap — nothing installed.
    final fetchedKb = await restoreClient.fetchKeybundle(
        base: stub.base, token: stub.token);
    expect(fetchedKb, isNotNull);
    await expectLater(
      crypto.installRestoredKeybundle(fetchedKb!, 'wrong password'),
      throwsA(isA<InvalidCipherTextException>()),
    );
    expect(storage.containsKey('vault_master_key_wrapped'), isFalse,
        reason: 'failed unwrap must not install anything');

    // 6. Restore with the ORIGINAL password; setup resumes around it.
    final progress = <RestoreProgress>[];
    final store = VaultStore();
    final restoreReport = await RestoreController(store, crypto).restoreFresh(
      client: restoreClient,
      base: stub.base,
      token: stub.token,
      keybundle: fetchedKb,
      originalPassword: originalPassword,
      onProgress: progress.add,
    );
    expect(restoreReport.restored, 3);
    expect(restoreReport.skipped, 0);
    expect(progress.last.restored, 3);
    expect(
      stub.order.indexOf('get:manifest') < stub.order.indexOf('get:blob'),
      isTrue,
      reason: 'manifest is pulled before any blob',
    );

    // 7. Index matches: every entry imported with its content hash, and
    //    the ciphertext landed on disk at the vault layout path.
    final index = store.cachedFiles!;
    expect(index.length, 3);
    for (var i = 0; i < specs.length; i++) {
      final (name, type, _, size) = specs[i];
      final f = index.firstWhere((f) => f.id == 'file-$i');
      expect(f.originalName, name);
      expect(f.type.name, type);
      expect(f.fileSize, size);
      expect(f.remoteHash, entries[i].contentHash);
      final vp = SyncService.vaultPathFor(
          vaultRoot: '${tmpDir.path}/.locker_vault', entry: entries[i]);
      expect(File(vp).existsSync(), isTrue, reason: '$name blob missing');
      expect(sha256.convert(File(vp).readAsBytesSync()).toString(),
          entries[i].contentHash);
    }
    // The index was committed, not just cached.
    expect((await VaultStore().loadFileIndex()).length, 3);

    // 8. Unlock with the original password on a fresh read of secure
    //    storage (what unlockMasterKey does after an app restart).
    final kwk = await KeyDerivation.argon2id(
        originalPassword, base64Decode(storage['vault_kwk_salt']!));
    expect(
      KeyWrap.unwrap(
        base64Decode(storage['vault_master_key_wrapped']!),
        kwk,
        base64Decode(storage['vault_kwk_iv']!),
      ),
      master,
    );

    // 9. Setup resumes: choosing a new device credential re-wraps the
    //    restored key under it (one-shot), same master key inside.
    final restoredWrapSalt = storage['vault_kwk_salt'];
    await crypto.setPendingCredential('123456');
    expect(storage['vault_kwk_salt'], isNot(restoredWrapSalt));
    final newKwk = await KeyDerivation.argon2id(
        '123456', base64Decode(storage['vault_kwk_salt']!));
    expect(
      KeyWrap.unwrap(
        base64Decode(storage['vault_master_key_wrapped']!),
        newKwk,
        base64Decode(storage['vault_kwk_iv']!),
      ),
      master,
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
