import 'package:flutter/foundation.dart';

import '../../models/album.dart';
import '../../models/vault_folder.dart';
import '../../models/vaulted_file.dart';
import '../local_store.dart';
import '../vault_store.dart';
import 'daos/album_dao.dart';
import 'daos/folder_dao.dart';
import 'daos/tag_dao.dart';
import 'daos/vault_file_dao.dart';
import 'pb_client.dart';

/// PB-backed metadata store exposing the same load/save surface as
/// `VaultStore` (files / albums / folders / tags + cached maps) via
/// `LocalStore`. Non-decoy vault only — the decoy vault never starts the
/// sidecar, so `isDecoy: true` is a routing bug and throws. Settings stay in
/// FlutterSecureStorage.
class PocketBaseStore implements LocalStore {
  PocketBaseStore({required PbClient client, required Uint8List masterKey})
      : fileDao = VaultFileDao(client, masterKey),
        albumDao = AlbumDao(client, masterKey),
        folderDao = FolderDao(client, masterKey),
        tagDao = TagDao(client, masterKey);

  final VaultFileDao fileDao;
  final AlbumDao albumDao;
  final FolderDao folderDao;
  final TagDao tagDao;

  @override
  List<VaultedFile>? cachedFiles;
  @override
  List<Album>? cachedAlbums;
  @override
  List<VaultFolder>? cachedFolders;
  @override
  List<TagInfo>? cachedTags;

  void _noDecoy(bool isDecoy) {
    if (isDecoy) {
      throw ArgumentError('decoy vault never starts the PocketBase sidecar');
    }
  }

  @override
  Future<List<VaultedFile>> loadFileIndex({
    bool isDecoy = false,
    bool forceReload = false,
  }) async {
    _noDecoy(isDecoy);
    if (!forceReload && cachedFiles != null) return cachedFiles!;
    cachedFiles = await fileDao.list();
    return cachedFiles!;
  }

  @override
  Future<void> saveFileIndex({bool isDecoy = false}) async {
    _noDecoy(isDecoy);
    final files = cachedFiles ?? const <VaultedFile>[];
    // Same data-loss guard as VaultStore: never save an empty index over
    // existing rows via reconcile (reconcile([]) would wipe them).
    if (files.isEmpty) {
      final rows = await fileDao.list();
      if (rows.isNotEmpty) {
        debugPrint(
          'WARNING: Attempted to save empty PB index over ${rows.length} '
          'existing entries. Aborting save.',
        );
        return;
      }
    }
    await fileDao.reconcile(files);
  }

  @override
  Future<List<Album>> loadAlbums({bool forceReload = false}) async {
    if (!forceReload && cachedAlbums != null) return cachedAlbums!;
    cachedAlbums = await albumDao.list();
    if (cachedAlbums!.isEmpty) {
      cachedAlbums = VaultStore.createDefaultAlbums();
      await saveAlbums();
    }
    return cachedAlbums!;
  }

  @override
  Future<void> saveAlbums() => albumDao.reconcile(cachedAlbums ?? const []);

  @override
  Future<List<VaultFolder>> loadFolders({bool forceReload = false}) async {
    if (!forceReload && cachedFolders != null) return cachedFolders!;
    cachedFolders = await folderDao.list();
    return cachedFolders!;
  }

  @override
  Future<void> saveFolders() => folderDao.reconcile(cachedFolders ?? const []);

  @override
  Future<List<TagInfo>> loadTags({bool forceReload = false}) async {
    if (!forceReload && cachedTags != null) return cachedTags!;
    cachedTags = await tagDao.list();
    return cachedTags!;
  }

  @override
  Future<void> saveTags() => tagDao.reconcile(cachedTags ?? const []);

  /// Force-reload every cache (mirrors `VaultStore.reloadAll`).
  @override
  Future<void> reloadAll() async {
    cachedFiles = await loadFileIndex(forceReload: true);
    cachedAlbums = await loadAlbums(forceReload: true);
    cachedFolders = await loadFolders(forceReload: true);
    cachedTags = await loadTags(forceReload: true);
  }

  /// Clear every PB row + cache (`clearVault` routes here when PB is
  /// active — lingering rows would resurrect a wiped vault on next load).
  /// Deliberately bypasses the saveFileIndex empty-guard.
  @override
  Future<void> wipe({bool isDecoy = false}) async {
    _noDecoy(isDecoy);
    cachedFiles = null;
    cachedAlbums = null;
    cachedFolders = null;
    cachedTags = null;
    await fileDao.reconcile(const []);
    await albumDao.reconcile(const []);
    await folderDao.reconcile(const []);
    await tagDao.reconcile(const []);
  }
}
