import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/encryption_algorithm.dart';
import '../models/file_to_vault.dart';
import '../models/vaulted_file.dart';
import 'compression_service.dart';
import 'crypto_isolate_pool.dart';
import 'encryption_service.dart';
import 'thumbnail_service.dart';
import 'vault_store.dart';

class FileProgressInfo {
  final int current;
  final int total;
  final String fileName;
  final int fileSize;
  final String status;
  final bool isEncrypting;
  final int encryptedBytes;
  final int totalBytes;

  const FileProgressInfo({
    required this.current,
    required this.total,
    required this.fileName,
    required this.fileSize,
    required this.status,
    this.isEncrypting = false,
    this.encryptedBytes = 0,
    this.totalBytes = 0,
  });
}

class _PreparedVaultAddition {
  final VaultedFile vaultedFile;
  const _PreparedVaultAddition({required this.vaultedFile});
}

class _BatchPreparationResult {
  final int index;
  final FileToVault file;
  final int fileSize;
  final _PreparedVaultAddition? prepared;

  const _BatchPreparationResult({
    required this.index,
    required this.file,
    required this.fileSize,
    required this.prepared,
  });
}

/// File CRUD, import, export, re-encrypt, notes/password registration.
/// Splits out of `VaultService`.
///
/// late back-refs to TagService/AlbumService break cycles; ThumbnailService gets `this`.
class FileService {
  static const int _maxConcurrentBatchAdds = 3;

  final VaultStore _store;
  final EncryptionService _encryptionService;
  final ThumbnailService _thumbnailService;

  FileService(this._store, this._encryptionService, this._thumbnailService);

  /// Late-bound to break a constructor cycle (TagService → FileService →
  /// TagService for tag-usage updates on import).
  late final Future<void> Function(List<String> tags)? updateTagUsage;

  /// Late-bound so `removeFile` can clean album memberships without a
  /// constructor cycle (AlbumService → FileService → AlbumService).
  late final Future<bool> Function(String fileId, String albumId)?
      removeFileFromAlbumFn;

  Future<Uint8List?> deriveKeyForFile(VaultedFile file,
      {bool isDecoy = false}) async {
    if (file.keyDerivationSalt == null || file.kdfIterations == null) {
      return null;
    }
    final masterKey =
        await _encryptionService.getMasterKey(isDecoy: isDecoy || file.isDecoy);
    final salt = base64Decode(file.keyDerivationSalt!);
    return _encryptionService.deriveFileKeyAsync(
        masterKey, salt, file.kdfIterations!);
  }

  Future<VaultedFile?> addFile({
    required String sourcePath,
    required String originalName,
    required VaultedFileType type,
    required String mimeType,
    bool deleteOriginal = false,
    bool encrypt = false,
    bool isDecoy = false,
    List<String>? tags,
    List<String>? albumIds,
    EncryptionAlgorithm? encryptionAlgorithm,
    int? kdfIterations,
  }) async {
    final prepared = await _prepareVaultAddition(
      sourcePath: sourcePath,
      originalName: originalName,
      type: type,
      mimeType: mimeType,
      encrypt: encrypt,
      isDecoy: isDecoy,
      tags: tags,
      albumIds: albumIds,
      encryptionAlgorithm: encryptionAlgorithm,
      kdfIterations: kdfIterations,
    );

    if (prepared == null) return null;

    await _storePreparedVaultAddition(prepared, deleteOriginal: deleteOriginal);

    return prepared.vaultedFile;
  }

  Future<List<VaultedFile>> addFiles({
    required List<FileToVault> files,
    bool deleteOriginals = false,
    bool encrypt = false,
    bool isDecoy = false,
    Function(int current, int total)? onProgress,
    Function(FileProgressInfo)? onFileProgress,
  }) async {
    _store.cachedSettings ??= await _store.loadSettings();
    final results = <VaultedFile>[];

    int completed = 0;

    for (int start = 0; start < files.length; start += _maxConcurrentBatchAdds) {
      final chunk = files
          .sublist(
            start,
            start + _maxConcurrentBatchAdds > files.length
                ? files.length
                : start + _maxConcurrentBatchAdds,
          )
          .asMap()
          .entries
          .map((entry) => (index: start + entry.key, file: entry.value))
          .toList();

      final preparedChunk = await Future.wait(
        chunk.map((entry) async {
          final fileSize = await _store.getFileSizeIfExists(entry.file.sourcePath);
          final fileEncrypt = entry.file.encrypt ?? encrypt;
          final fileShouldEncrypt =
              fileEncrypt || _store.cachedSettings?.encryptionEnabled == true;

          onFileProgress?.call(FileProgressInfo(
            current: entry.index + 1,
            total: files.length,
            fileName: entry.file.originalName,
            fileSize: fileSize,
            status: fileShouldEncrypt ? 'Encrypting 0%...' : 'Processing...',
            isEncrypting: fileShouldEncrypt,
            totalBytes: fileShouldEncrypt ? fileSize : 0,
          ));

          final prepared = await _prepareVaultAddition(
            sourcePath: entry.file.sourcePath,
            originalName: entry.file.originalName,
            type: entry.file.type,
            mimeType: entry.file.mimeType,
            encrypt: fileEncrypt,
            isDecoy: isDecoy,
            encryptionAlgorithm: entry.file.encryptionAlgorithm,
            kdfIterations: entry.file.kdfIterations,
            onEncryptionProgress: fileShouldEncrypt
                ? (processed, total) {
                    final pct = total > 0
                        ? (processed / total * 100).toStringAsFixed(0)
                        : '0';
                    onFileProgress?.call(FileProgressInfo(
                      current: entry.index + 1,
                      total: files.length,
                      fileName: entry.file.originalName,
                      fileSize: fileSize,
                      status: 'Encrypting $pct%...',
                      isEncrypting: true,
                      encryptedBytes: processed,
                      totalBytes: total,
                    ));
                  }
                : null,
          );

          return _BatchPreparationResult(
            index: entry.index,
            file: entry.file,
            fileSize: fileSize,
            prepared: prepared,
          );
        }),
      );

      for (final preparedResult in preparedChunk) {
        if (preparedResult.prepared != null) {
          await _storePreparedVaultAddition(
            preparedResult.prepared!,
            deleteOriginal: deleteOriginals,
          );
          results.add(preparedResult.prepared!.vaultedFile);
        }

        completed++;
        onProgress?.call(completed, files.length);

        onFileProgress?.call(FileProgressInfo(
          current: preparedResult.index + 1,
          total: files.length,
          fileName: preparedResult.file.originalName,
          fileSize: preparedResult.fileSize,
          status: preparedResult.prepared != null ? 'Complete' : 'Failed',
          isEncrypting: false,
        ));
      }
    }

    return results;
  }

  Future<_PreparedVaultAddition?> _prepareVaultAddition({
    required String sourcePath,
    required String originalName,
    required VaultedFileType type,
    required String mimeType,
    required bool encrypt,
    required bool isDecoy,
    Function(int processed, int total)? onEncryptionProgress,
    List<String>? tags,
    List<String>? albumIds,
    EncryptionAlgorithm? encryptionAlgorithm,
    int? kdfIterations,
  }) async {
    String? sourcePathToUse;
    String? vaultPath;
    Uint8List? compressedImageBytes;

    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        debugPrint('Source file does not exist: $sourcePath');
        return null;
      }

      sourcePathToUse = sourcePath;
      _store.cachedSettings ??= await _store.loadSettings();

      if (_store.cachedSettings?.compressionEnabled == true) {
        if (type == VaultedFileType.image) {
          final bytes = await CompressionService.instance
              .compressImageToBytes(sourcePath);
          if (bytes != null) {
            compressedImageBytes = bytes;
            debugPrint(
                '[Vault] Using compressed image bytes (${bytes.length} bytes)');
          }
        } else if (type == VaultedFileType.video) {
          final compressedPath =
              await CompressionService.instance.compressVideo(sourcePath);
          if (compressedPath != null) {
            sourcePathToUse = compressedPath;
            debugPrint('[Vault] Using compressed video: $compressedPath');
          }
        }
      }

      final directory = isDecoy
          ? await _store.ensureDecoyDirectory()
          : await _store.ensureVaultDirectory();

      final vaultFilename = _store.generateVaultFilename(originalName);
      final subdirectory = _store.getSubdirectory(type);
      vaultPath = '${directory.path}/$subdirectory/$vaultFilename';

      final shouldEncrypt = encrypt || _store.cachedSettings?.encryptionEnabled == true;
      String? encryptionIv;
      int fileSize;
      EncryptionAlgorithm? usedAlgorithm;
      String? usedSalt;
      int? usedKdfIterations;

      Uint8List? derivedKey;
      if (shouldEncrypt) {
        final algorithm = encryptionAlgorithm ??
            _store.cachedSettings?.encryptionAlgorithm ??
            EncryptionAlgorithm.aes256Ctr;
        final iterations = kdfIterations ??
            _store.cachedSettings?.kdfIterations ??
            100000;
        final salt = _encryptionService.generateFileSalt();
        final masterKey = await _encryptionService.getMasterKey(isDecoy: isDecoy);
        derivedKey = await _encryptionService.deriveFileKeyAsync(masterKey, salt, iterations);
        usedAlgorithm = algorithm;
        usedSalt = base64Encode(salt);
        usedKdfIterations = iterations;
      }

      if (compressedImageBytes != null) {
        fileSize = compressedImageBytes.length;

        if (shouldEncrypt) {
          onEncryptionProgress?.call(0, fileSize);
          final useGcm = usedAlgorithm == EncryptionAlgorithm.aes256Gcm;

          final tempDir = await getTemporaryDirectory();
          final tempPath =
              '${tempDir.path}/lkr_enc_${DateTime.now().microsecondsSinceEpoch}';
          await File(tempPath).writeAsBytes(compressedImageBytes);

          try {
            final encResult = await _encryptionService.encryptFileInIsolate(
              tempPath,
              vaultPath,
              isDecoy: isDecoy,
              useGcm: useGcm,
              derivedKey: derivedKey,
              onProgress: (processed, total) {
                onEncryptionProgress?.call(processed, total);
              },
            );
            onEncryptionProgress?.call(fileSize, fileSize);

            if (!encResult.success) {
              debugPrint('Encryption failed: ${encResult.error}');
              await _store.deleteFileIfExists(vaultPath);
              return null;
            }

            encryptionIv = encResult.iv;
            fileSize = encResult.originalSize ?? fileSize;
          } finally {
            await _store.deleteFileIfExists(tempPath);
          }
        } else {
          await File(vaultPath).writeAsBytes(compressedImageBytes);
        }
      } else {
        final sourceFileForProcessing = File(sourcePathToUse);
        if (!await sourceFileForProcessing.exists()) {
          debugPrint('Processed file does not exist: $sourcePathToUse');
          return null;
        }

        fileSize = await sourceFileForProcessing.length();

        if (shouldEncrypt) {
          onEncryptionProgress?.call(0, fileSize);
          final useGcm = usedAlgorithm == EncryptionAlgorithm.aes256Gcm;
          final encResult = await _encryptionService.encryptFileInIsolate(
            sourcePathToUse,
            vaultPath,
            isDecoy: isDecoy,
            useGcm: useGcm,
            derivedKey: derivedKey,
            onProgress: (processed, total) {
              onEncryptionProgress?.call(processed, total);
            },
          );
          onEncryptionProgress?.call(fileSize, fileSize);

          if (!encResult.success) {
            debugPrint('Encryption failed: ${encResult.error}');
            await _store.deleteFileIfExists(vaultPath);
            return null;
          }

          encryptionIv = encResult.iv;
          fileSize = encResult.originalSize ?? fileSize;
        } else {
          await _store.streamCopyFile(sourceFileForProcessing, File(vaultPath));
        }
      }

      final normalizedTags = (tags ?? [])
          .map((tag) => tag.toLowerCase().trim())
          .where((tag) => tag.isNotEmpty)
          .toSet()
          .toList();
      final normalizedAlbumIds = (albumIds ?? []).toSet().toList();
      final now = DateTime.now();
      final fileId = sha256
          .convert(utf8.encode('$vaultPath${now.millisecondsSinceEpoch}'))
          .toString()
          .substring(0, 24);

      String? thumbPath;
      String? thumbIv;
      if (shouldEncrypt &&
          derivedKey != null &&
          (type == VaultedFileType.image || type == VaultedFileType.video)) {
        String? reconstructedTemp;
        try {
          File? plainFile;
          if (await File(sourcePathToUse).exists()) {
            plainFile = File(sourcePathToUse);
          } else if (compressedImageBytes != null) {
            final tmp = await getTemporaryDirectory();
            reconstructedTemp =
                '${tmp.path}/lkr_thumb_src_${DateTime.now().microsecondsSinceEpoch}';
            plainFile = File(reconstructedTemp);
            await plainFile.writeAsBytes(compressedImageBytes);
          }
          if (plainFile != null) {
            final thumbBytes = await _thumbnailService.generateThumbBytes(plainFile, type);
            if (thumbBytes != null) {
              final stored = await _thumbnailService.encryptAndStoreThumbnail(
                thumbBytes,
                fileId: fileId,
                derivedKey: derivedKey,
                isDecoy: isDecoy,
              );
              thumbPath = stored?.path;
              thumbIv = stored?.iv;
            }
          }
        } catch (e) {
          debugPrint('[Vault] import-time thumbnail generation failed: $e');
        } finally {
          if (reconstructedTemp != null) {
            await _store.deleteFileIfExists(reconstructedTemp);
          }
        }
      }

      return _PreparedVaultAddition(
        vaultedFile: VaultedFile(
          id: fileId,
          originalName: originalName,
          vaultPath: vaultPath,
          originalPath: sourcePath,
          type: type,
          mimeType: mimeType,
          fileSize: fileSize,
          dateAdded: now,
          isFavorite: normalizedAlbumIds.contains('favorites'),
          isEncrypted: shouldEncrypt,
          encryptionIv: encryptionIv,
          encryptionAlgorithm: usedAlgorithm,
          keyDerivationSalt: usedSalt,
          kdfIterations: usedKdfIterations,
          isDecoy: isDecoy,
          tags: normalizedTags,
          albumIds: normalizedAlbumIds,
          thumbnailPath: thumbPath,
          thumbnailIv: thumbIv,
        ),
      );
    } catch (e) {
      if (vaultPath != null) {
        await _store.deleteFileIfExists(vaultPath);
      }
      debugPrint('Error adding file to vault: $e');
      return null;
    } finally {
      if (sourcePathToUse != null && sourcePathToUse != sourcePath) {
        try {
          await File(sourcePathToUse).delete();
          debugPrint('[Vault] Cleaned up compressed temp file: $sourcePathToUse');
        } catch (e) {
          debugPrint('[Vault] Could not delete temp compressed file: $e');
        }
      }
    }
  }

  Future<void> _storePreparedVaultAddition(
    _PreparedVaultAddition prepared, {
    required bool deleteOriginal,
  }) async {
    final vaultedFile = prepared.vaultedFile;

    if (vaultedFile.isDecoy) {
      _store.cachedDecoyFiles ??= await _store.loadFileIndex(isDecoy: true);
      _store.cachedDecoyFiles!.add(vaultedFile);
      await _store.saveFileIndex(isDecoy: true);
    } else {
      _store.cachedFiles ??= await _store.loadFileIndex();
      _store.cachedFiles!.add(vaultedFile);
      await _store.saveFileIndex();

      if (vaultedFile.albumIds.isNotEmpty) {
        _store.cachedAlbums ??= await _store.loadAlbums();

        for (final albumId in vaultedFile.albumIds) {
          final albumIndex =
              _store.cachedAlbums!.indexWhere((album) => album.id == albumId);
          if (albumIndex != -1) {
            _store.cachedAlbums![albumIndex] =
                _store.cachedAlbums![albumIndex].addFile(vaultedFile.id);
          }
        }

        await _store.saveAlbums();
      }

      if (vaultedFile.tags.isNotEmpty) {
        await updateTagUsage?.call(vaultedFile.tags);
      }
    }

    if (!deleteOriginal || vaultedFile.originalPath == null) {
      return;
    }

    final originalFile = File(vaultedFile.originalPath!);
    bool deleted = false;

    try {
      if (await originalFile.exists()) {
        await originalFile.delete();
        deleted = true;
      } else {
        deleted = true;
      }
    } catch (e) {
      debugPrint('Could not delete original file: $e');
    }

    if (!deleted) {
      try {
        if (await originalFile.exists()) {
          debugPrint(
              'Original file still exists, attempting secure delete: ${vaultedFile.originalPath}');
          if (_store.cachedSettings?.secureDelete == true) {
            await _encryptionService.secureDelete(vaultedFile.originalPath!);
          } else {
            await originalFile.delete();
          }
        }
      } catch (_) {}
    }

    try {
      if (await originalFile.exists()) {
        debugPrint(
            'WARNING: Could not delete original file from device storage: ${vaultedFile.originalPath}');
      }
    } catch (_) {}
  }

  Future<VaultedFile?> updateFile(VaultedFile updatedFile) async {
    try {
      final files = await _store.loadFileIndex(isDecoy: updatedFile.isDecoy);
      final index = files.indexWhere((f) => f.id == updatedFile.id);

      if (index == -1) return null;

      // Mutate the loaded list ref — it IS the cache, so the two can never
      // drift apart if loadFileIndex ever returns a detached copy.
      files[index] = updatedFile;
      await _store.saveFileIndex(isDecoy: updatedFile.isDecoy);

      return updatedFile;
    } catch (e) {
      debugPrint('Error updating file: $e');
      return null;
    }
  }

  Future<bool> removeFile(String fileId, {bool isDecoy = false}) async {
    try {
      final files = await _store.loadFileIndex(isDecoy: isDecoy);
      final fileIndex = files.indexWhere((f) => f.id == fileId);

      if (fileIndex == -1) return false;

      final file = files[fileIndex];

      final vaultFile = File(file.vaultPath);
      if (await vaultFile.exists()) {
        if (_store.cachedSettings?.secureDelete == true) {
          await _encryptionService.secureDelete(file.vaultPath);
        } else {
          await vaultFile.delete();
        }
      }

      if (file.thumbnailPath != null) {
        final thumbFile = File(file.thumbnailPath!);
        if (await thumbFile.exists()) {
          await thumbFile.delete();
        }
      }

      if (!isDecoy && file.albumIds.isNotEmpty) {
        for (final albumId in file.albumIds) {
          await removeFileFromAlbumFn?.call(fileId, albumId);
        }
      }

      if (!isDecoy && file.folderId != null) {
        _store.cachedFolders ??= await _store.loadFolders();
        final folderIndex =
            _store.cachedFolders!.indexWhere((f) => f.id == file.folderId);
        if (folderIndex != -1) {
          _store.cachedFolders![folderIndex] =
              _store.cachedFolders![folderIndex].removeFile(fileId);
          await _store.saveFolders();
        }
      }

      if (isDecoy) {
        _store.cachedDecoyFiles!.removeAt(fileIndex);
        await _store.saveFileIndex(isDecoy: true);
      } else {
        _store.cachedFiles!.removeAt(fileIndex);
        await _store.saveFileIndex();
      }

      return true;
    } catch (e) {
      debugPrint('Error removing file from vault: $e');
      return false;
    }
  }

  Future<int> removeFiles(
    List<String> fileIds, {
    bool isDecoy = false,
    void Function(int current, int total, {int currentSize, int totalSize})?
        onProgress,
  }) async {
    final fileIndex = await _store.loadFileIndex(isDecoy: isDecoy);
    final idSet = fileIds.toSet();
    final filesToDelete = fileIndex.where((f) => idSet.contains(f.id)).toList();
    final totalSize = filesToDelete.fold<int>(0, (s, f) => s + f.fileSize);

    final albumUpdates = <String, Set<String>>{};
    final folderUpdates = <String, Set<String>>{};
    int removed = 0;
    int currentSize = 0;

    for (final file in filesToDelete) {
      try {
        final vaultFile = File(file.vaultPath);
        if (await vaultFile.exists()) {
          if (_store.cachedSettings?.secureDelete == true) {
            await _encryptionService.secureDelete(file.vaultPath);
          } else {
            await vaultFile.delete();
          }
        }

        if (file.thumbnailPath != null) {
          final thumbFile = File(file.thumbnailPath!);
          if (await thumbFile.exists()) {
            await thumbFile.delete();
          }
        }

        if (!isDecoy && file.albumIds.isNotEmpty) {
          for (final albumId in file.albumIds) {
            albumUpdates.putIfAbsent(albumId, () => {}).add(file.id);
          }
        }

        if (!isDecoy && file.folderId != null) {
          folderUpdates.putIfAbsent(file.folderId!, () => {}).add(file.id);
        }

        removed++;
        currentSize += file.fileSize;
        onProgress?.call(removed, fileIds.length,
            currentSize: currentSize, totalSize: totalSize);
      } catch (e) {
        debugPrint('Error deleting file ${file.id}: $e');
      }
    }

    if (!isDecoy && albumUpdates.isNotEmpty) {
      final albums = await _store.loadAlbums();
      bool albumsChanged = false;
      for (final entry in albumUpdates.entries) {
        final albumIdx = albums.indexWhere((a) => a.id == entry.key);
        if (albumIdx != -1) {
          var album = albums[albumIdx];
          for (final fid in entry.value) {
            album = album.removeFile(fid);
          }
          albums[albumIdx] = album;
          albumsChanged = true;
        }
      }
      if (albumsChanged) await _store.saveAlbums();
    }

    if (!isDecoy && folderUpdates.isNotEmpty) {
      _store.cachedFolders ??= await _store.loadFolders();
      bool foldersChanged = false;
      for (final entry in folderUpdates.entries) {
        final folderIdx = _store.cachedFolders!.indexWhere((f) => f.id == entry.key);
        if (folderIdx != -1) {
          var folder = _store.cachedFolders![folderIdx];
          for (final fid in entry.value) {
            folder = folder.removeFile(fid);
          }
          _store.cachedFolders![folderIdx] = folder;
          foldersChanged = true;
        }
      }
      if (foldersChanged) await _store.saveFolders();
    }

    final deleteIdSet = filesToDelete.map((f) => f.id).toSet();
    if (isDecoy) {
      _store.cachedDecoyFiles!.removeWhere((f) => deleteIdSet.contains(f.id));
      await _store.saveFileIndex(isDecoy: true);
    } else {
      _store.cachedFiles!.removeWhere((f) => deleteIdSet.contains(f.id));
      await _store.saveFileIndex();
    }

    return removed;
  }

  Future<List<VaultedFile>> getAllFiles({bool isDecoy = false}) async {
    return await _store.loadFileIndex(isDecoy: isDecoy);
  }

  Future<List<VaultedFile>> getFilesByType(VaultedFileType type,
      {bool isDecoy = false}) async {
    final files = await _store.loadFileIndex(isDecoy: isDecoy);
    return files.where((f) => f.type == type).toList();
  }

  Future<VaultedFile?> getFileById(String fileId, {bool isDecoy = false}) async {
    final files = await _store.loadFileIndex(isDecoy: isDecoy);
    try {
      return files.firstWhere((f) => f.id == fileId);
    } catch (e) {
      return null;
    }
  }

  /// Get the actual file from vault (decrypts if needed).
  Future<File?> getVaultedFile(
    String fileId, {
    bool isDecoy = false,
    Function(int processed, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final vaultedFile = await getFileById(fileId, isDecoy: isDecoy);
    if (vaultedFile == null) return null;

    final file = File(vaultedFile.vaultPath);
    if (!await file.exists()) return null;

    if (vaultedFile.isEncrypted && vaultedFile.encryptionIv != null) {
      final tempDir = await _store.ensureVaultDirectory();
      final tempPath = '${tempDir.path}/temp/${vaultedFile.id}_${vaultedFile.originalName}';

      final format = _encryptionService.detectFileFormat(vaultedFile.vaultPath);
      final isLegacyCbc = (format == 0 || format == 3);
      final derivedKey = await deriveKeyForFile(vaultedFile, isDecoy: isDecoy);

      if (cancelToken?.isCancelled == true) return null;

      FileDecryptionResult result;
      if (isLegacyCbc) {
        result = await _encryptionService.decryptFile(
          vaultedFile.vaultPath,
          tempPath,
          vaultedFile.encryptionIv!,
          isDecoy: isDecoy,
          derivedKey: derivedKey,
          onProgress: onProgress == null
              ? null
              : (current, total) {
                  final estimatedProcessed = total > 0
                      ? (current / total * vaultedFile.fileSize).round()
                      : 0;
                  onProgress(estimatedProcessed, vaultedFile.fileSize);
                },
        );
      } else {
        result = await _encryptionService.decryptFileInIsolate(
          vaultedFile.vaultPath,
          tempPath,
          vaultedFile.encryptionIv!,
          isDecoy: isDecoy,
          derivedKey: derivedKey,
          onProgress: onProgress,
          cancelToken: cancelToken,
        );
      }

      if (cancelToken?.isCancelled == true) return null;

      if (result.success && result.decryptedPath != null) {
        return File(result.decryptedPath!);
      }
      return null;
    }

    return file;
  }

  Future<Uint8List?> getDecryptedFileData(String fileId,
      {bool isDecoy = false}) async {
    final vaultedFile = await getFileById(fileId, isDecoy: isDecoy);
    if (vaultedFile == null) return null;

    if (vaultedFile.isEncrypted && vaultedFile.encryptionIv != null) {
      final derivedKey = await deriveKeyForFile(vaultedFile, isDecoy: isDecoy);
      final result = await _encryptionService.decryptStreamedFileToMemory(
        vaultedFile.vaultPath,
        vaultedFile.encryptionIv!,
        isDecoy: isDecoy,
        derivedKey: derivedKey,
      );

      if (result.success && result.data != null) {
        await updateFile(vaultedFile.markViewed());
        return result.data;
      }
      return null;
    }

    final file = File(vaultedFile.vaultPath);
    if (!await file.exists()) return null;

    await updateFile(vaultedFile.markViewed());
    return await file.readAsBytes();
  }

  Future<File?> exportFile(
    String fileId,
    String destinationPath, {
    bool isDecoy = false,
    Function(int processed, int total)? onProgress,
  }) async {
    try {
      final vaultedFile = await getFileById(fileId, isDecoy: isDecoy);
      if (vaultedFile == null) return null;

      final sourceFile = File(vaultedFile.vaultPath);
      if (!await sourceFile.exists()) return null;

      if (vaultedFile.isEncrypted && vaultedFile.encryptionIv != null) {
        final format = _encryptionService.detectFileFormat(vaultedFile.vaultPath);
        final isLegacyCbc = (format == 0 || format == 3);
        final derivedKey = await deriveKeyForFile(vaultedFile, isDecoy: isDecoy);

        FileDecryptionResult result;
        if (isLegacyCbc) {
          result = await _encryptionService.decryptFile(
            vaultedFile.vaultPath,
            destinationPath,
            vaultedFile.encryptionIv!,
            derivedKey: derivedKey,
            onProgress: onProgress == null
                ? null
                : (current, total) {
                    final estimatedProcessed = total > 0
                        ? (current / total * vaultedFile.fileSize).round()
                        : 0;
                    onProgress(estimatedProcessed, vaultedFile.fileSize);
                  },
          );
        } else {
          result = await _encryptionService.decryptFileInIsolate(
            vaultedFile.vaultPath,
            destinationPath,
            vaultedFile.encryptionIv!,
            isDecoy: isDecoy,
            derivedKey: derivedKey,
            onProgress: onProgress == null
                ? null
                : (bytesProcessed, totalBytes) {
                    onProgress(bytesProcessed, totalBytes);
                  },
          );
        }

        if (result.success && result.decryptedPath != null) {
          return File(result.decryptedPath!);
        }
        return null;
      }

      await _store.streamCopyFile(sourceFile, File(destinationPath),
          onProgress: onProgress);
      return File(destinationPath);
    } catch (e) {
      debugPrint('Error exporting file: $e');
      return null;
    }
  }

  Future<int> reEncryptVault(
    EncryptionAlgorithm targetAlgorithm, {
    bool isDecoy = false,
    Function(int current, int total, String currentFileName, int processedBytes,
            int totalBytes)?
        onProgress,
    Set<String>? fileFilter,
  }) async {
    try {
      final files = isDecoy
          ? (await getAllFiles(isDecoy: true))
          : (await getAllFiles(isDecoy: false));
      var encryptedFiles = files.where((f) => f.isEncrypted).toList();

      if (fileFilter != null && fileFilter.isNotEmpty) {
        encryptedFiles =
            encryptedFiles.where((f) => fileFilter.contains(f.id)).toList();
      }

      if (encryptedFiles.isEmpty) return 0;

      final journalIvs = <String, String>{};
      String? priorInProgress;

      final journalStr = await _store.read(VaultStore.reEncryptJournalKey);
      if (journalStr != null) {
        try {
          final journal = jsonDecode(journalStr) as Map<String, dynamic>;
          final savedIvs =
              (journal['ivs'] as Map<String, dynamic>?)?.cast<String, String>() ?? {};
          journalIvs.addAll(savedIvs);
          priorInProgress = journal['inProgress'] as String?;

          for (final entry in journalIvs.entries) {
            final idx = files.indexWhere((f) => f.vaultPath == entry.key);
            if (idx >= 0) {
              files[idx] = files[idx].copyWith(encryptionIv: entry.value);
            }
          }

          if (priorInProgress != null) {
            try {
              await File('$priorInProgress.tmp').delete();
            } catch (_) {}
          }

          encryptedFiles = files.where((f) => f.isEncrypted).toList();
          if (fileFilter != null && fileFilter.isNotEmpty) {
            encryptedFiles =
                encryptedFiles.where((f) => fileFilter.contains(f.id)).toList();
          }

          if (isDecoy) {
            _store.cachedDecoyFiles = files;
          } else {
            _store.cachedFiles = files;
          }
          await _store.saveFileIndex(isDecoy: isDecoy);
        } catch (_) {}
      }

      final totalBytes = encryptedFiles.fold<int>(0, (s, f) => s + f.fileSize);
      var processedBytes = 0;
      int reEncryptedCount = 0;

      for (int i = 0; i < encryptedFiles.length; i++) {
        final file = encryptedFiles[i];
        onProgress?.call(i, encryptedFiles.length, file.originalName,
            processedBytes, totalBytes);

        if (!await File(file.vaultPath).exists()) {
          processedBytes += file.fileSize;
          onProgress?.call(i + 1, encryptedFiles.length, file.originalName,
              processedBytes, totalBytes);
          continue;
        }
        if (file.encryptionIv == null || file.encryptionIv!.isEmpty) {
          debugPrint(
              'reEncryptVault: skipping ${file.originalName} (missing IV)');
          processedBytes += file.fileSize;
          onProgress?.call(i + 1, encryptedFiles.length, file.originalName,
              processedBytes, totalBytes);
          continue;
        }

        final currentFormat = _encryptionService.detectFileFormat(file.vaultPath);
        final targetIsGcm = targetAlgorithm == EncryptionAlgorithm.aes256Gcm;
        final currentIsGcm = (currentFormat == 1 || currentFormat == 4);

        if (currentIsGcm == targetIsGcm && currentFormat != 0 && currentFormat != 3) {
          processedBytes += file.fileSize;
          onProgress?.call(i + 1, encryptedFiles.length, file.originalName,
              processedBytes, totalBytes);
          continue;
        }

        await _store.write(
          VaultStore.reEncryptJournalKey,
          jsonEncode({
            'ivs': journalIvs,
            'inProgress': file.vaultPath,
          }),
        );

        final oldDerivedKey = await deriveKeyForFile(file, isDecoy: isDecoy);
        final newSalt = _encryptionService.generateFileSalt();
        final newIterations = _store.cachedSettings?.kdfIterations ?? 100000;
        final masterKey =
            await _encryptionService.getMasterKey(isDecoy: isDecoy || file.isDecoy);
        final newDerivedKey = await _encryptionService.deriveFileKeyAsync(
            masterKey, newSalt, newIterations);

        final baseBytes = processedBytes;
        final halfBytes = file.fileSize ~/ 2;
        final newIv = await _encryptionService.reEncryptFile(
          file.vaultPath,
          file.encryptionIv ?? '',
          targetAlgorithm: targetAlgorithm,
          isDecoy: isDecoy,
          oldDerivedKey: oldDerivedKey,
          newDerivedKey: newDerivedKey,
          onProgress: onProgress == null
              ? null
              : (processed, _, isEnc) => onProgress(
                    i,
                    encryptedFiles.length,
                    file.originalName,
                    baseBytes +
                        (isEnc
                            ? halfBytes + (processed ~/ 2)
                            : processed ~/ 2),
                    totalBytes),
        );

        journalIvs[file.vaultPath] = newIv;
        await _store.write(
          VaultStore.reEncryptJournalKey,
          jsonEncode({
            'ivs': journalIvs,
          }),
        );

        final fileIndex = files.indexWhere((f) => f.id == file.id);
        if (fileIndex >= 0) {
          if (file.thumbnailPath != null) {
            try {
              await File(file.thumbnailPath!).delete();
            } catch (_) {}
          }
          files[fileIndex] = file.copyWith(
            encryptionIv: newIv,
            encryptionAlgorithm: targetAlgorithm,
            keyDerivationSalt: base64Encode(newSalt),
            kdfIterations: newIterations,
          );
          reEncryptedCount++;
        }
        processedBytes += file.fileSize;
        onProgress?.call(i + 1, encryptedFiles.length, file.originalName,
            processedBytes, totalBytes);
      }

      if (isDecoy) {
        _store.cachedDecoyFiles = files;
      } else {
        _store.cachedFiles = files;
      }

      await _store.saveFileIndex(isDecoy: isDecoy);
      await _store.delete(VaultStore.reEncryptJournalKey);
      return reEncryptedCount;
    } catch (e) {
      debugPrint('Re-encryption error: $e');
      return -1;
    }
  }

  Future<int> encryptVaultFiles(
    EncryptionAlgorithm algorithm, {
    bool isDecoy = false,
    Function(int current, int total, String currentFileName, int processedBytes,
            int totalBytes)?
        onProgress,
    Set<String>? fileFilter,
  }) async {
    try {
      final files = await getAllFiles(isDecoy: isDecoy);
      var targets = files.where((f) => !f.isEncrypted).toList();
      if (fileFilter != null && fileFilter.isNotEmpty) {
        targets = targets.where((f) => fileFilter.contains(f.id)).toList();
      }
      if (targets.isEmpty) return 0;

      final iterations = _store.cachedSettings?.kdfIterations ?? 100000;
      final totalBytes = targets.fold<int>(0, (s, f) => s + f.fileSize);
      var processedBytes = 0;
      var count = 0;

      for (int i = 0; i < targets.length; i++) {
        final file = targets[i];
        onProgress?.call(
            i, targets.length, file.originalName, processedBytes, totalBytes);
        if (!await File(file.vaultPath).exists()) {
          processedBytes += file.fileSize;
          continue;
        }

        final salt = _encryptionService.generateFileSalt();
        final masterKey =
            await _encryptionService.getMasterKey(isDecoy: isDecoy || file.isDecoy);
        final derivedKey =
            await _encryptionService.deriveFileKeyAsync(masterKey, salt, iterations);

        final baseBytes = processedBytes;
        final newIv = await _encryptionService.encryptFileInPlace(
          file.vaultPath,
          useGcm: algorithm == EncryptionAlgorithm.aes256Gcm,
          isDecoy: isDecoy,
          derivedKey: derivedKey,
          onProgress: onProgress == null
              ? null
              : (processed, _) => onProgress(i, targets.length,
                  file.originalName, baseBytes + processed, totalBytes),
        );

        final idx = files.indexWhere((f) => f.id == file.id);
        if (idx >= 0) {
          files[idx] = file.copyWith(
            isEncrypted: true,
            encryptionIv: newIv,
            encryptionAlgorithm: algorithm,
            keyDerivationSalt: base64Encode(salt),
            kdfIterations: iterations,
          );
          count++;
        }
        processedBytes += file.fileSize;
        onProgress?.call(
            i + 1, targets.length, file.originalName, processedBytes, totalBytes);
      }

      await _store.saveFileIndex(isDecoy: isDecoy);
      return count;
    } catch (e) {
      try {
        await _store.saveFileIndex(isDecoy: isDecoy);
      } catch (_) {}
      debugPrint('Encrypt-in-place error: $e');
      return -1;
    }
  }

  Future<int> removeEncryption({
    bool isDecoy = false,
    Function(int current, int total, String currentFileName, int processedBytes,
            int totalBytes)?
        onProgress,
    Set<String>? fileFilter,
  }) async {
    try {
      final files = await getAllFiles(isDecoy: isDecoy);
      var targets = files.where((f) => f.isEncrypted).toList();
      if (fileFilter != null && fileFilter.isNotEmpty) {
        targets = targets.where((f) => fileFilter.contains(f.id)).toList();
      }
      if (targets.isEmpty) return 0;

      final totalBytes = targets.fold<int>(0, (s, f) => s + f.fileSize);
      var processedBytes = 0;
      var count = 0;

      for (int i = 0; i < targets.length; i++) {
        final file = targets[i];
        onProgress?.call(
            i, targets.length, file.originalName, processedBytes, totalBytes);
        if (!await File(file.vaultPath).exists()) {
          processedBytes += file.fileSize;
          continue;
        }
        if (file.encryptionIv == null) {
          processedBytes += file.fileSize;
          continue;
        }

        final derivedKey = await deriveKeyForFile(file, isDecoy: isDecoy);

        final baseBytes = processedBytes;
        await _encryptionService.decryptFileInPlace(
          file.vaultPath,
          file.encryptionIv!,
          isDecoy: isDecoy,
          derivedKey: derivedKey,
          onProgress: onProgress == null
              ? null
              : (processed, _) => onProgress(i, targets.length,
                  file.originalName, baseBytes + processed, totalBytes),
        );

        final idx = files.indexWhere((f) => f.id == file.id);
        if (idx >= 0) {
          if (file.thumbnailPath != null) {
            try {
              await File(file.thumbnailPath!).delete();
            } catch (_) {}
          }
          files[idx] = VaultedFile(
            id: file.id,
            originalName: file.originalName,
            vaultPath: file.vaultPath,
            originalPath: file.originalPath,
            type: file.type,
            mimeType: file.mimeType,
            fileSize: file.fileSize,
            dateAdded: file.dateAdded,
            dateModified: DateTime.now(),
            metadata: file.metadata,
            tags: file.tags,
            isFavorite: file.isFavorite,
            isEncrypted: false,
            isDecoy: file.isDecoy,
            lastViewed: file.lastViewed,
            viewCount: file.viewCount,
            notes: file.notes,
            albumIds: file.albumIds,
            folderId: file.folderId,
          );
          count++;
        }
        processedBytes += file.fileSize;
        onProgress?.call(
            i + 1, targets.length, file.originalName, processedBytes, totalBytes);
      }

      await _store.saveFileIndex(isDecoy: isDecoy);
      return count;
    } catch (e) {
      try {
        await _store.saveFileIndex(isDecoy: isDecoy);
      } catch (_) {}
      debugPrint('Remove-encryption error: $e');
      return -1;
    }
  }

  Future<void> cleanupTemp() async {
    try {
      final vaultDir = await _store.ensureVaultDirectory();
      final tempDir = Directory('${vaultDir.path}/temp');

      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
        await tempDir.create();
      }
    } catch (e) {
      debugPrint('Error cleaning temp: $e');
    }
  }

  // ---- Notes / password registration ----

  Future<void> registerNoteEntry({
    required String noteId,
    required String title,
    required String encryptedContentPath,
    String fileExtension = 'txt',
    bool isEncrypted = false,
    EncryptionAlgorithm encryptionAlgorithm = EncryptionAlgorithm.aes256Gcm,
    int kdfIterations = 0,
    String? folderId,
    bool isDecoy = false,
  }) async {
    final files = isDecoy
        ? (_store.cachedDecoyFiles ??= await _store.loadFileIndex(isDecoy: true))
        : (_store.cachedFiles ??= await _store.loadFileIndex());

    final existingIndex = files.indexWhere((f) => f.metadata?['noteId'] == noteId);

    final mimeType = switch (fileExtension) {
      'md' => 'text/markdown',
      'html' => 'text/html',
      _ => 'text/plain',
    };

    final entry = VaultedFile(
      id: existingIndex != -1 ? files[existingIndex].id : noteId,
      originalName: '$title.$fileExtension',
      vaultPath: encryptedContentPath,
      type: VaultedFileType.document,
      mimeType: mimeType,
      fileSize: 0,
      dateAdded:
          existingIndex != -1 ? files[existingIndex].dateAdded : DateTime.now(),
      dateModified: DateTime.now(),
      tags: ['note'],
      isEncrypted: isEncrypted,
      encryptionAlgorithm: encryptionAlgorithm,
      kdfIterations: kdfIterations,
      folderId: folderId,
      metadata: {'noteId': noteId},
    );

    if (existingIndex != -1) {
      files[existingIndex] = entry;
    } else {
      files.insert(0, entry);
    }

    if (isDecoy) {
      await _store.saveFileIndex(isDecoy: true);
    } else {
      await _store.saveFileIndex();
    }
  }

  Future<void> removeNoteEntry(String noteId, {bool isDecoy = false}) async {
    final files = isDecoy
        ? (_store.cachedDecoyFiles ??= await _store.loadFileIndex(isDecoy: true))
        : (_store.cachedFiles ??= await _store.loadFileIndex());

    files.removeWhere((f) => f.metadata?['noteId'] == noteId);

    if (isDecoy) {
      await _store.saveFileIndex(isDecoy: true);
    } else {
      await _store.saveFileIndex();
    }
  }

  Future<void> registerPasswordEntry({
    required String passwordId,
    required String title,
    required String encryptedContentPath,
    List<String> tags = const [],
    bool isEncrypted = false,
    EncryptionAlgorithm encryptionAlgorithm = EncryptionAlgorithm.aes256Gcm,
    int kdfIterations = 0,
    bool isDecoy = false,
  }) async {
    final files = isDecoy
        ? (_store.cachedDecoyFiles ??= await _store.loadFileIndex(isDecoy: true))
        : (_store.cachedFiles ??= await _store.loadFileIndex());

    final existingIndex =
        files.indexWhere((f) => f.metadata?['passwordId'] == passwordId);

    final entry = VaultedFile(
      id: existingIndex != -1 ? files[existingIndex].id : passwordId,
      originalName: '$title.pwd',
      vaultPath: encryptedContentPath,
      type: VaultedFileType.document,
      mimeType: 'application/octet-stream',
      fileSize: 0,
      dateAdded:
          existingIndex != -1 ? files[existingIndex].dateAdded : DateTime.now(),
      dateModified: DateTime.now(),
      tags: ['password', ...tags],
      isEncrypted: isEncrypted,
      encryptionAlgorithm: encryptionAlgorithm,
      kdfIterations: kdfIterations,
      metadata: {'passwordId': passwordId},
    );

    if (existingIndex != -1) {
      files[existingIndex] = entry;
    } else {
      files.insert(0, entry);
    }

    if (isDecoy) {
      await _store.saveFileIndex(isDecoy: true);
    } else {
      await _store.saveFileIndex();
    }
  }

  Future<void> removePasswordEntry(String passwordId, {bool isDecoy = false}) async {
    final files = isDecoy
        ? (_store.cachedDecoyFiles ??= await _store.loadFileIndex(isDecoy: true))
        : (_store.cachedFiles ??= await _store.loadFileIndex());

    files.removeWhere((f) => f.metadata?['passwordId'] == passwordId);

    if (isDecoy) {
      await _store.saveFileIndex(isDecoy: true);
    } else {
      await _store.saveFileIndex();
    }
  }
}