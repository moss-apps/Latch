import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import '../models/vaulted_file.dart';
import '../models/album.dart';
import '../models/encryption_algorithm.dart';
import 'encryption_service.dart';
import 'compression_service.dart';

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

/// Service for managing vaulted files storage
class VaultService {
  VaultService._();
  static final VaultService instance = VaultService._();

  static const int _largeFileIsolateThresholdBytes = 5 * 1024 * 1024;
  static const int _maxConcurrentBatchAdds = 3;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const String _vaultIndexKey = 'vault_file_index';
  static const String _decoyIndexKey = 'vault_decoy_index';
  static const String _albumsKey = 'vault_albums';
  static const String _tagsKey = 'vault_tags';
  static const String _settingsKey = 'vault_settings';
  static const String _vaultFolderName = '.locker_vault';
  static const String _decoyFolderName = '.locker_decoy';

  final EncryptionService _encryptionService = EncryptionService.instance;

  Directory? _vaultDirectory;
  Directory? _decoyDirectory;
  List<VaultedFile>? _cachedFiles;
  List<VaultedFile>? _cachedDecoyFiles;
  List<Album>? _cachedAlbums;
  List<TagInfo>? _cachedTags;
  VaultSettings? _cachedSettings;

  /// Initialize the vault service
  Future<void> initialize() async {
    await _encryptionService.initialize();
    await _ensureVaultDirectory();
    await _loadFileIndex();
    await _loadAlbums();
    await _loadTags();
    await _loadSettings();
  }

  /// Get the vault directory
  Future<Directory> _ensureVaultDirectory() async {
    if (_vaultDirectory != null && await _vaultDirectory!.exists()) {
      await _ensureNoMediaFile(_vaultDirectory!.path);
      return _vaultDirectory!;
    }

    final appDir = await getApplicationDocumentsDirectory();
    _vaultDirectory = Directory('${appDir.path}/$_vaultFolderName');

    if (!await _vaultDirectory!.exists()) {
      await _vaultDirectory!.create(recursive: true);
    }

    // Create subdirectories for different file types
    await Directory('${_vaultDirectory!.path}/images').create(recursive: true);
    await Directory('${_vaultDirectory!.path}/videos').create(recursive: true);
    await Directory('${_vaultDirectory!.path}/songs').create(recursive: true);
    await Directory('${_vaultDirectory!.path}/documents')
        .create(recursive: true);
    await Directory('${_vaultDirectory!.path}/thumbnails')
        .create(recursive: true);
    await Directory('${_vaultDirectory!.path}/temp').create(recursive: true);

    // Prevent system gallery/media scanner from indexing vault contents
    await _ensureNoMediaFile(_vaultDirectory!.path);

    return _vaultDirectory!;
  }

  /// Get the decoy directory
  Future<Directory> _ensureDecoyDirectory() async {
    if (_decoyDirectory != null && await _decoyDirectory!.exists()) {
      await _ensureNoMediaFile(_decoyDirectory!.path);
      return _decoyDirectory!;
    }

    final appDir = await getApplicationDocumentsDirectory();
    _decoyDirectory = Directory('${appDir.path}/$_decoyFolderName');

    if (!await _decoyDirectory!.exists()) {
      await _decoyDirectory!.create(recursive: true);
    }

    await Directory('${_decoyDirectory!.path}/images').create(recursive: true);
    await Directory('${_decoyDirectory!.path}/videos').create(recursive: true);
    await Directory('${_decoyDirectory!.path}/songs').create(recursive: true);
    await Directory('${_decoyDirectory!.path}/documents')
        .create(recursive: true);

    // Prevent media scanner from indexing decoy vault
    await _ensureNoMediaFile(_decoyDirectory!.path);

    return _decoyDirectory!;
  }

  /// Ensure a .nomedia marker exists to hide from gallery/media scanners
  Future<void> _ensureNoMediaFile(String directoryPath) async {
    final noMediaFile = File('$directoryPath/.nomedia');
    if (!await noMediaFile.exists()) {
      await noMediaFile.create();
    }
  }

  /// Get subdirectory path for file type
  String _getSubdirectory(VaultedFileType type) {
    switch (type) {
      case VaultedFileType.image:
        return 'images';
      case VaultedFileType.video:
        return 'videos';
      case VaultedFileType.song:
        return 'songs';
      case VaultedFileType.document:
      case VaultedFileType.other:
        return 'documents';
    }
  }

  /// Load file index from secure storage
  Future<List<VaultedFile>> _loadFileIndex({bool isDecoy = false}) async {
    if (!isDecoy && _cachedFiles != null) return _cachedFiles!;
    if (isDecoy && _cachedDecoyFiles != null) return _cachedDecoyFiles!;

    try {
      final key = isDecoy ? _decoyIndexKey : _vaultIndexKey;
      final indexJson = await _storage.read(key: key);
      if (indexJson == null || indexJson.isEmpty) {
        if (isDecoy) {
          _cachedDecoyFiles = [];
          return _cachedDecoyFiles!;
        }
        _cachedFiles = [];
        return _cachedFiles!;
      }

      final List<dynamic> jsonList = jsonDecode(indexJson);
      final files = jsonList
          .map((json) => VaultedFile.fromJson(json as Map<String, dynamic>))
          .toList();

      if (isDecoy) {
        _cachedDecoyFiles = files;
        return _cachedDecoyFiles!;
      }
      _cachedFiles = files;
      return _cachedFiles!;
    } catch (e) {
      debugPrint('Error loading vault index: $e');
      if (isDecoy) {
        _cachedDecoyFiles = [];
        return _cachedDecoyFiles!;
      }
      _cachedFiles = [];
      return _cachedFiles!;
    }
  }

  /// Save file index to secure storage
  Future<void> _saveFileIndex({bool isDecoy = false}) async {
    try {
      final files = isDecoy ? _cachedDecoyFiles : _cachedFiles;
      final key = isDecoy ? _decoyIndexKey : _vaultIndexKey;
      final jsonList = files?.map((file) => file.toJson()).toList() ?? [];
      await _storage.write(key: key, value: jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error saving vault index: $e');
    }
  }

  /// Load albums from secure storage
  Future<List<Album>> _loadAlbums() async {
    if (_cachedAlbums != null) return _cachedAlbums!;

    try {
      final albumsJson = await _storage.read(key: _albumsKey);
      if (albumsJson == null || albumsJson.isEmpty) {
        _cachedAlbums = _createDefaultAlbums();
        await _saveAlbums();
        return _cachedAlbums!;
      }

      final List<dynamic> jsonList = jsonDecode(albumsJson);
      _cachedAlbums = jsonList
          .map((json) => Album.fromJson(json as Map<String, dynamic>))
          .toList();

      return _cachedAlbums!;
    } catch (e) {
      debugPrint('Error loading albums: $e');
      _cachedAlbums = _createDefaultAlbums();
      return _cachedAlbums!;
    }
  }

  /// Create default albums
  List<Album> _createDefaultAlbums() {
    final now = DateTime.now();
    return [
      Album(
        id: 'favorites',
        name: 'Favorites',
        createdAt: now,
        updatedAt: now,
        isDefault: true,
        type: AlbumType.favorites,
        sortOrder: 0,
      ),
      Album(
        id: 'recent',
        name: 'Recent',
        createdAt: now,
        updatedAt: now,
        isDefault: true,
        type: AlbumType.recent,
        sortOrder: 1,
      ),
    ];
  }

  /// Save albums to secure storage
  Future<void> _saveAlbums() async {
    try {
      final jsonList = _cachedAlbums?.map((a) => a.toJson()).toList() ?? [];
      await _storage.write(key: _albumsKey, value: jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error saving albums: $e');
    }
  }

  /// Load tags from secure storage
  Future<List<TagInfo>> _loadTags() async {
    if (_cachedTags != null) return _cachedTags!;

    try {
      final tagsJson = await _storage.read(key: _tagsKey);
      if (tagsJson == null || tagsJson.isEmpty) {
        _cachedTags = [];
        return _cachedTags!;
      }

      final List<dynamic> jsonList = jsonDecode(tagsJson);
      _cachedTags = jsonList
          .map((json) => TagInfo.fromJson(json as Map<String, dynamic>))
          .toList();

      return _cachedTags!;
    } catch (e) {
      debugPrint('Error loading tags: $e');
      _cachedTags = [];
      return _cachedTags!;
    }
  }

  /// Save tags to secure storage
  Future<void> _saveTags() async {
    try {
      final jsonList = _cachedTags?.map((t) => t.toJson()).toList() ?? [];
      await _storage.write(key: _tagsKey, value: jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error saving tags: $e');
    }
  }

  /// Load settings from secure storage
  Future<VaultSettings> _loadSettings() async {
    if (_cachedSettings != null) return _cachedSettings!;

    try {
      final settingsJson = await _storage.read(key: _settingsKey);
      if (settingsJson == null || settingsJson.isEmpty) {
        _cachedSettings = const VaultSettings();
        return _cachedSettings!;
      }

      _cachedSettings = VaultSettings.fromJson(
        jsonDecode(settingsJson) as Map<String, dynamic>,
      );
      return _cachedSettings!;
    } catch (e) {
      debugPrint('Error loading settings: $e');
      _cachedSettings = const VaultSettings();
      return _cachedSettings!;
    }
  }

  /// Save settings to secure storage
  Future<void> _saveSettings() async {
    try {
      await _storage.write(
        key: _settingsKey,
        value: jsonEncode(_cachedSettings?.toJson() ?? {}),
      );
    } catch (e) {
      debugPrint('Error saving settings: $e');
    }
  }

  /// Stream copy a file in chunks (memory-efficient for large files)
  Future<void> _streamCopyFile(
    File source,
    File destination, {
    Function(int processed, int total)? onProgress,
  }) async {
    final totalBytes = await source.length();
    var processedBytes = 0;
    final sink = destination.openWrite();

    onProgress?.call(0, totalBytes);

    await for (final chunk in source.openRead()) {
      sink.add(chunk);
      processedBytes += chunk.length;
      onProgress?.call(processedBytes, totalBytes);
    }

    await sink.flush();
    await sink.close();
  }

  Future<void> _deleteFileIfExists(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<int> _getFileSizeIfExists(String path) async {
    try {
      return await File(path).length();
    } catch (_) {
      return 0;
    }
  }

  /// Generate a unique encrypted filename
  String _generateVaultFilename(String originalName) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomBytes = utf8.encode('$originalName$timestamp${DateTime.now()}');
    final hash = sha256.convert(randomBytes).toString().substring(0, 16);

    final extension =
        originalName.contains('.') ? originalName.split('.').last : '';

    return extension.isNotEmpty ? '$hash.$extension' : hash;
  }

  /// Add a file to the vault
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
    );

    if (prepared == null) {
      return null;
    }

    await _storePreparedVaultAddition(
      prepared,
      deleteOriginal: deleteOriginal,
    );

    return prepared.vaultedFile;
  }

  /// Add multiple files to the vault (batch import)
  Future<List<VaultedFile>> addFiles({
    required List<FileToVault> files,
    bool deleteOriginals = false,
    bool encrypt = false,
    bool isDecoy = false,
    Function(int current, int total)? onProgress,
    Function(FileProgressInfo)? onFileProgress,
  }) async {
    // Load settings once before processing the batch
    _cachedSettings ??= await _loadSettings();
    final results = <VaultedFile>[];

    int completed = 0;
    final shouldEncrypt = encrypt || _cachedSettings?.encryptionEnabled == true;

    for (int start = 0;
        start < files.length;
        start += _maxConcurrentBatchAdds) {
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
          final fileSize = await _getFileSizeIfExists(entry.file.sourcePath);

          onFileProgress?.call(FileProgressInfo(
            current: entry.index + 1,
            total: files.length,
            fileName: entry.file.originalName,
            fileSize: fileSize,
            status: shouldEncrypt ? 'Encrypting 0%...' : 'Processing...',
            isEncrypting: shouldEncrypt,
            totalBytes: shouldEncrypt ? fileSize : 0,
          ));

          final prepared = await _prepareVaultAddition(
            sourcePath: entry.file.sourcePath,
            originalName: entry.file.originalName,
            type: entry.file.type,
            mimeType: entry.file.mimeType,
            encrypt: encrypt,
            isDecoy: isDecoy,
            onEncryptionProgress: shouldEncrypt
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
      _cachedSettings ??= await _loadSettings();

      if (_cachedSettings?.compressionEnabled == true) {
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
          ? await _ensureDecoyDirectory()
          : await _ensureVaultDirectory();

      final vaultFilename = _generateVaultFilename(originalName);
      final subdirectory = _getSubdirectory(type);
      vaultPath = '${directory.path}/$subdirectory/$vaultFilename';

      final shouldEncrypt =
          encrypt || _cachedSettings?.encryptionEnabled == true;
      String? encryptionIv;
      int fileSize;

      if (compressedImageBytes != null) {
        fileSize = compressedImageBytes.length;

        if (shouldEncrypt) {
          onEncryptionProgress?.call(0, fileSize);
          final useGcm = _cachedSettings?.encryptionAlgorithm == EncryptionAlgorithm.aes256Gcm;
          final encResult = useGcm
              ? await _encryptionService.encryptBytesStreamedGcm(
                  compressedImageBytes,
                  vaultPath,
                  isDecoy: isDecoy,
                )
              : await _encryptionService.encryptBytesStreamed(
                  compressedImageBytes,
                  vaultPath,
                  isDecoy: isDecoy,
                  onProgress: (processed, total) {
                    onEncryptionProgress?.call(processed, total);
                  },
                );
          onEncryptionProgress?.call(fileSize, fileSize);

          if (!encResult.success) {
            debugPrint('Encryption failed: ${encResult.error}');
            await _deleteFileIfExists(vaultPath);
            return null;
          }

          encryptionIv = encResult.iv;
          fileSize = encResult.originalSize ?? fileSize;
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
          final useGcm = _cachedSettings?.encryptionAlgorithm == EncryptionAlgorithm.aes256Gcm;
          final useIsolateEncryption =
              fileSize >= _largeFileIsolateThresholdBytes &&
                  onEncryptionProgress == null;
          final encResult = useIsolateEncryption
              ? await _encryptionService.encryptFileInIsolate(
                  sourcePathToUse,
                  vaultPath,
                  isDecoy: isDecoy,
                  useGcm: useGcm,
                  onProgress: (processed, total) {
                    onEncryptionProgress?.call(processed, total);
                  },
                )
              : useGcm
                  ? await _encryptionService.encryptFileStreamedGcm(
                      sourcePathToUse,
                      vaultPath,
                      isDecoy: isDecoy,
                      onProgress: (processed, total) {
                        onEncryptionProgress?.call(processed, total);
                      },
                    )
                  : await _encryptionService.encryptFileStreamed(
                      sourcePathToUse,
                      vaultPath,
                      isDecoy: isDecoy,
                      onProgress: (processed, total) {
                        onEncryptionProgress?.call(processed, total);
                      },
                    );
          onEncryptionProgress?.call(fileSize, fileSize);

          if (!encResult.success) {
            debugPrint('Encryption failed: ${encResult.error}');
            await _deleteFileIfExists(vaultPath);
            return null;
          }

          encryptionIv = encResult.iv;
          fileSize = encResult.originalSize ?? fileSize;
        } else {
          await _streamCopyFile(sourceFileForProcessing, File(vaultPath));
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
          isDecoy: isDecoy,
          tags: normalizedTags,
          albumIds: normalizedAlbumIds,
        ),
      );
    } catch (e) {
      if (vaultPath != null) {
        await _deleteFileIfExists(vaultPath);
      }
      debugPrint('Error adding file to vault: $e');
      return null;
    } finally {
      if (sourcePathToUse != null && sourcePathToUse != sourcePath) {
        try {
          await File(sourcePathToUse).delete();
          debugPrint(
              '[Vault] Cleaned up compressed temp file: $sourcePathToUse');
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
      _cachedDecoyFiles ??= await _loadFileIndex(isDecoy: true);
      _cachedDecoyFiles!.add(vaultedFile);
      await _saveFileIndex(isDecoy: true);
    } else {
      _cachedFiles ??= await _loadFileIndex();
      _cachedFiles!.add(vaultedFile);
      await _saveFileIndex();

      if (vaultedFile.albumIds.isNotEmpty) {
        _cachedAlbums ??= await _loadAlbums();

        for (final albumId in vaultedFile.albumIds) {
          final albumIndex =
              _cachedAlbums!.indexWhere((album) => album.id == albumId);
          if (albumIndex != -1) {
            _cachedAlbums![albumIndex] =
                _cachedAlbums![albumIndex].addFile(vaultedFile.id);
          }
        }

        await _saveAlbums();
      }

      if (vaultedFile.tags.isNotEmpty) {
        await _updateTagUsage(vaultedFile.tags);
      }
    }

    if (!deleteOriginal || vaultedFile.originalPath == null) {
      return;
    }

    try {
      await File(vaultedFile.originalPath!).delete();
    } catch (e) {
      debugPrint('Could not delete original file: $e');
    }
  }

  /// Update a file's metadata
  Future<VaultedFile?> updateFile(VaultedFile updatedFile) async {
    try {
      final files = await _loadFileIndex(isDecoy: updatedFile.isDecoy);
      final index = files.indexWhere((f) => f.id == updatedFile.id);

      if (index == -1) return null;

      if (updatedFile.isDecoy) {
        _cachedDecoyFiles![index] = updatedFile;
        await _saveFileIndex(isDecoy: true);
      } else {
        _cachedFiles![index] = updatedFile;
        await _saveFileIndex();
      }

      return updatedFile;
    } catch (e) {
      debugPrint('Error updating file: $e');
      return null;
    }
  }

  /// Remove a file from the vault
  Future<bool> removeFile(String fileId, {bool isDecoy = false}) async {
    try {
      final files = await _loadFileIndex(isDecoy: isDecoy);
      final fileIndex = files.indexWhere((f) => f.id == fileId);

      if (fileIndex == -1) return false;

      final file = files[fileIndex];

      // Delete the actual file
      final vaultFile = File(file.vaultPath);
      if (await vaultFile.exists()) {
        if (_cachedSettings?.secureDelete == true) {
          await _encryptionService.secureDelete(file.vaultPath);
        } else {
          await vaultFile.delete();
        }
      }

      // Delete thumbnail if exists
      if (file.thumbnailPath != null) {
        final thumbFile = File(file.thumbnailPath!);
        if (await thumbFile.exists()) {
          await thumbFile.delete();
        }
      }

      // Remove from albums
      if (!isDecoy && file.albumIds.isNotEmpty) {
        for (final albumId in file.albumIds) {
          await removeFileFromAlbum(fileId, albumId);
        }
      }

      // Remove from index
      if (isDecoy) {
        _cachedDecoyFiles!.removeAt(fileIndex);
        await _saveFileIndex(isDecoy: true);
      } else {
        _cachedFiles!.removeAt(fileIndex);
        await _saveFileIndex();
      }

      return true;
    } catch (e) {
      debugPrint('Error removing file from vault: $e');
      return false;
    }
  }

  /// Remove multiple files from the vault
  Future<int> removeFiles(
    List<String> fileIds, {
    bool isDecoy = false,
    void Function(int current, int total, {int currentSize, int totalSize})?
        onProgress,
  }) async {
    final fileIndex = await _loadFileIndex(isDecoy: isDecoy);
    final idSet = fileIds.toSet();
    final filesToDelete = fileIndex.where((f) => idSet.contains(f.id)).toList();
    final totalSize = filesToDelete.fold<int>(0, (s, f) => s + f.fileSize);

    int removed = 0;
    int currentSize = 0;
    for (final id in fileIds) {
      final file = filesToDelete.cast<VaultedFile?>().firstWhere(
        (f) => f?.id == id,
        orElse: () => null,
      );
      final fileSize = file?.fileSize ?? 0;
      if (await removeFile(id, isDecoy: isDecoy)) {
        removed++;
        currentSize += fileSize;
        onProgress?.call(removed, fileIds.length,
            currentSize: currentSize, totalSize: totalSize);
      }
    }
    return removed;
  }

  /// Get all vaulted files
  Future<List<VaultedFile>> getAllFiles({bool isDecoy = false}) async {
    return await _loadFileIndex(isDecoy: isDecoy);
  }

  /// Get files by type
  Future<List<VaultedFile>> getFilesByType(
    VaultedFileType type, {
    bool isDecoy = false,
  }) async {
    final files = await _loadFileIndex(isDecoy: isDecoy);
    return files.where((f) => f.type == type).toList();
  }

  /// Get file by ID
  Future<VaultedFile?> getFileById(String fileId,
      {bool isDecoy = false}) async {
    final files = await _loadFileIndex(isDecoy: isDecoy);
    try {
      return files.firstWhere((f) => f.id == fileId);
    } catch (e) {
      return null;
    }
  }

  /// Get the actual file from vault (decrypts if needed)
  Future<File?> getVaultedFile(String fileId, {bool isDecoy = false}) async {
    final vaultedFile = await getFileById(fileId, isDecoy: isDecoy);
    if (vaultedFile == null) return null;

    final file = File(vaultedFile.vaultPath);
    if (!await file.exists()) return null;

    // If encrypted, decrypt to temp file
    if (vaultedFile.isEncrypted && vaultedFile.encryptionIv != null) {
      final tempDir = await _ensureVaultDirectory();
      final tempPath =
          '${tempDir.path}/temp/${vaultedFile.id}_${vaultedFile.originalName}';

      final result = await _encryptionService.decryptFile(
        vaultedFile.vaultPath,
        tempPath,
        vaultedFile.encryptionIv!,
        isDecoy: isDecoy,
      );

      if (result.success && result.decryptedPath != null) {
        return File(result.decryptedPath!);
      }
      return null;
    }

    return file;
  }

  /// Get decrypted file data in memory (for viewing)
  Future<Uint8List?> getDecryptedFileData(
    String fileId, {
    bool isDecoy = false,
  }) async {
    final vaultedFile = await getFileById(fileId, isDecoy: isDecoy);
    if (vaultedFile == null) return null;

    if (vaultedFile.isEncrypted && vaultedFile.encryptionIv != null) {
      // Use decryptStreamedFileToMemory which auto-detects format
      // (legacy CBC vs new CTR streamed encryption)
      final result = await _encryptionService.decryptStreamedFileToMemory(
        vaultedFile.vaultPath,
        vaultedFile.encryptionIv!,
        isDecoy: isDecoy,
      );

      if (result.success && result.data != null) {
        // Mark as viewed
        await updateFile(vaultedFile.markViewed());
        return result.data;
      }
      return null;
    }

    final file = File(vaultedFile.vaultPath);
    if (!await file.exists()) return null;

    // Mark as viewed
    await updateFile(vaultedFile.markViewed());
    return await file.readAsBytes();
  }

  // ========== ALBUM OPERATIONS ==========

  /// Get all albums
  Future<List<Album>> getAllAlbums() async {
    return await _loadAlbums();
  }

  /// Get album by ID
  Future<Album?> getAlbumById(String albumId) async {
    final albums = await _loadAlbums();
    try {
      return albums.firstWhere((a) => a.id == albumId);
    } catch (e) {
      return null;
    }
  }

  /// Create a new album
  Future<Album?> createAlbum({
    required String name,
    String? description,
    String? coverImageId,
  }) async {
    try {
      final now = DateTime.now();
      final id = sha256
          .convert(utf8.encode('$name${now.millisecondsSinceEpoch}'))
          .toString()
          .substring(0, 16);

      final album = Album(
        id: id,
        name: name,
        description: description,
        coverImageId: coverImageId,
        createdAt: now,
        updatedAt: now,
        sortOrder: (_cachedAlbums?.length ?? 0) + 1,
      );

      _cachedAlbums ??= [];
      _cachedAlbums!.add(album);
      await _saveAlbums();

      return album;
    } catch (e) {
      debugPrint('Error creating album: $e');
      return null;
    }
  }

  /// Update an album
  Future<Album?> updateAlbum(Album updatedAlbum) async {
    try {
      final albums = await _loadAlbums();
      final index = albums.indexWhere((a) => a.id == updatedAlbum.id);

      if (index == -1) return null;

      _cachedAlbums![index] = updatedAlbum.copyWith(updatedAt: DateTime.now());
      await _saveAlbums();

      return _cachedAlbums![index];
    } catch (e) {
      debugPrint('Error updating album: $e');
      return null;
    }
  }

  /// Delete an album
  Future<bool> deleteAlbum(String albumId) async {
    try {
      final albums = await _loadAlbums();
      final album = albums.firstWhere(
        (a) => a.id == albumId,
        orElse: () => throw Exception('Album not found'),
      );

      // Don't delete default albums
      if (album.isDefault) {
        debugPrint('Cannot delete default album');
        return false;
      }

      // Remove album reference from files
      for (final fileId in album.fileIds) {
        final file = await getFileById(fileId);
        if (file != null) {
          await updateFile(file.removeFromAlbum(albumId));
        }
      }

      _cachedAlbums!.removeWhere((a) => a.id == albumId);
      await _saveAlbums();

      return true;
    } catch (e) {
      debugPrint('Error deleting album: $e');
      return false;
    }
  }

  /// Add file to album
  Future<bool> addFileToAlbum(String fileId, String albumId) async {
    try {
      final file = await getFileById(fileId);
      if (file == null) return false;

      final albums = await _loadAlbums();
      final albumIndex = albums.indexWhere((a) => a.id == albumId);
      if (albumIndex == -1) return false;

      // Update album
      _cachedAlbums![albumIndex] = _cachedAlbums![albumIndex].addFile(fileId);
      await _saveAlbums();

      // Update file - also set isFavorite if adding to favorites album
      VaultedFile updatedFile = file.addToAlbum(albumId);
      if (albumId == 'favorites') {
        updatedFile = updatedFile.copyWith(isFavorite: true);
      }
      await updateFile(updatedFile);

      return true;
    } catch (e) {
      debugPrint('Error adding file to album: $e');
      return false;
    }
  }

  /// Remove file from album
  Future<bool> removeFileFromAlbum(String fileId, String albumId) async {
    try {
      final albums = await _loadAlbums();
      final albumIndex = albums.indexWhere((a) => a.id == albumId);
      if (albumIndex == -1) return false;

      // Update album
      _cachedAlbums![albumIndex] =
          _cachedAlbums![albumIndex].removeFile(fileId);
      await _saveAlbums();

      // Update file - also unset isFavorite if removing from favorites album
      final file = await getFileById(fileId);
      if (file != null) {
        VaultedFile updatedFile = file.removeFromAlbum(albumId);
        if (albumId == 'favorites') {
          updatedFile = updatedFile.copyWith(isFavorite: false);
        }
        await updateFile(updatedFile);
      }

      return true;
    } catch (e) {
      debugPrint('Error removing file from album: $e');
      return false;
    }
  }

  /// Get files in album
  Future<List<VaultedFile>> getFilesInAlbum(String albumId) async {
    final album = await getAlbumById(albumId);
    if (album == null) return [];

    final files = await getAllFiles();
    return files.where((f) => album.fileIds.contains(f.id)).toList();
  }

  // ========== TAG OPERATIONS ==========

  /// Get all unique tags
  Future<List<TagInfo>> getAllTags() async {
    return await _loadTags();
  }

  /// Get files by tag
  Future<List<VaultedFile>> getFilesByTag(String tag) async {
    final files = await getAllFiles();
    return files.where((f) => f.hasTag(tag)).toList();
  }

  /// Add tag to file
  Future<VaultedFile?> addTagToFile(String fileId, String tag) async {
    final file = await getFileById(fileId);
    if (file == null) return null;

    final updatedFile = file.addTag(tag);
    await updateFile(updatedFile);
    await _updateTagUsage([tag]);

    return updatedFile;
  }

  /// Remove tag from file
  Future<VaultedFile?> removeTagFromFile(String fileId, String tag) async {
    final file = await getFileById(fileId);
    if (file == null) return null;

    final updatedFile = file.removeTag(tag);
    await updateFile(updatedFile);

    return updatedFile;
  }

  /// Update tag usage counts
  Future<void> _updateTagUsage(List<String> tags) async {
    _cachedTags ??= [];

    for (final tag in tags) {
      final normalizedTag = tag.toLowerCase().trim();
      if (normalizedTag.isEmpty) continue;

      final existingIndex =
          _cachedTags!.indexWhere((t) => t.name == normalizedTag);

      if (existingIndex == -1) {
        _cachedTags!.add(TagInfo(name: normalizedTag, usageCount: 1));
      } else {
        _cachedTags![existingIndex] = TagInfo(
          name: normalizedTag,
          colorValue: _cachedTags![existingIndex].colorValue,
          usageCount: _cachedTags![existingIndex].usageCount + 1,
        );
      }
    }

    await _saveTags();
  }

  /// Create a new tag with optional color
  Future<TagInfo> createTag(String name, [int? colorValue]) async {
    _cachedTags ??= await _loadTags();

    final normalizedName = name.toLowerCase().trim();
    final existingIndex =
        _cachedTags!.indexWhere((t) => t.name == normalizedName);

    if (existingIndex != -1) {
      // Tag already exists, just update color if provided
      if (colorValue != null) {
        _cachedTags![existingIndex] = TagInfo(
          name: normalizedName,
          colorValue: colorValue,
          usageCount: _cachedTags![existingIndex].usageCount,
        );
        await _saveTags();
      }
      return _cachedTags![existingIndex];
    }

    // Create new tag
    final newTag = TagInfo(
      name: normalizedName,
      colorValue: colorValue ?? 0xFF1976D2,
      usageCount: 0,
    );
    _cachedTags!.add(newTag);
    await _saveTags();

    return newTag;
  }

  /// Update a tag's color
  Future<bool> updateTagColor(String tagName, int colorValue) async {
    _cachedTags ??= await _loadTags();

    final normalizedName = tagName.toLowerCase().trim();
    final index = _cachedTags!.indexWhere((t) => t.name == normalizedName);

    if (index == -1) return false;

    _cachedTags![index] = TagInfo(
      name: normalizedName,
      colorValue: colorValue,
      usageCount: _cachedTags![index].usageCount,
    );
    await _saveTags();

    return true;
  }

  /// Delete a tag and remove it from all files
  Future<bool> deleteTag(String tagName) async {
    try {
      final normalizedName = tagName.toLowerCase().trim();

      // Remove tag from all files
      final files = await getAllFiles();
      for (final file in files) {
        if (file.hasTag(normalizedName)) {
          await removeTagFromFile(file.id, normalizedName);
        }
      }

      // Remove from cached tags
      _cachedTags ??= await _loadTags();
      _cachedTags!.removeWhere((t) => t.name == normalizedName);
      await _saveTags();

      return true;
    } catch (e) {
      debugPrint('Error deleting tag: $e');
      return false;
    }
  }

  // ========== SORTING ==========

  /// Sort files
  List<VaultedFile> sortFiles(List<VaultedFile> files, SortOption sortOption) {
    final sorted = List<VaultedFile>.from(files);

    switch (sortOption) {
      case SortOption.nameAsc:
        sorted.sort((a, b) => a.originalName
            .toLowerCase()
            .compareTo(b.originalName.toLowerCase()));
        break;
      case SortOption.nameDesc:
        sorted.sort((a, b) => b.originalName
            .toLowerCase()
            .compareTo(a.originalName.toLowerCase()));
        break;
      case SortOption.dateAddedNewest:
        sorted.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
        break;
      case SortOption.dateAddedOldest:
        sorted.sort((a, b) => a.dateAdded.compareTo(b.dateAdded));
        break;
      case SortOption.dateModifiedNewest:
        sorted.sort((a, b) => (b.dateModified ?? b.dateAdded)
            .compareTo(a.dateModified ?? a.dateAdded));
        break;
      case SortOption.dateModifiedOldest:
        sorted.sort((a, b) => (a.dateModified ?? a.dateAdded)
            .compareTo(b.dateModified ?? b.dateAdded));
        break;
      case SortOption.sizeSmallest:
        sorted.sort((a, b) => a.fileSize.compareTo(b.fileSize));
        break;
      case SortOption.sizeLargest:
        sorted.sort((a, b) => b.fileSize.compareTo(a.fileSize));
        break;
      case SortOption.typeAsc:
        sorted.sort((a, b) => a.type.displayName.compareTo(b.type.displayName));
        break;
      case SortOption.typeDesc:
        sorted.sort((a, b) => b.type.displayName.compareTo(a.type.displayName));
        break;
    }

    return sorted;
  }

  // ========== FAVORITES ==========

  /// Toggle favorite status
  Future<VaultedFile?> toggleFavorite(String fileId) async {
    final file = await getFileById(fileId);
    if (file == null) return null;

    // Update favorites album - this will also update the isFavorite flag
    final favoritesAlbum = await getAlbumById('favorites');
    if (favoritesAlbum != null) {
      if (file.isFavorite) {
        // Currently favorite, so remove from favorites
        await removeFileFromAlbum(fileId, 'favorites');
      } else {
        // Not favorite, so add to favorites
        await addFileToAlbum(fileId, 'favorites');
      }
    } else {
      // No favorites album exists, just toggle the flag directly
      final updatedFile = file.toggleFavorite();
      await updateFile(updatedFile);
      return updatedFile;
    }

    // Return the updated file
    return await getFileById(fileId);
  }

  /// Get favorite files
  Future<List<VaultedFile>> getFavoriteFiles() async {
    final files = await getAllFiles();
    return files.where((f) => f.isFavorite).toList();
  }

  // ========== SEARCH ==========

  /// Search files by name
  Future<List<VaultedFile>> searchFiles(String query) async {
    final files = await _loadFileIndex();
    final lowerQuery = query.toLowerCase();
    return files
        .where((f) => f.originalName.toLowerCase().contains(lowerQuery))
        .toList();
  }

  /// Search files by name and tags
  Future<List<VaultedFile>> searchFilesAdvanced({
    String? query,
    List<String>? tags,
    VaultedFileType? type,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool? isFavorite,
    String? albumId,
  }) async {
    var files = await getAllFiles();

    // Filter by query
    if (query != null && query.isNotEmpty) {
      final lowerQuery = query.toLowerCase();
      files = files
          .where((f) => f.originalName.toLowerCase().contains(lowerQuery))
          .toList();
    }

    // Filter by tags
    if (tags != null && tags.isNotEmpty) {
      files = files.where((f) => tags.every((tag) => f.hasTag(tag))).toList();
    }

    // Filter by type
    if (type != null) {
      files = files.where((f) => f.type == type).toList();
    }

    // Filter by date range
    if (dateFrom != null) {
      files = files.where((f) => f.dateAdded.isAfter(dateFrom)).toList();
    }
    if (dateTo != null) {
      files = files.where((f) => f.dateAdded.isBefore(dateTo)).toList();
    }

    // Filter by favorite
    if (isFavorite != null) {
      files = files.where((f) => f.isFavorite == isFavorite).toList();
    }

    // Filter by album
    if (albumId != null) {
      files = files.where((f) => f.isInAlbum(albumId)).toList();
    }

    return files;
  }

  // ========== SETTINGS ==========

  /// Get vault settings
  Future<VaultSettings> getSettings() async {
    return await _loadSettings();
  }

  /// Update vault settings
  Future<void> updateSettings(VaultSettings settings) async {
    _cachedSettings = settings;
    await _saveSettings();
  }

  // ========== STATISTICS ==========

  /// Get file counts by type
  Future<Map<VaultedFileType, int>> getFileCounts() async {
    final files = await _loadFileIndex();
    final counts = <VaultedFileType, int>{};

    for (final type in VaultedFileType.values) {
      counts[type] = files.where((f) => f.type == type).length;
    }

    return counts;
  }

  /// Get total storage used
  Future<int> getTotalStorageUsed() async {
    final files = await _loadFileIndex();
    return files.fold<int>(0, (sum, file) => sum + file.fileSize);
  }

  /// Export a file from vault to a location
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

      final fileSize = await sourceFile.length();
      const largeFileThreshold = 10 * 1024 * 1024; // 10MB
      final isLargeFile = fileSize > largeFileThreshold;

      // If encrypted, decrypt first
      if (vaultedFile.isEncrypted && vaultedFile.encryptionIv != null) {
        // Check if it's a streamed CTR file by reading magic bytes
        final raf = await sourceFile.open();
        final header = await raf.read(4);
        await raf.close();

        final isStreamedFile = header.length >= 4 &&
            header[0] == 0x4C &&
            header[1] == 0x4B &&
            header[2] == 0x52 &&
            header[3] == 0x53;

        FileDecryptionResult result;
        if (isStreamedFile || isLargeFile) {
          // Use streaming decryption for CTR files or large files
          if (isStreamedFile) {
            result = await _encryptionService.decryptFileStreamed(
              vaultedFile.vaultPath,
              destinationPath,
              vaultedFile.encryptionIv!,
              onProgress: onProgress,
            );
          } else {
            // Legacy CBC file but large - still use regular method
            // (CBC can't be streamed without the full file)
            result = await _encryptionService.decryptFile(
              vaultedFile.vaultPath,
              destinationPath,
              vaultedFile.encryptionIv!,
              onProgress: onProgress == null
                  ? null
                  : (current, total) {
                      final estimatedProcessed = total > 0
                          ? (current / total * vaultedFile.fileSize).round()
                          : 0;
                      onProgress(estimatedProcessed, vaultedFile.fileSize);
                    },
            );
          }
        } else {
          result = await _encryptionService.decryptFile(
            vaultedFile.vaultPath,
            destinationPath,
            vaultedFile.encryptionIv!,
            onProgress: onProgress == null
                ? null
                : (current, total) {
                    final estimatedProcessed = total > 0
                        ? (current / total * vaultedFile.fileSize).round()
                        : 0;
                    onProgress(estimatedProcessed, vaultedFile.fileSize);
                  },
          );
        }

        if (result.success && result.decryptedPath != null) {
          return File(result.decryptedPath!);
        }
        return null;
      }

      // Non-encrypted file - stream the copy so we can report progress.
      await _streamCopyFile(
        sourceFile,
        File(destinationPath),
        onProgress: onProgress,
      );
      return File(destinationPath);
    } catch (e) {
      debugPrint('Error exporting file: $e');
      return null;
    }
  }

  /// Re-encrypt all vault files to a target algorithm
  /// Returns the number of files re-encrypted, or -1 on failure
  Future<int> reEncryptVault(
    EncryptionAlgorithm targetAlgorithm, {
    bool isDecoy = false,
    Function(int current, int total)? onProgress,
  }) async {
    try {
      final files = isDecoy
          ? (await getAllFiles(isDecoy: true))
          : (await getAllFiles(isDecoy: false));
      final encryptedFiles = files.where((f) => f.isEncrypted).toList();

      if (encryptedFiles.isEmpty) return 0;

      int reEncryptedCount = 0;
      for (int i = 0; i < encryptedFiles.length; i++) {
        onProgress?.call(i + 1, encryptedFiles.length);

        final file = encryptedFiles[i];
        if (!await File(file.vaultPath).exists()) continue;

        final currentFormat = _encryptionService.detectFileFormat(file.vaultPath);
        final targetIsGcm = targetAlgorithm == EncryptionAlgorithm.aes256Gcm;
        final currentIsGcm = currentFormat == 1;

        if (currentIsGcm == targetIsGcm && currentFormat != 0 && currentFormat != 3) continue;

        final newIv = await _encryptionService.reEncryptFile(
          file.vaultPath,
          file.encryptionIv ?? '',
          targetAlgorithm: targetAlgorithm,
          isDecoy: isDecoy,
        );

        final fileIndex = files.indexWhere((f) => f.id == file.id);
        if (fileIndex >= 0) {
          files[fileIndex] = file.copyWith(encryptionIv: newIv);
          reEncryptedCount++;
        }
      }

      if (isDecoy) {
        _cachedDecoyFiles = files;
      } else {
        _cachedFiles = files;
      }

      await _saveFileIndex(isDecoy: isDecoy);
      return reEncryptedCount;
    } catch (e) {
      debugPrint('Re-encryption error: $e');
      return -1;
    }
  }

  /// Clear all vault data (use with caution!)
  Future<void> clearVault({bool isDecoy = false}) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final directory = Directory(
        '${appDir.path}/${isDecoy ? _decoyFolderName : _vaultFolderName}',
      );

      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }

      if (isDecoy) {
        _cachedDecoyFiles = [];
        await _storage.delete(key: _decoyIndexKey);
        _decoyDirectory = null;
      } else {
        _cachedFiles = [];
        _cachedAlbums = null;
        _cachedTags = null;
        await _storage.delete(key: _vaultIndexKey);
        await _storage.delete(key: _albumsKey);
        await _storage.delete(key: _tagsKey);
        _vaultDirectory = null;
      }
    } catch (e) {
      debugPrint('Error clearing vault: $e');
    }
  }

  /// Refresh the cache
  Future<void> refresh() async {
    _cachedFiles = null;
    _cachedDecoyFiles = null;
    _cachedAlbums = null;
    _cachedTags = null;
    await _loadFileIndex();
    await _loadAlbums();
    await _loadTags();
  }

  /// Clean up temp files
  Future<void> cleanupTemp() async {
    try {
      final vaultDir = await _ensureVaultDirectory();
      final tempDir = Directory('${vaultDir.path}/temp');

      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
        await tempDir.create();
      }
    } catch (e) {
      debugPrint('Error cleaning temp: $e');
    }
  }
}

/// Helper class for batch file import
class FileToVault {
  final String sourcePath;
  final String originalName;
  final VaultedFileType type;
  final String mimeType;

  const FileToVault({
    required this.sourcePath,
    required this.originalName,
    required this.type,
    required this.mimeType,
  });
}

/// Vault settings
class VaultSettings {
  final bool encryptionEnabled;
  final EncryptionAlgorithm encryptionAlgorithm;
  final int kdfIterations;
  final bool secureDelete;
  final bool screenshotProtectionEnabled;
  final int autoKillDelaySeconds;
  final SortOption defaultSort;
  final bool showHiddenFiles;
  final bool autoBackup;
  final int? maxStorageMB;
  final bool decoyModeEnabled;
  final String? decoyPin;
  final bool compressionEnabled;
  final bool failedUnlockProtectionEnabled;
  final int maxFailedAttemptsBeforeLockout;
  final int lockoutDurationSeconds;
  final bool wipeVaultOnMaxFailedAttempts;
  final int maxFailedAttemptsBeforeWipe;

  const VaultSettings({
    this.encryptionEnabled = false,
    this.encryptionAlgorithm = EncryptionAlgorithm.aes256Ctr,
    this.kdfIterations = 100000,
    this.secureDelete = true,
    this.screenshotProtectionEnabled = false,
    this.autoKillDelaySeconds = 0,
    this.defaultSort = SortOption.dateAddedNewest,
    this.showHiddenFiles = false,
    this.autoBackup = false,
    this.maxStorageMB,
    this.decoyModeEnabled = false,
    this.decoyPin,
    this.compressionEnabled = false,
    this.failedUnlockProtectionEnabled = false,
    this.maxFailedAttemptsBeforeLockout = 5,
    this.lockoutDurationSeconds = 30,
    this.wipeVaultOnMaxFailedAttempts = false,
    this.maxFailedAttemptsBeforeWipe = 12,
  });

  VaultSettings copyWith({
    bool? encryptionEnabled,
    EncryptionAlgorithm? encryptionAlgorithm,
    int? kdfIterations,
    bool? secureDelete,
    bool? screenshotProtectionEnabled,
    int? autoKillDelaySeconds,
    SortOption? defaultSort,
    bool? showHiddenFiles,
    bool? autoBackup,
    int? maxStorageMB,
    bool? decoyModeEnabled,
    String? decoyPin,
    bool? compressionEnabled,
    bool? failedUnlockProtectionEnabled,
    int? maxFailedAttemptsBeforeLockout,
    int? lockoutDurationSeconds,
    bool? wipeVaultOnMaxFailedAttempts,
    int? maxFailedAttemptsBeforeWipe,
  }) {
    return VaultSettings(
      encryptionEnabled: encryptionEnabled ?? this.encryptionEnabled,
      encryptionAlgorithm: encryptionAlgorithm ?? this.encryptionAlgorithm,
      kdfIterations: kdfIterations ?? this.kdfIterations,
      secureDelete: secureDelete ?? this.secureDelete,
      screenshotProtectionEnabled:
          screenshotProtectionEnabled ?? this.screenshotProtectionEnabled,
      autoKillDelaySeconds: autoKillDelaySeconds ?? this.autoKillDelaySeconds,
      defaultSort: defaultSort ?? this.defaultSort,
      showHiddenFiles: showHiddenFiles ?? this.showHiddenFiles,
      autoBackup: autoBackup ?? this.autoBackup,
      maxStorageMB: maxStorageMB ?? this.maxStorageMB,
      decoyModeEnabled: decoyModeEnabled ?? this.decoyModeEnabled,
      decoyPin: decoyPin ?? this.decoyPin,
      compressionEnabled: compressionEnabled ?? this.compressionEnabled,
      failedUnlockProtectionEnabled:
          failedUnlockProtectionEnabled ?? this.failedUnlockProtectionEnabled,
      maxFailedAttemptsBeforeLockout:
          maxFailedAttemptsBeforeLockout ?? this.maxFailedAttemptsBeforeLockout,
      lockoutDurationSeconds:
          lockoutDurationSeconds ?? this.lockoutDurationSeconds,
      wipeVaultOnMaxFailedAttempts:
          wipeVaultOnMaxFailedAttempts ?? this.wipeVaultOnMaxFailedAttempts,
      maxFailedAttemptsBeforeWipe:
          maxFailedAttemptsBeforeWipe ?? this.maxFailedAttemptsBeforeWipe,
    );
  }

  Map<String, dynamic> toJson() => {
        'encryptionEnabled': encryptionEnabled,
        'encryptionAlgorithm': encryptionAlgorithm.name,
        'kdfIterations': kdfIterations,
        'secureDelete': secureDelete,
        'screenshotProtectionEnabled': screenshotProtectionEnabled,
        'autoKillDelaySeconds': autoKillDelaySeconds,
        'defaultSort': defaultSort.name,
        'showHiddenFiles': showHiddenFiles,
        'autoBackup': autoBackup,
        'maxStorageMB': maxStorageMB,
        'decoyModeEnabled': decoyModeEnabled,
        'decoyPin': decoyPin,
        'compressionEnabled': compressionEnabled,
        'failedUnlockProtectionEnabled': failedUnlockProtectionEnabled,
        'maxFailedAttemptsBeforeLockout': maxFailedAttemptsBeforeLockout,
        'lockoutDurationSeconds': lockoutDurationSeconds,
        'wipeVaultOnMaxFailedAttempts': wipeVaultOnMaxFailedAttempts,
        'maxFailedAttemptsBeforeWipe': maxFailedAttemptsBeforeWipe,
      };

  factory VaultSettings.fromJson(Map<String, dynamic> json) {
    return VaultSettings(
      encryptionEnabled: json['encryptionEnabled'] as bool? ?? false,
      encryptionAlgorithm: EncryptionAlgorithm.values.firstWhere(
        (a) => a.name == (json['encryptionAlgorithm'] as String? ?? 'aes256Ctr'),
        orElse: () => EncryptionAlgorithm.aes256Ctr,
      ),
      kdfIterations: json['kdfIterations'] as int? ?? 100000,
      secureDelete: json['secureDelete'] as bool? ?? true,
      screenshotProtectionEnabled:
          json['screenshotProtectionEnabled'] as bool? ?? false,
      autoKillDelaySeconds: json['autoKillDelaySeconds'] as int? ?? 0,
      defaultSort: SortOption.values.firstWhere(
        (s) => s.name == (json['defaultSort'] as String? ?? 'dateAddedNewest'),
        orElse: () => SortOption.dateAddedNewest,
      ),
      showHiddenFiles: json['showHiddenFiles'] as bool? ?? false,
      autoBackup: json['autoBackup'] as bool? ?? false,
      maxStorageMB: json['maxStorageMB'] as int?,
      decoyModeEnabled: json['decoyModeEnabled'] as bool? ?? false,
      decoyPin: json['decoyPin'] as String?,
      compressionEnabled: json['compressionEnabled'] as bool? ?? false,
      failedUnlockProtectionEnabled:
          json['failedUnlockProtectionEnabled'] as bool? ?? false,
      maxFailedAttemptsBeforeLockout:
          json['maxFailedAttemptsBeforeLockout'] as int? ?? 5,
      lockoutDurationSeconds: json['lockoutDurationSeconds'] as int? ?? 30,
      wipeVaultOnMaxFailedAttempts:
          json['wipeVaultOnMaxFailedAttempts'] as bool? ?? false,
      maxFailedAttemptsBeforeWipe:
          json['maxFailedAttemptsBeforeWipe'] as int? ?? 12,
    );
  }
}
