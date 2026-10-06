import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/remote_manifest.dart';
import 'package:locker/models/sync_profile.dart';
import 'package:locker/models/vaulted_file.dart';
import 'package:locker/services/encryption_service.dart';
import 'package:locker/services/remote/remote_store.dart';
import 'package:locker/services/remote/webdav_store.dart';
import 'package:locker/services/sync_control.dart';
import 'package:locker/services/sync_service.dart';
import 'package:locker/services/sync_state_store.dart';
import 'package:locker/services/vault_store.dart';

void main() {
  late HttpServer server;
  late Directory dir;
  late WebDAVStore store;
  final objects = <String, Uint8List>{};
  final operations = <String>[];
  final locks = <String, String>{};
  var slow = false;
  var supportsDav = true;
  var weakEtag = false;
  var ignoreIf = false;
  var rcloneStyle = false;

  String etag(Uint8List bytes) => '"${SyncService.sha256Hex(bytes)}"';

  setUp(() async {
    objects.clear();
    operations.clear();
    locks.clear();
    slow = false;
    supportsDav = true;
    weakEtag = false;
    ignoreIf = false;
    rcloneStyle = false;
    dir = await Directory.systemTemp.createTemp('latch_dav_');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      final response = request.response;
      operations.add('${request.method} $path');
      try {
        switch (request.method) {
          case 'OPTIONS':
            if (supportsDav) response.headers.set('dav', '1, 2');
            response.statusCode = 200;
          case 'MKCOL':
            response.statusCode = 201;
          case 'PUT':
            final bytes = await request.fold<List<int>>([], (result, chunk) => result..addAll(chunk));
            objects[path] = Uint8List.fromList(bytes);
            response.statusCode = 201;
          case 'HEAD':
            final bytes = objects[path];
            response.statusCode = bytes == null ? 404 : 200;
            if (bytes != null) response.contentLength = bytes.length;
          case 'DELETE':
            objects.remove(path);
            response.statusCode = 204;
          case 'GET':
            final bytes = objects[path];
            if (bytes == null) {
              response.statusCode = 404;
              break;
            }
            response.headers.set('etag', '${weakEtag ? 'W/' : ''}${etag(bytes)}');
            response.contentLength = bytes.length;
            for (var offset = 0; offset < bytes.length; offset += 16384) {
              final end = offset + 16384 > bytes.length ? bytes.length : offset + 16384;
              response.add(Uint8List.sublistView(bytes, offset, end));
              await response.flush();
              if (slow) await Future<void>.delayed(const Duration(milliseconds: 10));
            }
          case 'MOVE':
            final destination = Uri.parse(request.headers.value('destination')!).path;
            final existing = objects[destination];
            final condition = request.headers.value('if');
            final presented = condition == null
                ? null
                : RegExp(r'\(<([^>]+)>\)').firstMatch(condition)?.group(1);
            final lock = locks[destination];
            if (!ignoreIf && lock != null && presented != lock) {
              response.statusCode = 423;
            } else if (!ignoreIf &&
                condition != null &&
                condition.contains('[') &&
                (rcloneStyle ||
                    existing == null ||
                    !condition.contains('[${etag(existing)}]'))) {
              // rclone/x-net-webdav: bracketed entity-tags never satisfy If.
              response.statusCode = 412;
            } else if (request.headers.value('overwrite') == 'F' && existing != null) {
              response.statusCode = 412;
            } else {
              objects[destination] = objects.remove(path)!;
              response.statusCode = existing == null ? 201 : 204;
            }
          case 'LOCK':
            if (locks[path] != null) {
              response.statusCode = 423;
              break;
            }
            final created = objects[path] == null;
            final token = 'opaquelocktoken:${operations.length}';
            locks[path] = token;
            if (created) objects[path] = Uint8List(0);
            response.statusCode = created ? 201 : 200;
            response.headers.set('lock-token', '<$token>');
          case 'UNLOCK':
            final header = request.headers.value('lock-token');
            final token = header == null
                ? null
                : RegExp(r'^<([^>]+)>$').firstMatch(header)?.group(1);
            if (locks[path] != null && token == locks[path]) {
              locks.remove(path);
              response.statusCode = 204;
            } else {
              response.statusCode = 409;
            }
          default:
            response.statusCode = 405;
        }
        await response.close();
      } on HttpException {
        // The client deliberately closes the body during cancellation.
      } on SocketException {
        // The client deliberately closes the body during cancellation.
      }
    });
    store = WebDAVStore(baseUrl: 'http://${server.address.address}:${server.port}');
  });

  tearDown(() async {
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  test('uploads stream to staging, verify, then atomically promote', () async {
    final bytes = Uint8List.fromList(List<int>.generate(512 * 1024, (i) => i % 251));
    final source = File('${dir.path}/source');
    await source.writeAsBytes(bytes);
    final hash = SyncService.sha256Hex(bytes);
    final name = SyncService.blobNameFor(hash);
    final samples = <int>[];
    await store.uploadFile(name, source, hash, SyncControl(), (sent, _) => samples.add(sent));
    expect(objects['/locker/$name'], bytes);
    expect(operations.where((o) => o.startsWith('PUT ')).single, contains('.partial'));
    expect(operations.where((o) => o.startsWith('MOVE ')), hasLength(1));
    expect(objects.keys.any((key) => key.contains('.partial')), isFalse);
    expect(samples.last, bytes.length);
    expect(samples, hasLength(greaterThan(1)));
  });

  test('source hash mismatch cannot replace a canonical blob', () async {
    final source = File('${dir.path}/source');
    await source.writeAsBytes([8, 9]);
    final expected = SyncService.sha256Hex(Uint8List.fromList([1, 2]));
    final name = SyncService.blobNameFor(expected);
    objects['/locker/$name'] = Uint8List.fromList([1, 2]);
    await expectLater(store.uploadFile(name, source, expected, SyncControl(), (sent, total) {}), throwsFormatException);
    expect(objects['/locker/$name'], [1, 2]);
    expect(operations.any((o) => o.startsWith('MOVE ')), isFalse);
  });

  test('publication honors both creation and replacement revision preconditions', () async {
    final a = Uint8List.fromList([1, 2]);
    final b = Uint8List.fromList([3, 4]);
    await store.publishManifest(a, null, SyncControl());
    final read = await store.readManifest(SyncControl());
    expect(read.bytes, a);
    await expectLater(store.publishManifest(b, null, SyncControl()), throwsA(isA<RemoteRevisionChanged>()));
    await store.publishManifest(b, read.revision, SyncControl());
    await expectLater(store.publishManifest(a, read.revision, SyncControl()), throwsA(isA<RemoteRevisionChanged>()));
    expect(objects['/locker/${RemoteStore.manifestName}'], b);
  });

  test('servers without safe-publication capabilities are rejected', () async {
    supportsDav = false;
    await expectLater(store.publishManifest(Uint8List.fromList([1]), null, SyncControl()),
        throwsA(isA<UnsafeRemotePublication>()));
    expect(objects['/locker/${RemoteStore.manifestName}'], isNull);
    supportsDav = true;
    weakEtag = true;
    objects['/locker/${RemoteStore.manifestName}'] = Uint8List.fromList([1]);
    await expectLater(store.readManifest(SyncControl()), throwsA(isA<UnsafeRemotePublication>()));
  });

  test('servers that ignore publication preconditions are rejected', () async {
    ignoreIf = true;
    await expectLater(store.publishManifest(Uint8List.fromList([1]), null, SyncControl()),
        throwsA(isA<UnsafeRemotePublication>()));
    expect(objects['/locker/${RemoteStore.manifestName}'], isNull);
  });

  test('publication falls back to verified exclusive locks when If preconditions are unsupported',
      () async {
    rcloneStyle = true;
    await store.publishManifest(Uint8List.fromList([1, 2]), null, SyncControl());
    expect(store.usesLockPublication, isTrue);
    expect(objects['/locker/${RemoteStore.manifestName}'], [1, 2]);
    final read = await store.readManifest(SyncControl());
    await store.publishManifest(Uint8List.fromList([3, 4]), read.revision, SyncControl());
    expect(objects['/locker/${RemoteStore.manifestName}'], [3, 4]);
    await expectLater(store.publishManifest(Uint8List.fromList([5]), read.revision, SyncControl()),
        throwsA(isA<RemoteRevisionChanged>()));
    expect(objects['/locker/${RemoteStore.manifestName}'], [3, 4]);
  });

  test('a manifest that vanishes mid-sync is never replaced with an empty lock stub', () async {
    rcloneStyle = true;
    await store.publishManifest(Uint8List.fromList([1, 2]), null, SyncControl());
    final read = await store.readManifest(SyncControl());
    objects.remove('/locker/${RemoteStore.manifestName}');
    await expectLater(store.publishManifest(Uint8List.fromList([3]), read.revision, SyncControl()),
        throwsA(isA<RemoteRevisionChanged>()));
    expect(objects.containsKey('/locker/${RemoteStore.manifestName}'), isFalse);
  });

  test('download cancellation stops a real HTTP body partway through', () async {
    objects['/locker/blob'] = Uint8List(1024 * 1024);
    slow = true;
    final control = SyncControl();
    var received = 0;
    final destination = File('${dir.path}/partial');
    await expectLater(store.downloadFile('blob', destination, control, (bytes, _) {
      received = bytes;
      control.cancel();
    }), throwsA(isA<SyncCancelled>()));
    expect(received, greaterThan(0));
    expect(received, lessThan(1024 * 1024));
    expect(await destination.length(), received);
  });

  test('syncNow streams through the worker and recovers after an index write failure',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
    const secureChannel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final storage = <String, String>{};
    var failIndexWrite = false;
    messenger.setMockMethodCallHandler(secureChannel, (call) async {
      final args = (call.arguments ?? const <String, Object?>{}) as Map;
      final key = args['key'] as String?;
      switch (call.method) {
        case 'read':
          return storage[key];
        case 'write':
          if (failIndexWrite && key == VaultStore.vaultIndexKey) {
            throw PlatformException(code: 'disk-full');
          }
          storage[key!] = args['value'] as String;
          return null;
        case 'delete':
          storage.remove(key);
          return null;
        case 'deleteAll':
          storage.clear();
          return null;
      }
      return null;
    });
    final crypto = EncryptionService.instance;
    addTearDown(() async {
      await crypto.evictCachedKeys();
      messenger.setMockMethodCallHandler(secureChannel, null);
    });

    final vaultDir = Directory('${dir.path}/appdocs/.locker_vault');
    await vaultDir.create(recursive: true);
    for (final sub in [
      'images',
      'videos',
      'songs',
      'documents',
      'thumbnails',
      'temp',
    ]) {
      await Directory('${vaultDir.path}/$sub').create();
    }
    final vault = VaultStore()..vaultDirectory = vaultDir;

    final payload = Uint8List.fromList(List<int>.generate(4096, (i) => i % 251));
    final source = File('${vaultDir.path}/images/${'a' * 64}.jpg');
    await source.writeAsBytes(payload);
    final hash = SyncService.sha256Hex(payload);
    await crypto.unlockMasterKey('integration-credential');
    final masterKey = Uint8List.fromList(await crypto.getMasterKey());
    final local = VaultedFile(
      id: 'a',
      originalName: 'a.jpg',
      vaultPath: source.path,
      type: VaultedFileType.image,
      mimeType: 'image/jpeg',
      fileSize: payload.length,
      dateAdded: DateTime.utc(2024, 1, 1),
      dateModified: DateTime.utc(2024, 1, 1),
    );
    vault.cachedFiles = [local];
    await vault.saveFileIndex();

    final profile = SyncProfile(
      id: 'p',
      serverUrl: 'http://${server.address.address}:${server.port}',
      basePath: '/locker',
      direction: SyncDirection.twoWay,
      wifiOnly: false,
    );
    final service = SyncService(vault, crypto);
    final manifestKey = '/locker/${RemoteStore.manifestName}';

    final first =
        await service.syncNow(profile: profile, password: '', deviceId: 'devA');
    expect(first.blobsPushed, 1);
    await service.complete(profile, first, crypto.cacheGeneration);
    expect(objects['/locker/${SyncService.blobNameFor(hash)}'], payload);
    final published =
        SyncService.decryptManifest(objects[manifestKey]!, masterKey);
    expect(published.entries.single.contentHash, hash);

    objects[manifestKey] = SyncService.encryptManifest(
      RemoteManifest(
        deviceId: 'devB',
        generatedAt: DateTime.now().toUtc(),
        entries: [published.entries.single.copyWith(tags: const ['server'])],
      ),
      masterKey,
    );
    final target = SyncStateStore.targetId(profile);
    final stateStore = SyncStateStore(vaultDir.path, masterKey);
    failIndexWrite = true;
    final pending =
        await service.syncNow(profile: profile, password: '', deviceId: 'devA');
    await expectLater(service.complete(profile, pending, crypto.cacheGeneration),
        throwsA(isA<PlatformException>()));
    expect(await stateStore.read(target, journal: true), isNotNull);
    expect((await stateStore.load(target)).baseline['a']!.tags,
        isNot(contains('server')));
    expect(storage[VaultStore.vaultIndexKey], isNot(contains('server')));

    failIndexWrite = false;
    vault.cachedFiles = null;
    final recovered =
        await service.syncNow(profile: profile, password: '', deviceId: 'devA');
    await service.complete(profile, recovered, crypto.cacheGeneration);
    expect(await stateStore.read(target, journal: true), isNull);
    expect((await stateStore.load(target)).baseline.keys, contains('a'));
    expect(storage[VaultStore.vaultIndexKey], contains('server'));
  });
}
