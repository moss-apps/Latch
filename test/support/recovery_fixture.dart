import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/vaulted_file.dart';
import 'package:locker/services/note_service.dart';
import 'package:locker/services/password_service.dart';
import 'package:locker/services/vault_service.dart';

class RecoveryFixture {
  final storage = <String, String>{};
  bool Function(String key, String value)? failWrite;
  late Directory root;
  late VaultService vault;

  Future<void> initialize() async {
    final preferred = Directory('/tmp/opencode');
    root = await (await preferred.exists() ? preferred : Directory.systemTemp)
        .createTemp('latch_recovery_');
    for (final folder in ['documents', 'support', 'cache', 'backup']) {
      await Directory('${root.path}/$folder').create();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final args = (call.arguments ?? {}) as Map;
        final key = args['key'] as String?;
        switch (call.method) {
          case 'read':
            return storage[key];
          case 'write':
            final value = args['value'] as String;
            if (failWrite?.call(key!, value) ?? false) {
              throw PlatformException(code: 'test-write-failed');
            }
            storage[key!] = value;
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
        }
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => switch (call.method) {
        'getApplicationDocumentsDirectory' => '${root.path}/documents',
        'getApplicationSupportDirectory' => '${root.path}/support',
        'getTemporaryDirectory' => '${root.path}/cache',
        _ => null,
      },
    );
    vault = await reopen();
  }

  Future<VaultService> reopen() async {
    final service = VaultService();
    await service.loadIndexesForTesting();
    return service;
  }

  Future<VaultedFile> file(String id,
      {bool decoy = false, List<int> bytes = const [1, 2, 3]}) async {
    final dir = decoy
        ? await vault.store.ensureDecoyDirectory()
        : await vault.store.ensureVaultDirectory();
    final path = '${dir.path}/documents/$id.dat';
    await File(path).writeAsBytes(bytes);
    return VaultedFile(
        id: id,
        originalName: '$id.dat',
        vaultPath: path,
        type: VaultedFileType.document,
        mimeType: 'application/octet-stream',
        fileSize: bytes.length,
        dateAdded: DateTime.utc(2024),
        isDecoy: decoy);
  }

  Future<void> seed(List<VaultedFile> files, {bool decoy = false}) async {
    if (decoy) {
      vault.store.cachedDecoyFiles = List.of(files);
    } else {
      vault.store.cachedFiles = List.of(files);
    }
    await vault.store
        .saveFileIndex(isDecoy: decoy, strict: true, allowEmpty: true);
  }

  Future<void> dispose() async {
    NoteService.instance.clearCache();
    PasswordService.instance.clearCache();
    for (final channel in [
      'plugins.it_nomads.com/flutter_secure_storage',
      'plugins.flutter.io/path_provider'
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(channel), null);
    }
    await root.delete(recursive: true);
  }
}
