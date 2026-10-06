import 'dart:typed_data';
import 'dart:io';

import '../sync_control.dart';

class RemoteManifestSnapshot {
  const RemoteManifestSnapshot(this.bytes, this.revision);
  final Uint8List? bytes;
  final String? revision;
}

class RemoteRevisionChanged implements Exception {}
class UnsafeRemotePublication implements Exception {
  UnsafeRemotePublication([this.reason = 'missing-dav-capability']);
  final String reason;
}

abstract class StreamingRemoteStore {
  Future<RemoteManifestSnapshot> readManifest(SyncControl control);
  Future<void> publishManifest(Uint8List bytes, String? revision, SyncControl control);
  Future<bool> verifyBlob(String name, String hash, SyncControl control);
  Future<int?> blobLength(String name, SyncControl control);
  Future<void> uploadFile(String name, File file, String hash, SyncControl control,
      void Function(int, int) progress);
  Future<bool> downloadFile(String name, File destination, SyncControl control,
      void Function(int, int) progress);
}

/// Dumb blob transport. The server sees opaque bytes only — no vault model
/// types cross this boundary. SyncService owns manifest encrypt/decrypt and
/// content-addressed naming; this interface just moves bytes by name.
///
/// interface-only contract for pure SyncService logic + tests.
abstract class RemoteStore {
  /// Encrypted manifest blob name on the remote store.
  static const String manifestName = 'manifest.enc';

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
