import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';

import '../models/vaulted_file.dart';
import 'encryption_service.dart';
import 'file_service.dart';
import 'vault_store.dart';

class StoredThumb {
  final String path;
  final String iv;
  const StoredThumb(this.path, this.iv);
}

/// Encrypted-thumbnail generation, caching, lazy regen. Splits out of
/// `VaultService`.
///
/// ponytail: depends on FileService for `getVaultedFile` (decrypt-to-temp for
/// regen) and `deriveKeyForFile`. The File↔Thumbnail cycle is broken by a
/// late non-final `fileService` field set after both are constructed —
/// neither reads the other during construction, only at runtime.
class ThumbnailService {
  final VaultStore _store;
  final EncryptionService _encryptionService;
  late FileService fileService;

  ThumbnailService(this._store, this._encryptionService);

  final Map<String, Uint8List> _cache = {};
  final Map<String, Future<Uint8List?>> _inFlight = {};
  static const int _cacheLimit = 200;
  Future<void> _genLock = Future.value();

  Future<Uint8List?> getThumbnailBytes(VaultedFile file) async {
    if (!file.isEncrypted) return null;
    final cached = _cache[file.id];
    if (cached != null) return cached;
    final inFlight = _inFlight[file.id];
    if (inFlight != null) return inFlight;
    final fut = _loadOrRegenerateThumbnail(file);
    _inFlight[file.id] = fut;
    try {
      final bytes = await fut;
      if (bytes != null) _cacheThumbnail(file.id, bytes);
      return bytes;
    } finally {
      _inFlight.remove(file.id);
    }
  }

  void _cacheThumbnail(String id, Uint8List bytes) {
    _cache[id] = bytes;
    if (_cache.length > _cacheLimit) {
      _cache.remove(_cache.keys.first);
    }
  }

  Future<Uint8List?> _loadOrRegenerateThumbnail(VaultedFile file) {
    final prev = _genLock;
    final result = prev.then((_) => _loadOrRegenerateThumbnailLocked(file));
    _genLock = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<Uint8List?> _loadOrRegenerateThumbnailLocked(VaultedFile file) async {
    if (file.thumbnailPath != null && file.thumbnailIv != null) {
      final thumbFile = File(file.thumbnailPath!);
      if (await thumbFile.exists()) {
        final derivedKey = await fileService.deriveKeyForFile(file);
        final res = await _encryptionService.decryptStreamedFileToMemoryGcm(
          file.thumbnailPath!,
          file.thumbnailIv!,
          isDecoy: file.isDecoy,
          derivedKey: derivedKey,
        );
        if (res.success && res.data != null) return res.data;
      }
    }
    return _regenerateThumbnail(file);
  }

  Future<Uint8List?> _regenerateThumbnail(VaultedFile file) async {
    final plaintext = await fileService.getVaultedFile(file.id, isDecoy: file.isDecoy);
    if (plaintext == null) return null;
    try {
      final thumbBytes = await generateThumbBytes(plaintext, file.type);
      if (thumbBytes == null) return null;
      final derivedKey = await fileService.deriveKeyForFile(file);
      if (derivedKey != null) {
        final stored = await encryptAndStoreThumbnail(
          thumbBytes,
          fileId: file.id,
          derivedKey: derivedKey,
          isDecoy: file.isDecoy,
        );
        if (stored != null) {
          await _persistThumbnailRecord(
            file.id,
            stored.path,
            stored.iv,
            isDecoy: file.isDecoy,
          );
        }
      }
      return thumbBytes;
    } finally {
      try {
        if (await plaintext.exists()) await plaintext.delete();
      } catch (_) {}
    }
  }

  Future<Uint8List?> generateThumbBytes(File plaintext, VaultedFileType type) async {
    try {
      if (type == VaultedFileType.video) {
        return await VideoCompress.getByteThumbnail(plaintext.path, quality: 70);
      }
      return await FlutterImageCompress.compressWithFile(
        plaintext.path,
        minWidth: 300,
        minHeight: 300,
        quality: 70,
      );
    } catch (e) {
      debugPrint('[Vault] thumbnail generation failed: $e');
      return null;
    }
  }

  Future<StoredThumb?> encryptAndStoreThumbnail(
    Uint8List thumbBytes, {
    required String fileId,
    required Uint8List derivedKey,
    required bool isDecoy,
  }) async {
    final dir = isDecoy
        ? await _store.ensureDecoyDirectory()
        : await _store.ensureVaultDirectory();
    final thumbPath = '${dir.path}/thumbnails/$fileId.thumb.enc';
    final tempDir = await getTemporaryDirectory();
    final tempPath =
        '${tempDir.path}/lkr_thumb_${DateTime.now().microsecondsSinceEpoch}';
    await File(tempPath).writeAsBytes(thumbBytes);
    try {
      final res = await _encryptionService.encryptFileInIsolate(
        tempPath,
        thumbPath,
        isDecoy: isDecoy,
        useGcm: true,
        derivedKey: derivedKey,
      );
      if (!res.success || res.iv == null) return null;
      return StoredThumb(thumbPath, res.iv!);
    } catch (e) {
      debugPrint('[Vault] thumbnail encrypt failed: $e');
      return null;
    } finally {
      await _store.deleteFileIfExists(tempPath);
    }
  }

  Future<void> _persistThumbnailRecord(
    String fileId,
    String path,
    String iv, {
    required bool isDecoy,
  }) async {
    final files = await _store.loadFileIndex(isDecoy: isDecoy);
    final idx = files.indexWhere((f) => f.id == fileId);
    if (idx == -1) return;
    files[idx] = files[idx].copyWith(thumbnailPath: path, thumbnailIv: iv);
    await _store.saveFileIndex(isDecoy: isDecoy);
  }

  void clearCache() {
    _cache.clear();
    _inFlight.clear();
  }
}