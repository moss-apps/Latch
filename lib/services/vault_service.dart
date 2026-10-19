import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/album.dart';
import '../models/encryption_algorithm.dart';
import '../models/file_to_vault.dart';
import '../models/vault_file_filter.dart';
import '../models/vault_folder.dart';
import '../models/vault_settings.dart';
import '../models/vaulted_file.dart';
import 'album_service.dart';
import 'crypto_isolate_pool.dart';
import 'encryption_service.dart';
import 'file_service.dart';
import 'file_operation_gate.dart';
import 'folder_service.dart';
import 'note_service.dart';
import 'password_service.dart';
import 'recently_deleted_service.dart';
import 'pb/migrate_legacy_index.dart';
import 'pb/pocketbase_runtime.dart';
import 'pb/pocketbase_store.dart';
import 'search_service.dart';
import 'settings_service.dart';
import 'smart_collection_service.dart';
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
/// pure facade — logic lives in the split services; this forwards.
class VaultService {
  @visibleForTesting
  VaultService();
  static final VaultService instance = VaultService();

  late final VaultStore _store = VaultStore();
  late final EncryptionService _encryptionService = EncryptionService.instance;

  /// The shared vault state holder. Exposed so Riverpod-constructed services
  /// (e.g. SyncService) can share the same caches without a new singleton.
  VaultStore get store => _store;

  // late back-ref breaks the File↔Thumbnail construction cycle (runtime-only calls).
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
  RecentlyDeletedService get recentlyDeleted => _files.recentlyDeleted;

  // Wire late back-edges once everything's constructed. Tests hit this via
  // the implicit first call to any forwarded method.
  bool _wired = false;
  void _wire() {
    if (_wired) return;
    _thumbnails.fileService = _files;
    _files.updateTagUsage = _tags.updateTagUsage;
    _files.removeFileFromAlbumFn = _albums.removeFileFromAlbum;
    _files.recentlyDeleted.onChanged = clearEditorCaches;
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
    final generation = _encryptionService.cacheGeneration;
    final client = PocketBaseRuntime.instance.client;
    if (client == null) return;
    final masterKey = await _encryptionService.getMasterKey();
    final pb = PocketBaseStore(
        client: client,
        masterKey: masterKey,
        isSessionValid: () => _encryptionService.isCurrentSession(generation));
    await migrateLegacyIndex(pb);
    if (!_encryptionService.isCurrentSession(generation)) return;
    _store.pbStore = pb;
    // Resurrect legacy-only entries (written while the sidecar was down in
    // an earlier session) before PB becomes the load source — otherwise
    // they'd never surface again.
    await _store.healLegacyDivergence();
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

  Future<T> _mutate<T>(Future<T> Function() task, T blockedResult,
          {Set<String> fileIds = const {}}) =>
      FileOperationGate.instance
          .mutate(task, blockedResult: blockedResult, fileIds: fileIds);

  Future<VaultedFile?> addFile({
    required String sourcePath,
    required String originalName,
    required VaultedFileType type,
    required String mimeType,
    bool deleteOriginal = false,
    bool? encrypt,
    bool isDecoy = false,
    List<String>? tags,
    List<String>? albumIds,
    EncryptionAlgorithm? encryptionAlgorithm,
    int? kdfIterations,
  }) =>
      _mutate(
          () => _files.addFile(
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
              ),
          null);

  Future<List<VaultedFile>> addFiles({
    required List<FileToVault> files,
    bool deleteOriginals = false,
    bool? encrypt,
    bool isDecoy = false,
    Function(int current, int total)? onProgress,
    Function(FileProgressInfo)? onFileProgress,
  }) =>
      _mutate(
          () => _files.addFiles(
                files: files,
                deleteOriginals: deleteOriginals,
                encrypt: encrypt,
                isDecoy: isDecoy,
                onProgress: onProgress,
                onFileProgress: onFileProgress,
              ),
          const <VaultedFile>[]);

  Future<VaultedFile?> updateFile(VaultedFile updatedFile) =>
      // Metadata-only: updateFile rewrites the index, not the vault payload.
      // Reserving the id here would make a viewer's concurrent read return
      // null, e.g. when marking a video viewed right after a swipe.
      _mutate(() => _files.updateFile(updatedFile), null);

  Future<String> hashFile(String path) => FileService.hashFile(path);

  Future<String?> contentHashFor(VaultedFile file, {bool isDecoy = false}) =>
      _files.contentHashFor(file, isDecoy: isDecoy);

  Future<bool> removeFile(String fileId, {bool isDecoy = false}) =>
      _mutate(() => _files.removeFile(fileId, isDecoy: isDecoy), false,
          fileIds: {fileId});

  Future<BulkDeleteResult> removeFiles(
    List<String> fileIds, {
    bool isDecoy = false,
    void Function(int current, int total,
            {int currentSize, int totalSize, String? currentFileName})?
        onProgress,
  }) =>
      _mutate(
          () => _files.removeFiles(
                fileIds,
                isDecoy: isDecoy,
                onProgress: onProgress,
              ),
          BulkDeleteResult(removed: const [], failed: List.of(fileIds)),
          fileIds: fileIds.toSet());

  void clearEditorCaches() {
    NoteService.instance.clearCache();
    PasswordService.instance.clearCache();
    clearThumbnailCache();
  }

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

  Future<Uint8List?> getDecryptedFileData(String fileId,
          {bool isDecoy = false}) =>
      _files.getDecryptedFileData(fileId, isDecoy: isDecoy);

  // Export reads the vault payload and writes outside it, so it must not
  // reserve the source id against concurrent viewers.
  Future<File?> exportFile(
    String fileId,
    String destinationPath, {
    bool isDecoy = false,
    Function(int processed, int total)? onProgress,
  }) =>
      _mutate(
          () => _files.exportFile(
                fileId,
                destinationPath,
                isDecoy: isDecoy,
                onProgress: onProgress,
              ),
          null);

  Future<int> reEncryptVault(
    EncryptionAlgorithm targetAlgorithm, {
    bool isDecoy = false,
    Function(int current, int total, String currentFileName, int processedBytes,
            int totalBytes)?
        onProgress,
    Set<String>? fileFilter,
  }) =>
      _mutate(
          () => _files.reEncryptVault(
                targetAlgorithm,
                isDecoy: isDecoy,
                onProgress: onProgress,
                fileFilter: fileFilter,
              ),
          -1,
          fileIds: fileFilter ?? const {});

  Future<int> encryptVaultFiles(
    EncryptionAlgorithm algorithm, {
    bool isDecoy = false,
    Function(int current, int total, String currentFileName, int processedBytes,
            int totalBytes)?
        onProgress,
    Set<String>? fileFilter,
  }) =>
      _mutate(
          () => _files.encryptVaultFiles(
                algorithm,
                isDecoy: isDecoy,
                onProgress: onProgress,
                fileFilter: fileFilter,
              ),
          -1,
          fileIds: fileFilter ?? const {});

  Future<int> removeEncryption({
    bool isDecoy = false,
    Function(int current, int total, String currentFileName, int processedBytes,
            int totalBytes)?
        onProgress,
    Set<String>? fileFilter,
  }) =>
      _mutate(
          () => _files.removeEncryption(
                isDecoy: isDecoy,
                onProgress: onProgress,
                fileFilter: fileFilter,
              ),
          -1,
          fileIds: fileFilter ?? const {});

  Future<void> cleanupTemp({bool throwOnError = false}) =>
      _files.cleanupTemp(throwOnError: throwOnError);

  void detachSessionStore() {
    _store.pbStore = null;
    clearThumbnailCache();
  }

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

  Future<Album?> getAlbumById(String albumId) => _albums.getAlbumById(albumId);

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
      _mutate(() => _albums.updateAlbum(updatedAlbum), null);

  Future<bool> deleteAlbum(String albumId) =>
      _mutate(() => _albums.deleteAlbum(albumId), false);

  Future<bool> addFileToAlbum(String fileId, String albumId) =>
      _mutate(() => _albums.addFileToAlbum(fileId, albumId), false,
          fileIds: {fileId});

  Future<bool> addFilesToAlbum(List<String> fileIds, String albumId) =>
      _mutate(() => _albums.addFilesToAlbum(fileIds, albumId), false,
          fileIds: fileIds.toSet());

  Future<bool> removeFilesFromAlbum(List<String> fileIds, String albumId) =>
      _mutate(() => _albums.removeFilesFromAlbum(fileIds, albumId), false,
          fileIds: fileIds.toSet());

  Future<bool> removeFileFromAlbum(String fileId, String albumId) =>
      _mutate(() => _albums.removeFileFromAlbum(fileId, albumId), false,
          fileIds: {fileId});

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
      _mutate(() => _folders.updateFolder(updatedFolder), null);

  Future<bool> deleteFolder(String folderId, {bool deleteContents = false}) =>
      _mutate(
          () => _folders.deleteFolder(folderId, deleteContents: deleteContents),
          false);

  Future<bool> addFileToFolder(String fileId, String folderId) =>
      _mutate(() => _folders.addFileToFolder(fileId, folderId), false,
          fileIds: {fileId});

  Future<bool> removeFileFromFolder(String fileId, String folderId) =>
      _mutate(() => _folders.removeFileFromFolder(fileId, folderId), false,
          fileIds: {fileId});

  Future<List<VaultedFile>> getFilesInFolder(String folderId) =>
      _folders.getFilesInFolder(folderId);

  Future<FolderImportResult> importDeviceFolder(
    String deviceFolderPath, {
    String? parentFolderId,
    bool recursive = true,
    bool deleteOriginals = false,
    bool? encrypt,
    bool isDecoy = false,
    Function(int current, int total)? onProgress,
    Function(String fileName, int fileNumber, int total)? onFileProgress,
  }) =>
      _mutate(
          () => _folders.importDeviceFolder(
                deviceFolderPath,
                parentFolderId: parentFolderId,
                recursive: recursive,
                deleteOriginals: deleteOriginals,
                encrypt: encrypt,
                isDecoy: isDecoy,
                onProgress: onProgress,
                onFileProgress: onFileProgress,
              ),
          const FolderImportResult(
              foldersCreated: 0,
              filesImported: 0,
              errors: ['Another file operation is already running']));

  // ---- Tags ----

  Future<List<TagInfo>> getAllTags() => _tags.getAllTags();

  Future<List<VaultedFile>> getFilesByTag(String tag) =>
      _tags.getFilesByTag(tag);

  Future<List<VaultedFile>> getUntaggedFiles() => _tags.getUntaggedFiles();

  // Tag and favorite edits rewrite index metadata only. Reserving the payload
  // id would block a viewer that is decrypting the same file.
  Future<VaultedFile?> addTagToFile(String fileId, String tag) =>
      _mutate(() => _tags.addTagToFile(fileId, tag), null);

  Future<VaultedFile?> removeTagFromFile(String fileId, String tag) =>
      _mutate(() => _tags.removeTagFromFile(fileId, tag), null);

  Future<TagInfo> createTag(String name, [int? colorValue]) =>
      _tags.createTag(name, colorValue);

  Future<bool> updateTagColor(String tagName, int colorValue) =>
      _tags.updateTagColor(tagName, colorValue);

  Future<bool> deleteTag(String tagName) =>
      _mutate(() => _tags.deleteTag(tagName), false);

  // ---- Favorites ----

  Future<VaultedFile?> toggleFavorite(String fileId) =>
      _mutate(() => _tags.toggleFavorite(fileId), null);

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

  Future<List<VaultedFile>> searchWithFilter(
    VaultFileFilter filter, {
    bool isDecoy = false,
  }) =>
      _search.searchWithFilter(filter, isDecoy: isDecoy);

  Future<List<VaultedFile>> searchFilesAdvanced({
    String? query,
    List<String>? tags,
    VaultedFileType? type,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool? isFavorite,
    String? albumId,
    bool isDecoy = false,
  }) =>
      _search.searchFilesAdvanced(
        query: query,
        tags: tags,
        type: type,
        dateFrom: dateFrom,
        dateTo: dateTo,
        isFavorite: isFavorite,
        albumId: albumId,
        isDecoy: isDecoy,
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
      await SmartCollectionService.instance.clear(isDecoy: isDecoy);
      clearThumbnailCache();
    } catch (e) {
      debugPrint('Error clearing vault: $e');
    }
  }

  Future<void> refresh() async {
    // atomic swap — reload before replace, so caches are never observably null.
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
