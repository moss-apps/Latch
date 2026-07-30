import 'dart:typed_data';

/// Dumb blob transport. The server sees opaque bytes only — no vault model
/// types cross this boundary. SyncService owns manifest encrypt/decrypt and
/// content-addressed naming; this interface just moves bytes by name.
///
/// ponytail: abstract only — the WebDAV implementation (webdav_client) lands in
/// Phase S0.2 impl along with its dependency. Until then this pins the contract
/// the pure SyncService logic and tests build against.
abstract class RemoteStore {
  /// Auth + reachability probe (Phase S0.5 self-check).
  Future<void> testConnection();

  /// Fetch the encrypted manifest blob, or null if none exists yet.
  Future<Uint8List?> getManifest();

  /// Overwrite the encrypted manifest blob.
  Future<void> putManifest(Uint8List bytes);

  /// Upload a content-addressed blob by name (see SyncService.blobNameFor).
  Future<void> putBlob(String name, Uint8List bytes);

  /// Fetch a blob by name, or null if absent.
  Future<Uint8List?> getBlob(String name);

  /// Delete a blob by name.
  Future<void> deleteBlob(String name);

  /// List all blob names (for garbage collection / reconciliation).
  Future<List<String>> listBlobs();
}
