import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../models/album.dart';
import '../models/vault_folder.dart';
import '../models/vault_settings.dart';
import '../models/vaulted_file.dart';

/// Centralized vault state + persistence. Owns `_storage`, directories, the
/// `_cached*` maps and all `_load*`/`_save*` methods. Domain services depend
/// on this + `EncryptionService` via constructor.
///
/// ponytail: single shared-state holder. The original VaultService had every
/// cache read inline across all seams — no service could be extracted
/// cleanly without centralizing state first. This is that centralization.
class VaultStore {
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

  Directory? vaultDirectory;
  Directory? decoyDirectory;

  List<VaultedFile>? cachedFiles;
  List<VaultedFile>? cachedDecoyFiles;
  List<Album>? cachedAlbums;
  List<VaultFolder>? cachedFolders;
  List<TagInfo>? cachedTags;
  VaultSettings? cachedSettings;

  /// Read-only secure-storage handle (used by services for the re-encrypt
  /// journal, which lives outside the cached maps).
  Future<String?> read(String key) => _storage.read(key: key);

  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  Future<void> delete(String key) => _storage.delete(key: key);

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

  /// Get subdirectory path for file type.
  String getSubdirectory(VaultedFileType type) {
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

  // ---- Load / save primitive indexes ----

  Future<List<VaultedFile>> loadFileIndex({
    bool isDecoy = false,
    bool forceReload = false,
  }) async {
    if (!forceReload && !isDecoy && cachedFiles != null) {
      return cachedFiles!;
    }
    if (!forceReload && isDecoy && cachedDecoyFiles != null) {
      return cachedDecoyFiles!;
    }

    try {
      final key = isDecoy ? decoyIndexKey : vaultIndexKey;
      final indexJson = await _storage.read(key: key);
      if (indexJson == null || indexJson.isEmpty) {
        if (isDecoy) {
          cachedDecoyFiles = [];
          return cachedDecoyFiles!;
        }
        cachedFiles = [];
        return cachedFiles!;
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

      if (isDecoy) {
        cachedDecoyFiles = files;
        return cachedDecoyFiles!;
      }
      cachedFiles = files;
      return cachedFiles!;
    } catch (e) {
      debugPrint('Error loading vault index: $e');
      if (isDecoy) {
        cachedDecoyFiles = [];
        return cachedDecoyFiles!;
      }
      cachedFiles = [];
      return cachedFiles!;
    }
  }

  Future<void> saveFileIndex({bool isDecoy = false}) async {
    try {
      final files = isDecoy ? cachedDecoyFiles : cachedFiles;
      final key = isDecoy ? decoyIndexKey : vaultIndexKey;
      final jsonList = files?.map((file) => file.toJson()).toList() ?? [];

      if (jsonList.isEmpty) {
        final existing = await _storage.read(key: key);
        if (existing != null && existing.isNotEmpty) {
          final existingCount =
              (jsonDecode(existing) as List<dynamic>).length;
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
    }
  }

  Future<List<Album>> loadAlbums({bool forceReload = false}) async {
    if (!forceReload && cachedAlbums != null) return cachedAlbums!;

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

  List<Album> createDefaultAlbums() {
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

  Future<void> saveAlbums() async {
    try {
      final jsonList = cachedAlbums?.map((a) => a.toJson()).toList() ?? [];
      await _storage.write(key: albumsKey, value: jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error saving albums: $e');
    }
  }

  Future<List<VaultFolder>> loadFolders({bool forceReload = false}) async {
    if (!forceReload && cachedFolders != null) return cachedFolders!;

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

  Future<void> saveFolders() async {
    try {
      final jsonList = cachedFolders?.map((f) => f.toJson()).toList() ?? [];
      await _storage.write(key: foldersKey, value: jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error saving folders: $e');
    }
  }

  Future<List<TagInfo>> loadTags({bool forceReload = false}) async {
    if (!forceReload && cachedTags != null) return cachedTags!;

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

  Future<void> saveTags() async {
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
  Future<void> wipe({bool isDecoy = false}) async {
    final appDir = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${appDir.path}/${isDecoy ? decoyFolderName : vaultFolderName}',
    );

    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }

    if (isDecoy) {
      cachedDecoyFiles = [];
      await _storage.delete(key: decoyIndexKey);
      decoyDirectory = null;
    } else {
      cachedFiles = [];
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