import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../vault_store.dart';
import 'pocketbase_store.dart';

const _migrationFlagKey = 'pb_legacy_index_migrated';

/// One-time import of the FlutterSecureStorage JSON indexes into PB
/// (docs/embedded_pocketbase.md P3.4). Guarded by a secure-storage flag; the
/// legacy store is retained as fallback, never deleted. Upsert-only — a
/// reset flag combined with existing PB rows must not wipe PB.
///
/// Returns true if a migration ran.
Future<bool> migrateLegacyIndex(
  PocketBaseStore store, {
  FlutterSecureStorage? storage,
}) async {
  final s =
      storage ?? const FlutterSecureStorage(aOptions: AndroidOptions());
  if (await s.read(key: _migrationFlagKey) != null) return false;

  final legacy = VaultStore();
  final files = await legacy.loadFileIndex(forceReload: true);
  final albums = await legacy.loadAlbums(forceReload: true);
  final folders = await legacy.loadFolders(forceReload: true);
  final tags = await legacy.loadTags(forceReload: true);

  for (final f in files) {
    await store.fileDao.put(f);
  }
  for (final a in albums) {
    await store.albumDao.put(a);
  }
  for (final f in folders) {
    await store.folderDao.put(f);
  }
  for (final t in tags) {
    await store.tagDao.put(t);
  }

  store.cachedFiles = files;
  store.cachedAlbums = albums;
  store.cachedFolders = folders;
  store.cachedTags = tags;

  await s.write(
    key: _migrationFlagKey,
    value: DateTime.now().toIso8601String(),
  );
  return true;
}
