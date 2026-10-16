import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../models/album.dart';
import '../models/deleted_vault_item.dart';
import '../models/vault_folder.dart';
import '../models/vault_settings.dart';
import '../models/vaulted_file.dart';
import 'local_store.dart';
import 'sync_state_store.dart';

/// Centralized vault state + persistence. Owns `_storage`, directories, the
/// `_cached*` maps and all `_load*`/`_save*` methods. Domain services depend
/// on this + `EncryptionService` via constructor.
///
/// single shared-state holder, centralization that made service extraction possible.
///
/// P4: when a PB delegate is attached (post-unlock, sidecar healthy), all
/// non-decoy loads/saves/wipes route through it first, falling back to the
/// legacy secure-storage JSON path on any PB failure. VaultStore's own
/// caches stay the single in-memory truth either way.
class VaultStore implements LocalStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions:
        IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device),
  );

  static const String vaultIndexKey = 'vault_file_index';
  static const String decoyIndexKey = 'vault_decoy_index';
  static const String albumsKey = 'vault_albums';
  static const String tagsKey = 'vault_tags';
  static const String settingsKey = 'vault_settings';
  static const String vaultFolderName = '.locker_vault';
  static const String decoyFolderName = '.locker_decoy';
  static const String foldersKey = 'vault_folders';
  static const String reEncryptJournalKey = 'reencrypt_journal';
  static String recentlyDeletedKey(bool isDecoy) =>
      isDecoy ? 'vault_recently_deleted_decoy' : 'vault_recently_deleted';

  Directory? vaultDirectory;
  Directory? decoyDirectory;

  @override
  List<VaultedFile>? cachedFiles;
  List<VaultedFile>? cachedDecoyFiles;
  @override
  List<Album>? cachedAlbums;
  @override
  List<VaultFolder>? cachedFolders;
  @override
  List<TagInfo>? cachedTags;
  VaultSettings? cachedSettings;

  /// PB persistence backend when active (P4.2). Null = legacy-only. Set by
  /// `VaultService.activatePocketBase` after the sidecar is up + unlocked.
  LocalStore? pbStore;

  /// True when the non-decoy cache was built without PB data (PB outage).
  /// Set before reconciling back to PB so PB-only rows aren't deleted.
  bool _nonDecoyDiverged = false;

  /// Read-only secure-storage handle (used by services for the re-encrypt
  /// journal, which lives outside the cached maps).
  Future<String?> read(String key) => _storage.read(key: key);

  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  Future<void> delete(String key) => _storage.delete(key: key);

  /// Strict parsing: corrupt recovery metadata must never become an empty list
  /// which a later delete could silently overwrite.
  Future<List<DeletedVaultItem>> loadDeletedItems(
      {bool isDecoy = false}) async {
    final raw = await read(recentlyDeletedKey(isDecoy));
    if (raw == null) return [];
    return (jsonDecode(raw) as List<dynamic>)
        .map((e) => DeletedVaultItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveDeletedItems(List<DeletedVaultItem> items,
          {bool isDecoy = false}) =>
      write(recentlyDeletedKey(isDecoy),
          jsonEncode(items.map((e) => e.toJson()).toList()));

  /// Receipts are authoritative even if a legacy/PB write was interrupted.
  Future<List<VaultedFile>> _visibleFiles(List<VaultedFile> files,
      {required bool isDecoy}) async {
    final receipts = {
      for (final e in await loadDeletedItems(isDecoy: isDecoy)) e.file.id: e
    };
    final visible = files.where((file) {
      final receipt = receipts[file.id];
      return receipt == null ||
          (receipt.stage == DeletionStage.restoring &&
              receipt.restoredFile?.vaultPath == file.vaultPath);
    }).toList();
    // A strict save may have fallen back to legacy while PB was unavailable.
    // Once a purge drops its receipt, don't display PB's stale, missing blob.
    if (!isDecoy) {
      final deleted = await SyncStateStore.deletions();
      if (deleted.isNotEmpty) {
        final stale = <String>{};
        for (final file in visible) {
          if (deleted.containsKey(file.id) &&
              !receipts.containsKey(file.id) &&
              !await File(file.vaultPath).exists()) {
            stale.add(file.id);
          }
        }
        visible.removeWhere((file) => stale.contains(file.id));
      }
    }
    return visible;
  }

  Future<List<Map<String, dynamic>>> visibleEditorRecords(
      List<Map<String, dynamic>> records, String metadataKey,
      {bool isDecoy = false}) async {
    final receipts = {
      for (final item in await loadDeletedItems(isDecoy: isDecoy))
        if (item.file.metadata?[metadataKey] != null)
          item.file.metadata![metadataKey]: item
    };
    return records.where((record) {
      final item = receipts[record['id']];
      return item == null ||
          (item.stage == DeletionStage.restoring &&
              item.restoredFile?.vaultPath == record['encryptedContentPath']);
    }).toList();
  }

  /// Ensure the vault directory (and its subdirs) exist.
  Future<Directory> ensureVaultDirectory() async {
    if (vaultDirectory != null && await vaultDirectory!.exists()) {
      await _ensureNoMediaFile(vaultDirectory!.path);
      return vaultDirectory!;
    }

    final appDir = await getApplicationDocumentsDirectory();
    vaultDirectory = Directory('${appDir.path}/$vaultFolderName');

    if (!await vaultDirectory!.exists()) {
      await vaultDirectory!.create(recursive: true);
    }

    await Directory('${vaultDirectory!.path}/images').create(recursive: true);
    await Directory('${vaultDirectory!.path}/videos').create(recursive: true);
    await Directory('${vaultDirectory!.path}/songs').create(recursive: true);
    await Directory('${vaultDirectory!.path}/documents')
        .create(recursive: true);
    await Directory('${vaultDirectory!.path}/thumbnails')
        .create(recursive: true);
    await Directory('${vaultDirectory!.path}/temp').create(recursive: true);

    await _ensureNoMediaFile(vaultDirectory!.path);

    return vaultDirectory!;
  }

  /// Ensure the decoy vault directory (and its subdirs) exist.
  Future<Directory> ensureDecoyDirectory() async {
    if (decoyDirectory != null && await decoyDirectory!.exists()) {
      await _ensureNoMediaFile(decoyDirectory!.path);
      return decoyDirectory!;
    }

    final appDir = await getApplicationDocumentsDirectory();
    decoyDirectory = Directory('${appDir.path}/$decoyFolderName');

    if (!await decoyDirectory!.exists()) {
      await decoyDirectory!.create(recursive: true);
    }

    await Directory('${decoyDirectory!.path}/images').create(recursive: true);
    await Directory('${decoyDirectory!.path}/videos').create(recursive: true);
    await Directory('${decoyDirectory!.path}/songs').create(recursive: true);
    await Directory('${decoyDirectory!.path}/documents')
        .create(recursive: true);

    await _ensureNoMediaFile(decoyDirectory!.path);

    return decoyDirectory!;
  }

  Future<void> _ensureNoMediaFile(String directoryPath) async {
    final noMediaFile = File('$directoryPath/.nomedia');
    if (!await noMediaFile.exists()) {
      await noMediaFile.create();
    }
  }

  /// Subdirectory name for a file type. Static so the sync pull path (which
  /// computes a destination before a VaultedFile exists) can reuse it without
  /// an instance — `getSubdirectory` delegates here.
  static String subdirFor(VaultedFileType type) {
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

  /// Get subdirectory path for file type.
  String getSubdirectory(VaultedFileType type) => subdirFor(type);

  // ---- Load / save primitive indexes ----

  @override
  Future<List<VaultedFile>> loadFileIndex({
    bool isDecoy = false,
    bool forceReload = false,
  }) async {
    if (!forceReload && !isDecoy && cachedFiles != null) {
      cachedFiles = await _visibleFiles(cachedFiles!, isDecoy: false);
      return cachedFiles!;
    }
    if (!forceReload && isDecoy && cachedDecoyFiles != null) {
      cachedDecoyFiles = await _visibleFiles(cachedDecoyFiles!, isDecoy: true);
      return cachedDecoyFiles!;
    }

    if (!isDecoy && pbStore != null) {
      List<VaultedFile>? pbFiles;
      try {
        pbFiles = await pbStore!.loadFileIndex(forceReload: forceReload);
      } catch (e) {
        debugPrint('[PB] loadFileIndex failed, falling back to legacy: $e');
      }
      if (pbFiles != null) {
        final visible = await _visibleFiles(pbFiles, isDecoy: false);
        final legacy = await _visibleFiles(
            await _readLegacyFileIndex(isDecoy: false),
            isDecoy: false);
        cachedFiles = await _mergeRecoveryFallbacks(visible, legacy,
            includeLegacyOnly: _nonDecoyDiverged);
        if (jsonEncode(pbFiles.map((f) => f.toJson()).toList()) !=
            jsonEncode(cachedFiles!.map((f) => f.toJson()).toList())) {
          _nonDecoyDiverged = true;
        }
        return cachedFiles!;
      }
      // PB unreachable: cache-first merge so entries written to legacy
      // during an earlier outage stay visible instead of being replaced.
      _nonDecoyDiverged = true;
      final legacy = await _readLegacyFileIndex(isDecoy: false);
      cachedFiles = await _visibleFiles(
          mergeFileLists(cachedFiles ?? const [], legacy),
          isDecoy: false);
      return cachedFiles!;
    }

    final files = await _visibleFiles(
        await _readLegacyFileIndex(isDecoy: isDecoy),
        isDecoy: isDecoy);
    if (isDecoy) {
      cachedDecoyFiles = files;
      return cachedDecoyFiles!;
    }
    cachedFiles = files;
    return cachedFiles!;
  }

  /// Parse the legacy secure-storage JSON index. Rewrites the key when some
  /// entries failed to parse (recovery). Returns [] on missing/corrupt data.
  Future<List<VaultedFile>> _readLegacyFileIndex({
    required bool isDecoy,
  }) async {
    try {
      final key = isDecoy ? decoyIndexKey : vaultIndexKey;
      final indexJson = await _storage.read(key: key);
      if (indexJson == null || indexJson.isEmpty) {
        return [];
      }

      final List<dynamic> jsonList = jsonDecode(indexJson);
      final files = <VaultedFile>[];
      for (int i = 0; i < jsonList.length; i++) {
        try {
          files.add(
            VaultedFile.fromJson(jsonList[i] as Map<String, dynamic>),
          );
        } catch (e) {
          debugPrint('Error parsing vault entry $i: $e');
        }
      }

      if (files.length < jsonList.length) {
        debugPrint(
          'Vault index: recovered ${files.length}/${jsonList.length} entries',
        );
        await _storage.write(
          key: key,
          value: jsonEncode(files.map((f) => f.toJson()).toList()),
        );
      }

      return files;
    } catch (e) {
      debugPrint('Error loading vault index: $e');
      return [];
    }
  }

  /// Union by id. First occurrence (base) wins; extras with unseen ids are
  /// appended in order. Never drops entries from either side.
  static List<VaultedFile> mergeFileLists(
    List<VaultedFile> base,
    List<VaultedFile> extra,
  ) {
    if (extra.isEmpty) return List.of(base);
    final ids = base.map((f) => f.id).toSet();
    return [...base, ...extra.where((f) => !ids.contains(f.id))];
  }

  /// An offline restore deliberately moves the payload to a unique path. A
  /// recovered PB reader must not replace that record with its old, missing
  /// path. This is recovery evidence, not timestamp-based conflict resolution:
  /// a live PB payload always wins and unrelated same-id edits are untouched.
  Future<List<VaultedFile>> _mergeRecoveryFallbacks(
      List<VaultedFile> pbFiles, List<VaultedFile> legacy,
      {bool includeLegacyOnly = false}) async {
    final merged = List<VaultedFile>.of(pbFiles);
    final positions = {for (var i = 0; i < merged.length; i++) merged[i].id: i};
    for (final file in legacy) {
      final restoredAt = file.metadata?['restoredAt'];
      final explicitRestore =
          restoredAt is String && DateTime.tryParse(restoredAt) != null;
      final position = positions[file.id];
      if (position == null) {
        if ((includeLegacyOnly || explicitRestore) &&
            await File(file.vaultPath).exists()) {
          positions[file.id] = merged.length;
          merged.add(file);
        }
      } else if (explicitRestore &&
          merged[position].vaultPath != file.vaultPath &&
          await File(file.vaultPath).exists() &&
          !await File(merged[position].vaultPath).exists()) {
        merged[position] = file;
      }
    }
    return merged;
  }

  /// Pull PB rows the cache is missing (outage survivors with their blob
  /// still on disk) back into the cache before a reconciling save, so
  /// reconcile doesn't delete them.
  Future<void> _healDivergedCache({Set<String> removedIds = const {}}) async {
    try {
      final pbFiles = await _visibleFiles(
          await pbStore!.loadFileIndex(forceReload: true),
          isDecoy: false);
      final cacheIds = (cachedFiles ?? const []).map((f) => f.id).toSet();
      final missing = <VaultedFile>[];
      for (final f in pbFiles) {
        if (removedIds.contains(f.id)) continue;
        if (cacheIds.contains(f.id)) continue;
        if (!await File(f.vaultPath).exists()) continue;
        missing.add(f);
      }
      if (missing.isNotEmpty) {
        cachedFiles = mergeFileLists(cachedFiles ?? const [], missing);
        debugPrint('[PB] healed ${missing.length} PB-only entries into cache');
      }
      _nonDecoyDiverged = false;
    } catch (e) {
      debugPrint('[PB] divergence heal failed: $e');
    }
  }

  /// After PB attach: resurrect legacy-only entries (written while PB was
  /// down in an earlier session) whose blobs still exist, and push the
  /// merged index to PB so both backends converge. Best-effort, non-fatal.
  Future<void> healLegacyDivergence() async {
    if (pbStore == null) return;
    try {
      final rawPbFiles = await pbStore!.loadFileIndex(forceReload: true);
      final pbFiles = await _visibleFiles(rawPbFiles, isDecoy: false);
      final legacy = await _visibleFiles(
          await _readLegacyFileIndex(isDecoy: false),
          isDecoy: false);
      final merged = await _mergeRecoveryFallbacks(pbFiles, legacy,
          includeLegacyOnly: true);
      _nonDecoyDiverged = false;
      if (jsonEncode(rawPbFiles.map((f) => f.toJson()).toList()) ==
          jsonEncode(merged.map((f) => f.toJson()).toList())) {
        return;
      }

      cachedFiles = merged;
      pbStore!.cachedFiles = merged;
      await pbStore!.saveFileIndex();
      await _writeLegacyFileIndex(
          files: merged, isDecoy: false, strict: true, allowEmpty: true);
      debugPrint('[PB] reconciled legacy recovery records and stale PB rows');
    } catch (e) {
      _nonDecoyDiverged = true;
      debugPrint('[PB] healLegacyDivergence failed: $e');
    }
  }

  @override
  Future<void> saveFileIndex(
      {bool isDecoy = false,
      bool strict = false,
      bool allowEmpty = false,
      Set<String> removedIds = const {}}) async {
    if (isDecoy) {
      cachedDecoyFiles =
          await _visibleFiles(cachedDecoyFiles ?? [], isDecoy: true);
    } else {
      cachedFiles = await _visibleFiles(cachedFiles ?? [], isDecoy: false);
    }
    if (!isDecoy && pbStore != null) {
      if (_nonDecoyDiverged) {
        await _healDivergedCache(removedIds: removedIds);
      }
      pbStore!.cachedFiles = cachedFiles ?? const [];
      try {
        await pbStore!.saveFileIndex();
        if (strict) {
          await _writeLegacyFileIndex(
              files: cachedFiles ?? const [],
              isDecoy: false,
              strict: true,
              allowEmpty: allowEmpty,
              removedIds: removedIds);
        }
        return;
      } catch (e) {
        debugPrint('[PB] saveFileIndex failed, falling back to legacy: $e');
        _nonDecoyDiverged = true;
        await _writeLegacyFileIndex(
          files: cachedFiles ?? const [],
          isDecoy: false,
          unionWithLegacy: true,
          strict: strict,
          allowEmpty: allowEmpty,
          removedIds: removedIds,
        );
        return;
      }
    }
    await _writeLegacyFileIndex(
      files: (isDecoy ? cachedDecoyFiles : cachedFiles) ?? const [],
      isDecoy: isDecoy,
      strict: strict,
      allowEmpty: allowEmpty,
      removedIds: removedIds,
    );
  }

  /// Write the legacy secure-storage JSON index. `unionWithLegacy` (PB
  /// outage fallback) keeps legacy-only entries alive instead of clobbering
  /// them with a cache snapshot PB never received — only when their blob
  /// still exists on disk (deletes must shrink).
  Future<void> _writeLegacyFileIndex({
    required List<VaultedFile> files,
    required bool isDecoy,
    bool unionWithLegacy = false,
    bool strict = false,
    bool allowEmpty = false,
    Set<String> removedIds = const {},
  }) async {
    try {
      var toWrite = files;
      final key = isDecoy ? decoyIndexKey : vaultIndexKey;

      if (unionWithLegacy) {
        final legacy = await _visibleFiles(
            await _readLegacyFileIndex(isDecoy: isDecoy),
            isDecoy: isDecoy);
        final fileIds = files.map((f) => f.id).toSet();
        final survivors = <VaultedFile>[];
        for (final f in legacy) {
          if (removedIds.contains(f.id)) continue;
          if (fileIds.contains(f.id)) continue;
          if (!await File(f.vaultPath).exists()) continue;
          survivors.add(f);
        }
        if (survivors.isNotEmpty) {
          toWrite = mergeFileLists(files, survivors);
        }
      }

      final jsonList = toWrite.map((file) => file.toJson()).toList();

      if (jsonList.isEmpty && !allowEmpty) {
        final existing = await _storage.read(key: key);
        if (existing != null && existing.isNotEmpty) {
          final existingCount = (jsonDecode(existing) as List<dynamic>).length;
          if (existingCount > 0) {
            debugPrint(
              'WARNING: Attempted to save empty index over $existingCount existing entries. Aborting save.',
            );
            return;
          }
        }
      }

      await _storage.write(key: key, value: jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error saving vault index: $e');
      if (strict) rethrow;
    }
  }

  @override
  Future<List<Album>> loadAlbums({bool forceReload = false}) async {
    if (!forceReload && cachedAlbums != null) return cachedAlbums!;

    if (pbStore != null) {
      try {
        cachedAlbums = await pbStore!.loadAlbums(forceReload: forceReload);
        return cachedAlbums!;
      } catch (e) {
        debugPrint('[PB] loadAlbums failed, falling back to legacy: $e');
      }
    }

    try {
      final albumsJson = await _storage.read(key: albumsKey);
      if (albumsJson == null || albumsJson.isEmpty) {
        cachedAlbums = createDefaultAlbums();
        await saveAlbums();
        return cachedAlbums!;
      }

      final List<dynamic> jsonList = jsonDecode(albumsJson);
      cachedAlbums = jsonList
          .map((json) => Album.fromJson(json as Map<String, dynamic>))
          .toList();

      return cachedAlbums!;
    } catch (e) {
      debugPrint('Error loading albums: $e');
      cachedAlbums = createDefaultAlbums();
      return cachedAlbums!;
    }
  }

  /// Static so PocketBaseStore (which is not a VaultStore) can reuse the
  /// same defaults.
  static List<Album> createDefaultAlbums() {
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

  @override
  Future<void> saveAlbums() async {
    if (pbStore != null) {
      pbStore!.cachedAlbums = cachedAlbums ?? const [];
      try {
        await pbStore!.saveAlbums();
        return;
      } catch (e) {
        debugPrint('[PB] saveAlbums failed, falling back to legacy: $e');
      }
    }
    try {
      final jsonList = cachedAlbums?.map((a) => a.toJson()).toList() ?? [];
      await _storage.write(key: albumsKey, value: jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error saving albums: $e');
    }
  }

  @override
  Future<List<VaultFolder>> loadFolders({bool forceReload = false}) async {
    if (!forceReload && cachedFolders != null) return cachedFolders!;

    if (pbStore != null) {
      try {
        cachedFolders = await pbStore!.loadFolders(forceReload: forceReload);
        return cachedFolders!;
      } catch (e) {
        debugPrint('[PB] loadFolders failed, falling back to legacy: $e');
      }
    }

    try {
      final foldersJson = await _storage.read(key: foldersKey);
      if (foldersJson == null || foldersJson.isEmpty) {
        cachedFolders = [];
        return cachedFolders!;
      }

      final List<dynamic> jsonList = jsonDecode(foldersJson);
      cachedFolders = jsonList
          .map((json) => VaultFolder.fromJson(json as Map<String, dynamic>))
          .toList();

      return cachedFolders!;
    } catch (e) {
      debugPrint('Error loading folders: $e');
      cachedFolders = [];
      return cachedFolders!;
    }
  }

  @override
  Future<void> saveFolders() async {
    if (pbStore != null) {
      pbStore!.cachedFolders = cachedFolders ?? const [];
      try {
        await pbStore!.saveFolders();
        return;
      } catch (e) {
        debugPrint('[PB] saveFolders failed, falling back to legacy: $e');
      }
    }
    try {
      final jsonList = cachedFolders?.map((f) => f.toJson()).toList() ?? [];
      await _storage.write(key: foldersKey, value: jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error saving folders: $e');
    }
  }

  @override
  Future<List<TagInfo>> loadTags({bool forceReload = false}) async {
    if (!forceReload && cachedTags != null) return cachedTags!;

    if (pbStore != null) {
      try {
        cachedTags = await pbStore!.loadTags(forceReload: forceReload);
        return cachedTags!;
      } catch (e) {
        debugPrint('[PB] loadTags failed, falling back to legacy: $e');
      }
    }

    try {
      final tagsJson = await _storage.read(key: tagsKey);
      if (tagsJson == null || tagsJson.isEmpty) {
        cachedTags = [];
        return cachedTags!;
      }

      final List<dynamic> jsonList = jsonDecode(tagsJson);
      cachedTags = jsonList
          .map((json) => TagInfo.fromJson(json as Map<String, dynamic>))
          .toList();

      return cachedTags!;
    } catch (e) {
      debugPrint('Error loading tags: $e');
      cachedTags = [];
      return cachedTags!;
    }
  }

  @override
  Future<void> saveTags() async {
    if (pbStore != null) {
      pbStore!.cachedTags = cachedTags ?? const [];
      try {
        await pbStore!.saveTags();
        return;
      } catch (e) {
        debugPrint('[PB] saveTags failed, falling back to legacy: $e');
      }
    }
    try {
      final jsonList = cachedTags?.map((t) => t.toJson()).toList() ?? [];
      await _storage.write(key: tagsKey, value: jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error saving tags: $e');
    }
  }

  Future<VaultSettings> loadSettings() async {
    if (cachedSettings != null) return cachedSettings!;

    try {
      final settingsJson = await _storage.read(key: settingsKey);
      if (settingsJson == null || settingsJson.isEmpty) {
        cachedSettings = const VaultSettings();
        return cachedSettings!;
      }

      cachedSettings = VaultSettings.fromJson(
        jsonDecode(settingsJson) as Map<String, dynamic>,
      );
      return cachedSettings!;
    } catch (e) {
      debugPrint('Error loading settings: $e');
      cachedSettings = const VaultSettings();
      return cachedSettings!;
    }
  }

  Future<void> saveSettings() async {
    try {
      await _storage.write(
        key: settingsKey,
        value: jsonEncode(cachedSettings?.toJson() ?? {}),
      );
    } catch (e) {
      debugPrint('Error saving settings: $e');
    }
  }

  // ---- File-system helpers (stateless) ----

  /// Stream copy a file in chunks (memory-efficient for large files).
  Future<void> streamCopyFile(
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

  Future<void> deleteFileIfExists(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<int> getFileSizeIfExists(String path) async {
    try {
      return await File(path).length();
    } catch (_) {
      return 0;
    }
  }

  /// Generate a unique encrypted filename.
  String generateVaultFilename(String originalName) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomBytes = utf8.encode('$originalName$timestamp${DateTime.now()}');
    final hash = sha256.convert(randomBytes).toString().substring(0, 16);

    final extension =
        originalName.contains('.') ? originalName.split('.').last : '';

    return extension.isNotEmpty ? '$hash.$extension' : hash;
  }

  /// Reload every cache atomically (used by `refresh()` in VaultService).
  @override
  Future<void> reloadAll() async {
    final files = await loadFileIndex(forceReload: true);
    final decoyFiles = await loadFileIndex(isDecoy: true, forceReload: true);
    final albums = await loadAlbums(forceReload: true);
    final folders = await loadFolders(forceReload: true);
    final tags = await loadTags(forceReload: true);
    cachedFiles = files;
    cachedDecoyFiles = decoyFiles;
    cachedAlbums = albums;
    cachedFolders = folders;
    cachedTags = tags;
  }

  /// Wipe caches + storage for a vault (used by `clearVault()` in VaultService).
  /// PB rows are wiped too when active — else a cleared vault would
  /// resurrect from PB on the next load.
  @override
  Future<void> wipe({bool isDecoy = false}) async {
    if (!isDecoy && pbStore != null) {
      try {
        await pbStore!.wipe();
      } catch (e) {
        debugPrint('[PB] wipe failed: $e');
      }
    }
    final appDir = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${appDir.path}/${isDecoy ? decoyFolderName : vaultFolderName}',
    );

    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }

    await delete(recentlyDeletedKey(isDecoy));

    if (isDecoy) {
      cachedDecoyFiles = [];
      await _storage.delete(key: decoyIndexKey);
      decoyDirectory = null;
    } else {
      cachedFiles = [];
      _nonDecoyDiverged = false;
      cachedAlbums = null;
      cachedFolders = null;
      cachedTags = null;
      await _storage.delete(key: vaultIndexKey);
      await _storage.delete(key: albumsKey);
      await _storage.delete(key: foldersKey);
      await _storage.delete(key: tagsKey);
      vaultDirectory = null;
    }
  }
}
