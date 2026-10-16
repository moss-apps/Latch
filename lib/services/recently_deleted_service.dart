import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/deleted_vault_item.dart';
import '../models/vault_settings.dart';
import '../models/vaulted_file.dart';
import 'encryption_service.dart';
import 'file_operation_gate.dart';
import 'sync_state_store.dart';
import 'vault_store.dart';

/// Local-only recovery, serialized with imports, sync and session teardown.
/// Every destructive step follows a durable receipt; interrupted transitions
/// are idempotently completed on the next unlocked maintenance pass.
class RecentlyDeletedService extends ChangeNotifier {
  RecentlyDeletedService(
    this.store,
    this.encryption, {
    DateTime Function()? clock,
    this.onChanged,
  }) : clock = clock ?? DateTime.now;

  final VaultStore store;
  final EncryptionService encryption;
  final DateTime Function() clock;
  VoidCallback? onChanged;
  FileOperationGate get _gate => FileOperationGate.instance;

  void _changed() {
    onChanged?.call();
    notifyListeners();
  }

  void _check() {
    if (!_gate.allowsMutation) throw StateError('Vault operation interrupted');
  }

  Future<void> _put(DeletedVaultItem item, bool decoy) async {
    _check();
    final items = await store.loadDeletedItems(isDecoy: decoy);
    items.removeWhere((e) => e.file.id == item.file.id);
    items.add(item);
    _check();
    await store.saveDeletedItems(items, isDecoy: decoy);
  }

  Future<void> _forget(DeletedVaultItem item, bool decoy) async {
    _check();
    final items = await store.loadDeletedItems(isDecoy: decoy);
    items.removeWhere((e) => e.file.id == item.file.id);
    _check();
    await store.saveDeletedItems(items, isDecoy: decoy);
  }

  Future<Directory> _root(bool decoy) =>
      decoy ? store.ensureDecoyDirectory() : store.ensureVaultDirectory();

  Future<List<Map<String, dynamic>>> _auxiliary(String key) async {
    final raw = await store.read(key);
    return raw == null
        ? []
        : (jsonDecode(raw) as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
  }

  Future<bool> delete(VaultedFile file, {bool isDecoy = false}) =>
      _gate.mutate(() async {
        try {
          // A stale caller must not replace the only copy of a recovery receipt.
          if ((await store.loadDeletedItems(isDecoy: isDecoy))
              .any((item) => item.file.id == file.id)) {
            return false;
          }
          final settings = await store.loadSettings();
          final days = VaultSettings.retentionOptions
                  .contains(settings.recentlyDeletedRetentionDays)
              ? settings.recentlyDeletedRetentionDays
              : 30;
          final root = await _root(isDecoy);
          final token = const Uuid().v4();
          final noteId = file.metadata?['noteId'];
          final passwordId = file.metadata?['passwordId'];
          final key = noteId != null
              ? 'locker_notes_index'
              : passwordId != null
                  ? 'locker_passwords_index'
                  : null;
          final auxKey = key == null ? null : '$key${isDecoy ? '_decoy' : ''}';
          Map<String, dynamic>? record;
          if (auxKey != null) {
            final records = await _auxiliary(auxKey);
            for (final e in records) {
              if (e['id'] == (noteId ?? passwordId)) record = e;
            }
          }
          final now = clock().toUtc();
          final receipt = DeletedVaultItem(
            file: file,
            deletedAt: now,
            expiresAt: now.add(Duration(days: days)),
            payloadPath: '${root.path}/.recently-deleted/$token.payload',
            thumbnailPath: file.thumbnailPath == null
                ? null
                : '${root.path}/.recently-deleted/$token.thumbnail',
            auxiliaryKey: auxKey,
            auxiliaryRecord: record,
          );
          // No payload/index mutation until this write succeeds.
          await _put(receipt, isDecoy);
          await _recordDeletion(receipt, isDecoy);
          await _finishDelete(receipt, isDecoy);
          if (days == 0) await _purge(receipt, isDecoy);
          return true;
        } catch (error) {
          debugPrint('Local deletion pending/retry required: $error');
          return false;
        } finally {
          _changed();
        }
      }, blockedResult: false, fileIds: {file.id});

  Future<void> _move(String source, String destination,
      {bool required = false}) async {
    _check();
    final sourceType = await FileSystemEntity.type(source, followLinks: false);
    final targetType =
        await FileSystemEntity.type(destination, followLinks: false);
    if (sourceType == FileSystemEntityType.notFound) {
      if (required && targetType != FileSystemEntityType.file) {
        throw FileSystemException('Recovery payload is missing', source);
      }
      return;
    }
    if (sourceType != FileSystemEntityType.file ||
        targetType != FileSystemEntityType.notFound) {
      throw FileSystemException(
          'Recovery path collision or invalid payload', source);
    }
    await File(destination).parent.create(recursive: true);
    _check();
    await File(source).rename(destination);
  }

  Future<void> _removeActive(DeletedVaultItem item, bool decoy) async {
    _check();
    await _recordDeletion(item, decoy);
    if (item.auxiliaryKey != null && item.auxiliaryRecord != null) {
      final records = await _auxiliary(item.auxiliaryKey!);
      records.removeWhere((e) => e['id'] == item.auxiliaryRecord!['id']);
      _check();
      await store.write(item.auxiliaryKey!, jsonEncode(records));
    }
    final files = await store.loadFileIndex(isDecoy: decoy);
    files.removeWhere((e) => e.id == item.file.id);
    if (decoy) {
      store.cachedDecoyFiles = files;
    } else {
      store.cachedFiles = files;
    }
    _check();
    await store.saveFileIndex(
        isDecoy: decoy,
        strict: true,
        allowEmpty: true,
        removedIds: {item.file.id});
    if (!decoy) {
      final albums = await store.loadAlbums();
      store.cachedAlbums =
          albums.map((a) => a.removeFile(item.file.id)).toList();
      _check();
      await store.saveAlbums();
      final folders = await store.loadFolders();
      store.cachedFolders =
          folders.map((f) => f.removeFile(item.file.id)).toList();
      _check();
      await store.saveFolders();
    }
  }

  Future<void> _recordDeletion(DeletedVaultItem item, bool decoy) async {
    if (!decoy &&
        !(await SyncStateStore.deletions()).containsKey(item.file.id)) {
      _check();
      await SyncStateStore.recordDeletion(item.file.id);
    }
  }

  Future<void> _finishDelete(DeletedVaultItem item, bool decoy) async {
    await _move(item.file.vaultPath, item.payloadPath);
    if (item.file.thumbnailPath != null && item.thumbnailPath != null) {
      await _move(item.file.thumbnailPath!, item.thumbnailPath!);
    }
    await _removeActive(item, decoy);
    await _put(item.copyWith(stage: DeletionStage.trashed), decoy);
  }

  Future<bool> restore(String id, {bool isDecoy = false}) =>
      _gate.mutate(() async {
        try {
          final item = (await store.loadDeletedItems(isDecoy: isDecoy))
              .where((e) => e.file.id == id)
              .firstOrNull;
          if (item == null || !item.canRestore(clock())) return false;
          if (!await File(item.payloadPath).exists()) return false;
          final root = await _root(isDecoy);
          final token = const Uuid().v4();
          final data = item.file.toJson();
          final basename = item.file.vaultPath.split('/').last;
          final dot = basename.lastIndexOf('.');
          final extension = dot > 0 ? basename.substring(dot) : '';
          data['vaultPath'] =
              '${root.path}/${VaultStore.subdirFor(item.file.type)}'
              '/restored_$token$extension';
          data['thumbnailPath'] = item.thumbnailPath != null &&
                  await File(item.thumbnailPath!).exists()
              ? '${root.path}/thumbnails/restored_$token.thumb'
              : null;
          data['isDecoy'] = isDecoy;
          data['syncedDeleted'] = false;
          data['modifiedAt'] = clock().toUtc().toIso8601String();
          data['metadata'] = {
            ...?item.file.metadata,
            // Explicit restore intent must be reviewable against a remote
            // deletion even when the restored bytes/labels are unchanged.
            'restoredAt': data['modifiedAt'],
          };
          if (!isDecoy) {
            final albums = await store.loadAlbums();
            data['albumIds'] = item.file.albumIds
                .where((id) => albums.any((a) => a.id == id))
                .toList();
            final folders = await store.loadFolders();
            if (!folders.any((f) => f.id == item.file.folderId)) {
              data['folderId'] = null;
            }
          }
          final pending = item.copyWith(
              stage: DeletionStage.restoring,
              restoredFile: VaultedFile.fromJson(data));
          await _put(pending, isDecoy);
          await _finishRestore(pending, isDecoy);
          return true;
        } catch (error) {
          debugPrint('Local restore pending/retry required: $error');
          return false;
        } finally {
          _changed();
        }
      }, blockedResult: false, fileIds: {id});

  Future<void> _finishRestore(DeletedVaultItem item, bool decoy) async {
    final restored = item.restoredFile!;
    await _move(item.payloadPath, restored.vaultPath, required: true);
    if (restored.thumbnailPath != null && item.thumbnailPath != null) {
      await _move(item.thumbnailPath!, restored.thumbnailPath!, required: true);
    }
    if (item.auxiliaryKey != null && item.auxiliaryRecord != null) {
      final records = await _auxiliary(item.auxiliaryKey!);
      final record = Map<String, dynamic>.from(item.auxiliaryRecord!);
      record['encryptedContentPath'] = restored.vaultPath;
      // An editor folder may have been removed while the note was in trash.
      if (record.containsKey('folderId')) {
        final raw =
            await store.read('locker_note_folders${decoy ? '_decoy' : ''}');
        final folders = raw == null ? [] : jsonDecode(raw) as List;
        if (!folders.any((f) => f['id'] == record['folderId'])) {
          record['folderId'] = null;
        }
      }
      records.removeWhere((e) => e['id'] == record['id']);
      records.add(record);
      _check();
      await store.write(item.auxiliaryKey!, jsonEncode(records));
    }
    final files = await store.loadFileIndex(isDecoy: decoy);
    files.removeWhere((f) => f.id == restored.id);
    files.add(restored);
    if (decoy) {
      store.cachedDecoyFiles = files;
    } else {
      store.cachedFiles = files;
    }
    _check();
    await store.saveFileIndex(isDecoy: decoy, strict: true, allowEmpty: true);
    if (!decoy) {
      final albums = await store.loadAlbums();
      _check();
      store.cachedAlbums = albums
          .map((a) =>
              restored.albumIds.contains(a.id) ? a.addFile(restored.id) : a)
          .toList();
      await store.saveAlbums();
      _check();
      final folders = await store.loadFolders();
      _check();
      store.cachedFolders = folders
          .map((f) => f.id == restored.folderId ? f.addFile(restored.id) : f)
          .toList();
      await store.saveFolders();
      _check();
      await SyncStateStore.clearDeletion(restored.id);
    }
    await _forget(item, decoy);
  }

  Future<void> _erase(String path) async {
    _check();
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.file) {
      throw FileSystemException('Invalid permanent deletion payload', path);
    }
    final settings = await store.loadSettings();
    _check();
    if (settings.secureDelete) {
      if (!await encryption.secureDelete(path)) {
        throw FileSystemException('Secure deletion failed', path);
      }
    } else {
      await File(path).delete();
    }
  }

  Future<void> _purge(DeletedVaultItem item, bool decoy) async {
    // Persist non-restorable state BEFORE the first overwrite, even on failure.
    final purging = item.copyWith(stage: DeletionStage.purging);
    await _put(purging, decoy);
    await _removeActive(purging, decoy);
    await _erase(item.payloadPath);
    if (item.thumbnailPath != null) await _erase(item.thumbnailPath!);
    await _forget(item, decoy);
  }

  Future<bool> permanentlyDelete(String id, {bool isDecoy = false}) =>
      _gate.mutate(() async {
        try {
          var item = (await store.loadDeletedItems(isDecoy: isDecoy))
              .where((e) => e.file.id == id)
              .firstOrNull;
          if (item == null || item.stage == DeletionStage.restoring) {
            return false;
          }
          if (item.stage == DeletionStage.deleting) {
            await _finishDelete(item, isDecoy);
          }
          await _purge(item, isDecoy);
          return true;
        } catch (error) {
          debugPrint('Permanent deletion pending/retry required: $error');
          return false;
        } finally {
          _changed();
        }
      }, blockedResult: false, fileIds: {id});

  /// Returns false if another job owns the gate or any receipt needs a retry.
  /// OS background execution is not assumed: run on unlock/resume and expiry.
  Future<bool> maintain({bool isDecoy = false}) => _gate.mutate(() async {
        var succeeded = true;
        final items = await store.loadDeletedItems(isDecoy: isDecoy);
        _gate.reserveFileIds(items.map((item) => item.file.id));
        for (var item in items) {
          try {
            _check();
            if (item.stage == DeletionStage.restoring) {
              await _finishRestore(item, isDecoy);
              continue;
            }
            if (item.stage == DeletionStage.deleting) {
              await _finishDelete(item, isDecoy);
              item = item.copyWith(stage: DeletionStage.trashed);
            }
            if (item.stage == DeletionStage.purging ||
                !clock().isBefore(item.expiresAt)) {
              await _purge(item, isDecoy);
            }
          } catch (error) {
            succeeded = false;
            debugPrint('Recovery maintenance pending/retry required: $error');
          }
        }
        if (items.isNotEmpty) _changed();
        return succeeded;
      }, blockedResult: false);

  Future<int> storageUsed({bool isDecoy = false}) async {
    var bytes = 0;
    for (final item in await store.loadDeletedItems(isDecoy: isDecoy)) {
      final payload = await File(item.payloadPath).exists()
          ? item.payloadPath
          : item.stage == DeletionStage.restoring
              ? item.restoredFile!.vaultPath
              : item.stage == DeletionStage.deleting
                  ? item.file.vaultPath
                  : null;
      if (payload != null) bytes += await store.getFileSizeIfExists(payload);
      final thumbnail =
          item.thumbnailPath != null && await File(item.thumbnailPath!).exists()
              ? item.thumbnailPath
              : item.stage == DeletionStage.restoring
                  ? item.restoredFile?.thumbnailPath
                  : item.stage == DeletionStage.deleting
                      ? item.file.thumbnailPath
                      : null;
      if (thumbnail != null) {
        bytes += await store.getFileSizeIfExists(thumbnail);
      }
    }
    return bytes;
  }
}
