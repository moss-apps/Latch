import '../models/album.dart';
import '../models/vault_folder.dart';
import '../models/vaulted_file.dart';

/// The vault-metadata surface both persistence backends expose
/// (docs/embedded_pocketbase.md P4.1). `VaultStore` (secure-storage JSON)
/// and `PocketBaseStore` (app-encrypted PB columns) implement it.
///
/// `VaultStore` stays the cache holder every domain service talks to; when a
/// PB delegate is attached it routes non-decoy load/save/wipe through it and
/// falls back to its legacy JSON path otherwise — that routing IS the
/// "PB preferred, legacy fallback" of P4.2. The decoy vault never starts the
/// sidecar, so decoy traffic always stays on VaultStore's legacy path (PB
/// implementations throw on `isDecoy: true`).
abstract class LocalStore {
  List<VaultedFile>? cachedFiles;
  List<Album>? cachedAlbums;
  List<VaultFolder>? cachedFolders;
  List<TagInfo>? cachedTags;

  Future<List<VaultedFile>> loadFileIndex({
    bool isDecoy = false,
    bool forceReload = false,
  });

  Future<void> saveFileIndex({bool isDecoy = false});

  Future<List<Album>> loadAlbums({bool forceReload = false});

  Future<void> saveAlbums();

  Future<List<VaultFolder>> loadFolders({bool forceReload = false});

  Future<void> saveFolders();

  Future<List<TagInfo>> loadTags({bool forceReload = false});

  Future<void> saveTags();

  Future<void> reloadAll();

  Future<void> wipe({bool isDecoy = false});
}
