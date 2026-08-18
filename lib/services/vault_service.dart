import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/album.dart';
import '../models/encryption_algorithm.dart';
import '../models/file_to_vault.dart';
import '../models/vault_folder.dart';
import '../models/vault_settings.dart';
import '../models/vaulted_file.dart';
import 'album_service.dart';
import 'crypto_isolate_pool.dart';
import 'encryption_service.dart';
import 'file_service.dart';
import 'folder_service.dart';
import 'pb/migrate_legacy_index.dart';
import 'pb/pocketbase_runtime.dart';
import 'pb/pocketbase_store.dart';
import 'search_service.dart';
import 'settings_service.dart';
import 'stats_service.dart';
import 'tag_service.dart';
import 'thumbnail_service.dart';
import 'vault_store.dart';

export 'file_service.dart' show FileProgressInfo;

/// Facade over the split vault services. Preserves the original `VaultService`
/// API surface so the 11 direct `VaultService.instance` callers + Riverpod
/// providers keep working. Phase 4 (Riverpod) removes this facade in favor of
/// per-service providers.
///
/// ponytail: facade + forwarding. The real logic now lives in the split
/// services (FileService, AlbumService, FolderService, TagService,
/// ThumbnailService, SearchService, StatsService, SettingsService). This
/// class solely composes them + forwards ~100 public methods. No behavioral
/// changes from pre-split — same delegate order, same cache (now in VaultStore).
class VaultService {
  @visibleForTesting
  VaultService();
  static final VaultService instance = VaultService();

  late final VaultStore _store = VaultStore();
  late final EncryptionService _encryptionService = EncryptionService.instance;

  /// The shared vault state holder. Exposed so Riverpod-constructed services
  /// (e.g. SyncService) can share the same caches without a new singleton.
  VaultStore get store => _store;

  // ponytail: File↔Thumbnail form a construction cycle (each calls the other
  // at runtime, never at construction). Break it with a late non-final
  // back-reference on ThumbnailService that's wired after both exist.
  late final ThumbnailService _thumbnails =
      ThumbnailService(_store, _encryptionService);
  late final FileService _files =
      FileService(_store, _encryptionService, _thumbnails);
  late final AlbumService _albums = AlbumService(_store, _files);
  late final FolderService _folders = FolderService(_store, _files);
  late final TagService _tags = TagService(_store, _albums, _files);
  late final SearchService _search = SearchService(_store);
  late final StatsService _stats = StatsService(_store);
  late final SettingsService _settings = SettingsService(_store);

  // Wire late back-edges once everything's constructed. Tests hit this via
  // the implicit first call to any forwarded method.
  bool _wired = false;
  void _wire() {
    if (_wired) return;
    _thumbnails.fileService = _files;
    _files.updateTagUsage = _tags.updateTagUsage;
    _files.removeFileFromAlbumFn = _albums.removeFileFromAlbum;
    _wired = true;
  }

  // ---- Lifecycle ----

  Future<void> initialize() async {
    await _encryptionService.initialize();
    await _store.ensureVaultDirectory();
    await _store.loadFileIndex();
    await _store.loadAlbums();
    await _store.loadFolders();
    await _store.loadTags();
    await _store.loadSettings();
    _wire();
  }

  /// P4.2: route the non-decoy index through the PocketBase sidecar (PB
  /// preferred, legacy fallback — the routing lives in `VaultStore`).
  /// Runs the one-time legacy migration, then reloads every cache from PB.
  /// No-op when the sidecar isn't running. Call only after the vault is
  /// unlocked (the DAOs need the master key).
  Future<void> activatePocketBase() async {
    final client = PocketBaseRuntime.instance.client;
    if (client == null) return;
    final masterKey = await _encryptionService.getMasterKey();
    final pb = PocketBaseStore(client: client, masterKey: masterKey);
    await migrateLegacyIndex(pb);
    _store.pbStore = pb;
    await refresh();
  }

  /// Loads indexes without initializing encryption (test-only).
  @visibleForTesting
  Future<void> loadIndexesForTesting() async {
    _wire();
    await _store.ensureVaultDirectory();
    _store.cachedFiles = await _store.loadFileIndex(forceReload: true);
    _store.cachedDecoyFiles =
        await _store.loadFileIndex(isDecoy: true, forceReload: true);
    _store.cachedAlbums = await _store.loadAlbums(forceReload: true);
    _store.cachedFolders = await _store.loadFolders(forceReload: true);
    _store.cachedTags = await _store.loadTags(forceReload: true);
    _store.cachedSettings = await _store.loadSettings();
  }

  // ---- Files ----

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
  }) =>
      _files.addFile(
        sourcePath: sourcePath,
        originalName: originalName,
        type: type,
        mimeType: mimeType,
        deleteOriginal: deleteOriginal,
        encrypt: encrypt,
        isDecoy: isDecoy,
        tags: tags,
        albumIds: albumIds,
        encryptionAlgorithm: encryptionAlgorithm,
        kdfIterations: kdfIterations,
      );

  Future<List<VaultedFile>> addFiles({
    required List<FileToVault> files,
    bool deleteOriginals = false,
    bool encrypt = false,
    bool isDecoy = false,
    Function(int current, int total)? onProgress,
    Function(FileProgressInfo)? onFileProgress,
  }) =>
      _files.addFiles(
        files: files,
        deleteOriginals: deleteOriginals,
        encrypt: encrypt,
        isDecoy: isDecoy,
        onProgress: onProgress,
        onFileProgress: onFileProgress,
      );

  Future<VaultedFile?> updateFile(VaultedFile updatedFile) =>
      _files.updateFile(updatedFile);

  Future<bool> removeFile(String fileId, {bool isDecoy = false}) =>
      _files.removeFile(fileId, isDecoy: isDecoy);

  Future<int> removeFiles(
    List<String> fileIds, {
    bool isDecoy = false,
    void Function(int current, int total, {int currentSize, int totalSize})?
        onProgress,
  }) =>
      _files.removeFiles(
        fileIds,
        isDecoy: isDecoy,
        onProgress: onProgress,
      );

  Future<List<VaultedFile>> getAllFiles({bool isDecoy = false}) =>
      _files.getAllFiles(isDecoy: isDecoy);

  Future<List<VaultedFile>> getFilesByType(VaultedFileType type,
          {bool isDecoy = false}) =>
      _files.getFilesByType(type, isDecoy: isDecoy);

  Future<VaultedFile?> getFileById(String fileId, {bool isDecoy = false}) =>
      _files.getFileById(fileId, isDecoy: isDecoy);

  Future<File?> getVaultedFile(
    String fileId, {
    bool isDecoy = false,
    Function(int processed, int total)? onProgress,
    CancelToken? cancelToken,
  }) =>
      _files.getVaultedFile(
        fileId,
        isDecoy: isDecoy,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );

  Future<Uint8List?> getDecryptedFileData(String fileId, {bool isDecoy = false}) =>
      _files.getDecryptedFileData(fileId, isDecoy: isDecoy);

  Future<File?> exportFile(
    String fileId,
    String destinationPath, {
    bool isDecoy = false,
    Function(int processed, int total)? onProgress,
  }) =>
      _files.exportFile(
        fileId,
        destinationPath,
        isDecoy: isDecoy,
        onProgress: onProgress,
      );

  Future<int> reEncryptVault(
    EncryptionAlgorithm targetAlgorithm, {
    bool isDecoy = false,
    Function(int current, int total, String currentFileName, int processedBytes,
            int totalBytes)?
        onProgress,
    Set<String>? fileFilter,
  }) =>
      _files.reEncryptVault(
        targetAlgorithm,
        isDecoy: isDecoy,
        onProgress: onProgress,
        fileFilter: fileFilter,
      );

  Future<int> encryptVaultFiles(
    EncryptionAlgorithm algorithm, {
    bool isDecoy = false,
    Function(int current, int total, String currentFileName, int processedBytes,
            int totalBytes)?
        onProgress,
    Set<String>? fileFilter,
  }) =>
      _files.encryptVaultFiles(
        algorithm,
        isDecoy: isDecoy,
        onProgress: onProgress,
        fileFilter: fileFilter,
      );

  Future<int> removeEncryption({
    bool isDecoy = false,
    Function(int current, int total, String currentFileName, int processedBytes,
            int totalBytes)?
        onProgress,
    Set<String>? fileFilter,
  }) =>
      _files.removeEncryption(
        isDecoy: isDecoy,
        onProgress: onProgress,
        fileFilter: fileFilter,
      );

  Future<void> cleanupTemp() => _files.cleanupTemp();

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
  }) =>
      _files.registerNoteEntry(
        noteId: noteId,
        title: title,
        encryptedContentPath: encryptedContentPath,
        fileExtension: fileExtension,
        isEncrypted: isEncrypted,
        encryptionAlgorithm: encryptionAlgorithm,
        kdfIterations: kdfIterations,
        folderId: folderId,
        isDecoy: isDecoy,
      );

  Future<void> removeNoteEntry(String noteId, {bool isDecoy = false}) =>
      _files.removeNoteEntry(noteId, isDecoy: isDecoy);

  Future<void> registerPasswordEntry({
    required String passwordId,
    required String title,
    required String encryptedContentPath,
    List<String> tags = const [],
    bool isEncrypted = false,
    EncryptionAlgorithm encryptionAlgorithm = EncryptionAlgorithm.aes256Gcm,
    int kdfIterations = 0,
    bool isDecoy = false,
  }) =>
      _files.registerPasswordEntry(
        passwordId: passwordId,
        title: title,
        encryptedContentPath: encryptedContentPath,
        tags: tags,
        isEncrypted: isEncrypted,
        encryptionAlgorithm: encryptionAlgorithm,
        kdfIterations: kdfIterations,
        isDecoy: isDecoy,
      );

  Future<void> removePasswordEntry(String passwordId, {bool isDecoy = false}) =>
      _files.removePasswordEntry(passwordId, isDecoy: isDecoy);

  // ---- Thumbnails ----

  Future<Uint8List?> getThumbnailBytes(VaultedFile file) =>
      _thumbnails.getThumbnailBytes(file);

  void clearThumbnailCache() => _thumbnails.clearCache();

  // ---- Albums ----

  Future<List<Album>> getAllAlbums() => _albums.getAllAlbums();

  Future<Album?> getAlbumById(String albumId) =>
      _albums.getAlbumById(albumId);

  Future<Album?> createAlbum({
    required String name,
    String? description,
    String? coverImageId,
  }) =>
      _albums.createAlbum(
        name: name,
        description: description,
        coverImageId: coverImageId,
      );

  Future<Album?> updateAlbum(Album updatedAlbum) =>
      _albums.updateAlbum(updatedAlbum);

  Future<bool> deleteAlbum(String albumId) => _albums.deleteAlbum(albumId);

  Future<bool> addFileToAlbum(String fileId, String albumId) =>
      _albums.addFileToAlbum(fileId, albumId);

  Future<bool> addFilesToAlbum(List<String> fileIds, String albumId) =>
      _albums.addFilesToAlbum(fileIds, albumId);

  Future<bool> removeFilesFromAlbum(List<String> fileIds, String albumId) =>
      _albums.removeFilesFromAlbum(fileIds, albumId);

  Future<bool> removeFileFromAlbum(String fileId, String albumId) =>
      _albums.removeFileFromAlbum(fileId, albumId);

  Future<List<VaultedFile>> getFilesInAlbum(String albumId) =>
      _albums.getFilesInAlbum(albumId);

  // ---- Folders ----

  Future<List<VaultFolder>> getAllFolders() => _folders.getAllFolders();

  Future<VaultFolder?> getFolderById(String folderId) =>
      _folders.getFolderById(folderId);

  Future<List<VaultFolder>> getRootFolders() => _folders.getRootFolders();

  Future<List<VaultFolder>> getSubfolders(String parentId) =>
      _folders.getSubfolders(parentId);

  Future<VaultFolder?> createFolder({
    required String name,
    String? parentId,
    String? description,
  }) =>
      _folders.createFolder(
        name: name,
        parentId: parentId,
        description: description,
      );

  Future<VaultFolder?> updateFolder(VaultFolder updatedFolder) =>
      _folders.updateFolder(updatedFolder);

  Future<bool> deleteFolder(String folderId, {bool deleteContents = false}) =>
      _folders.deleteFolder(folderId, deleteContents: deleteContents);

  Future<bool> addFileToFolder(String fileId, String folderId) =>
      _folders.addFileToFolder(fileId, folderId);

  Future<bool> removeFileFromFolder(String fileId, String folderId) =>
      _folders.removeFileFromFolder(fileId, folderId);

  Future<List<VaultedFile>> getFilesInFolder(String folderId) =>
      _folders.getFilesInFolder(folderId);

  Future<FolderImportResult> importDeviceFolder(
    String deviceFolderPath, {
    String? parentFolderId,
    bool recursive = true,
    bool deleteOriginals = false,
    bool encrypt = false,
    bool isDecoy = false,
    Function(int current, int total)? onProgress,
    Function(String fileName, int fileNumber, int total)? onFileProgress,
  }) =>
      _folders.importDeviceFolder(
        deviceFolderPath,
        parentFolderId: parentFolderId,
        recursive: recursive,
        deleteOriginals: deleteOriginals,
        encrypt: encrypt,
        isDecoy: isDecoy,
        onProgress: onProgress,
        onFileProgress: onFileProgress,
      );

  // ---- Tags ----

  Future<List<TagInfo>> getAllTags() => _tags.getAllTags();

  Future<List<VaultedFile>> getFilesByTag(String tag) =>
      _tags.getFilesByTag(tag);

  Future<VaultedFile?> addTagToFile(String fileId, String tag) =>
      _tags.addTagToFile(fileId, tag);

  Future<VaultedFile?> removeTagFromFile(String fileId, String tag) =>
      _tags.removeTagFromFile(fileId, tag);

  Future<TagInfo> createTag(String name, [int? colorValue]) =>
      _tags.createTag(name, colorValue);

  Future<bool> updateTagColor(String tagName, int colorValue) =>
      _tags.updateTagColor(tagName, colorValue);

  Future<bool> deleteTag(String tagName) => _tags.deleteTag(tagName);

  // ---- Favorites ----

  Future<VaultedFile?> toggleFavorite(String fileId) =>
      _tags.toggleFavorite(fileId);

  Future<List<VaultedFile>> getFavoriteFiles() => _tags.getFavoriteFiles();

  // ---- Sorting ----

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

  // ---- Search ----

  Future<List<VaultedFile>> searchFiles(String query) =>
      _search.searchFiles(query);

  Future<List<VaultedFile>> searchFilesAdvanced({
    String? query,
    List<String>? tags,
    VaultedFileType? type,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool? isFavorite,
    String? albumId,
  }) =>
      _search.searchFilesAdvanced(
        query: query,
        tags: tags,
        type: type,
        dateFrom: dateFrom,
        dateTo: dateTo,
        isFavorite: isFavorite,
        albumId: albumId,
      );

  // ---- Settings ----

  Future<VaultSettings> getSettings() => _settings.getSettings();

  Future<void> updateSettings(VaultSettings settings) =>
      _settings.updateSettings(settings);

  // ---- Stats ----

  Future<Map<VaultedFileType, int>> getFileCounts() => _stats.getFileCounts();

  Future<int> getTotalStorageUsed() => _stats.getTotalStorageUsed();

  // ---- Misc ----

  Future<void> clearVault({bool isDecoy = false}) async {
    try {
      await _store.wipe(isDecoy: isDecoy);
      clearThumbnailCache();
    } catch (e) {
      debugPrint('Error clearing vault: $e');
    }
  }

  Future<void> refresh() async {
    // ponytail: atomic swap — reload all caches before replacing them, so a
    // concurrent mutation never observes a null cache (was the NPE vector
    // flagged in Tier 4). Full mutation serialization deferred.
    final files = await _store.loadFileIndex(forceReload: true);
    final decoyFiles =
        await _store.loadFileIndex(isDecoy: true, forceReload: true);
    final albums = await _store.loadAlbums(forceReload: true);
    final folders = await _store.loadFolders(forceReload: true);
    final tags = await _store.loadTags(forceReload: true);
    _store.cachedFiles = files;
    _store.cachedDecoyFiles = decoyFiles;
    _store.cachedAlbums = albums;
    _store.cachedFolders = folders;
    _store.cachedTags = tags;
  }
}