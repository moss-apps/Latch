import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/services/encryption_service.dart';
import 'package:locker/services/session_cleanup.dart';
import 'package:locker/services/sensitive_isolate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final crypto = EncryptionService.instance;
  final storage = <String, String>{};
  late Directory root;
  const secureStorage =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const paths = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('latch_session_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (call) async {
      final args = (call.arguments ?? {}) as Map;
      final key = args['key'] as String?;
      switch (call.method) {
        case 'read':
          return storage[key];
        case 'write':
          storage[key!] = args['value'] as String;
        case 'delete':
          storage.remove(key);
        case 'deleteAll':
          storage.clear();
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => root.path);
  });

  tearDownAll(() async {
    await crypto.evictCachedKeys();
    SensitiveIsolate.cancelAll();
    await root.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, null);
  });

  test(
      'lock zeros key buffers, rejects stale keys, preserves disk, and reauth works',
      () async {
    final master = await crypto.unlockMasterKey('session-test-password');
    final originalKey = Uint8List.fromList(master);
    final decoy =
        await crypto.unlockMasterKey('decoy-test-password', isDecoy: true);
    final derived =
        await crypto.deriveFileKeyAsync(master, Uint8List(32), 1000);
    final payload = Uint8List.fromList([10, 20, 30, 40]);
    final encryptedPath = '${root.path}/.locker_vault/data/file.enc';
    await File(encryptedPath).parent.create(recursive: true);
    final encrypted = await crypto
        .encryptBytesStreamedGcm(payload, encryptedPath, derivedKey: derived);
    expect(encrypted.success, true);
    final diskBytes = await File(encryptedPath).readAsBytes();
    final storageBefore = Map<String, String>.from(storage);
    final preview = File('${root.path}/.locker_vault/temp/preview.jpg');
    await preview.parent.create(recursive: true);
    await preview.writeAsBytes(payload);
    final scratch = File('${root.path}/.locker_temp/decrypted');
    await scratch.parent.create(recursive: true);
    await scratch.writeAsBytes(payload);
    final thumbnailScratch = File('${root.path}/lkr_thumb_test');
    await thumbnailScratch.writeAsBytes(payload);
    final unrelated = File('${root.path}/keep_me');
    await unrelated.writeAsBytes(payload);

    await clearSensitiveSession();
    expect(master, everyElement(0));
    expect(decoy, everyElement(0));
    expect(derived, everyElement(0));
    expect(storage, storageBefore);
    expect(await File(encryptedPath).readAsBytes(), diskBytes);
    expect(await unrelated.exists(), true);
    expect(await preview.exists(), false);
    expect(await scratch.exists(), false);
    expect(await thumbnailScratch.exists(), false);
    await expectLater(crypto.getMasterKey(), throwsStateError);
    final denied = await crypto.decryptStreamedFileToMemoryGcm(
        encryptedPath, encrypted.iv!,
        derivedKey: originalKey);
    expect(denied.success, false);

    final unlocked = await crypto.unlockMasterKey('session-test-password');
    expect(unlocked, originalKey);
    final newDerived =
        await crypto.deriveFileKeyAsync(unlocked, Uint8List(32), 1000);
    final decrypted = await crypto.decryptStreamedFileToMemoryGcm(
        encryptedPath, encrypted.iv!,
        derivedKey: newDerived);
    expect(decrypted.success, true);
    expect(decrypted.data, payload);
  });

  test('derivation completing after eviction cannot refill the key cache',
      () async {
    final master = await crypto.getMasterKey();
    final pending =
        crypto.deriveFileKeyAsync(master, Uint8List.fromList([1, 2, 3]), 1000);
    final rejected = expectLater(pending, throwsStateError);
    await crypto.evictCachedKeys();
    await rejected;
    await expectLater(crypto.getMasterKey(), throwsStateError);
  });

  test('key-holding background worker is cancelled on lock', () async {
    final pending = SensitiveIsolate.run(() async {
      await Future<void>.delayed(const Duration(seconds: 30));
      return 'sensitive result';
    });
    final rejected = expectLater(pending, throwsStateError);
    SensitiveIsolate.cancelAll();
    await rejected;
  });

  test('managed worker returns normal results and propagates failures',
      () async {
    expect(await SensitiveIsolate.run(() async => 42), 42);
    await expectLater(
      SensitiveIsolate.run<Object>(() async => throw StateError('failed')),
      throwsA(isA<SyncWorkerFailure>()
          .having((e) => e.message, 'message', isNotEmpty)
          .having((e) => e.diagnosticId, 'diagnosticId', isNotEmpty)),
    );
  });

  test('active worker is killed rather than publishing a late result',
      () async {
    final ready = ReceivePort();
    addTearDown(ready.close);
    final signal = ready.sendPort;
    final pending = SensitiveIsolate.run(() async {
      signal.send('running');
      await Future<void>.delayed(const Duration(seconds: 30));
      return 'sensitive result';
    });
    final rejected = expectLater(pending, throwsStateError);
    await ready.first;
    SensitiveIsolate.cancelAll();
    await rejected;
  });

  test('lock during streamed preview decryption removes partial plaintext',
      () async {
    await crypto.unlockMasterKey('session-test-password');
    final source = '${root.path}/stream.enc';
    final destination = '${root.path}/.locker_vault/temp/stream.preview';
    await File(destination).parent.create(recursive: true);
    final encrypted = await crypto.encryptBytesStreamedGcm(
      Uint8List(1024 * 1024),
      source,
    );
    expect(encrypted.success, true);
    var locked = false;
    final decrypted = await crypto.decryptFileStreamed(
        source, destination, encrypted.iv!, onProgress: (progress, total) {
      if (progress > 0 && !locked) {
        locked = true;
        crypto.evictCachedKeys();
      }
    });
    expect(locked, true);
    expect(decrypted.success, false);
    expect(await File(destination).exists(), false);
    expect(await File('$destination.tmp').exists(), false);
    expect(await File(source).exists(), true);
  });
}
