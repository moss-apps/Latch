import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

import 'encryption_service.dart';
import 'compression_service.dart';
import 'note_service.dart';
import 'password_service.dart';
import 'sensitive_isolate.dart';
import 'share_intake_service.dart';
import 'smart_collection_service.dart';
import 'vault_service.dart';

Future<void> clearSensitiveSession() async {
  final workersStopped = EncryptionService.instance.evictCachedKeys();
  SensitiveIsolate.cancelAll();
  CompressionService.instance.clearSensitiveState();
  VaultService.instance.detachSessionStore();
  NoteService.instance.clearCache();
  PasswordService.instance.clearCache();
  SmartCollectionService.instance.clearCache();
  PaintingBinding.instance.imageCache.clear();
  PaintingBinding.instance.imageCache.clearLiveImages();
  await workersStopped;
  await VaultService.instance.cleanupTemp(throwOnError: true);
  final documents = await getApplicationDocumentsDirectory();
  await _removeScratch(Directory('${documents.path}/.locker_temp'));
  await ShareIntakeService.instance.onSessionLocked();
  final temporary = await getTemporaryDirectory();
  if (await temporary.exists()) {
    await for (final entry in temporary.list(followLinks: false)) {
      final name = entry.path.split(Platform.pathSeparator).last;
      if (name.startsWith('lkr_') || name.startsWith('locker_backup_')) {
        await _removeScratch(entry);
      }
    }
  }
}

Future<void> _removeScratch(FileSystemEntity entry) async {
  if (await entry.exists()) await entry.delete(recursive: true);
}
