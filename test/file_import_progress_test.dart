import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/encryption_algorithm.dart';
import 'package:locker/models/operation_progress.dart';
import 'package:locker/providers/operation_provider.dart';
import 'package:locker/services/encryption_service.dart';
import 'package:locker/services/file_import_service.dart';
import 'package:locker/services/vault_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('latch_import_progress');
    final storage = <String, String>{};
    messenger.setMockMethodCallHandler(storageChannel, (call) async {
      final args = (call.arguments ?? {}) as Map;
      final key = args['key'] as String?;
      switch (call.method) {
        case 'read':
          return storage[key];
        case 'write':
          storage[key!] = args['value'] as String;
        case 'delete':
          storage.remove(key);
        case 'containsKey':
          return storage.containsKey(key);
        case 'readAll':
          return storage;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(pathChannel, (_) async => root.path);
    await EncryptionService.instance.evictCachedKeys();
    await VaultService.instance.loadIndexesForTesting();
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(storageChannel, null);
    messenger.setMockMethodCallHandler(pathChannel, null);
    await root.delete(recursive: true);
  });

  test('real duplicate-only document imports produce an informational result',
      () async {
    final source = File('${root.path}/document.txt')
      ..writeAsStringSync('already safely stored');
    final service = FileImportService.instance;
    final infos = <FileProgressInfo>[];
    final first = await service.importFromDocumentFiles(
      filePaths: [source.path],
      deleteOriginals: false,
      onFileProgress: infos.add,
    );
    expect(first.importedCount, 1);
    expect(infos.first.completedFiles, isNull);
    expect(infos.last.completedFiles, 1);
    expect(infos.last.batchProcessedBytes, source.lengthSync());

    final second = await service.importFromDocumentFiles(
      filePaths: [source.path],
      deleteOriginals: false,
    );
    expect(second.skippedDuplicates, 1);
    expect(second.failedCount, 0);
    expect(importOutcome(second).kind, OperationOutcomeKind.info);
    expect(source.existsSync(), isTrue);
  });

  test('duplicates do not hide inaccessible selected files', () async {
    final source = File('${root.path}/document.txt')
      ..writeAsStringSync('already stored');
    final service = FileImportService.instance;
    await service.importFromDocumentFiles(
        filePaths: [source.path], deleteOriginals: false);
    final result = await service.importFromDocumentFiles(
      filePaths: [source.path, '${root.path}/missing.txt'],
      deleteOriginals: false,
    );
    expect(result.importedCount, 0);
    expect(result.skippedDuplicates, 1);
    expect(result.failedCount, 1);
    expect(importOutcome(result).kind, OperationOutcomeKind.error);
  });

  for (final convert in [false, true]) {
    test(
        'partial ${convert ? 'document conversion' : 'file'} imports never '
        'delete a failed original with the same name', () async {
      final goodDir = Directory('${root.path}/good')..createSync();
      final badDir = Directory('${root.path}/bad')..createSync();
      final good = File('${goodDir.path}/same.txt')
        ..writeAsStringSync('copied successfully');
      final bad = File('${badDir.path}/same.txt')
        ..writeAsStringSync('must remain when encryption fails');
      final choices = {
        good.path: (encrypt: false, algorithm: EncryptionAlgorithm.aes256Gcm),
        bad.path: (encrypt: true, algorithm: EncryptionAlgorithm.aes256Gcm),
      };
      final service = FileImportService.instance;
      final OperationOutcome outcome;
      if (convert) {
        outcome = officeImportOutcome(
            await service.importFromDocumentFilesWithConversion(
          filePaths: [good.path, bad.path],
          perFileEncryption: choices,
          onConversionConfirmation: (_) async => true,
        ));
      } else {
        outcome = importOutcome(await service.importFromDocumentFiles(
          filePaths: [good.path, bad.path],
          perFileEncryption: choices,
        ));
      }
      expect(outcome.kind, OperationOutcomeKind.warning);
      expect(outcome.processedFiles, 1);
      expect(good.existsSync(), isFalse);
      expect(bad.existsSync(), isTrue);
      final vaulted = await VaultService.instance.getAllFiles();
      expect(vaulted, hasLength(1));
      expect(File(vaulted.single.vaultPath).readAsStringSync(),
          'copied successfully');
    });
  }
}
