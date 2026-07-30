import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

import '../crypto/aes_gcm_cipher.dart';
import '../crypto/key_derivation.dart';
import '../models/remote_manifest.dart';
import '../models/vaulted_file.dart';

/// The result of diffing local vault state against a remote manifest.
class SyncPlan {
  /// Local files newer than (or absent from) the remote — upload these.
  final List<VaultedFile> toPush;

  /// Remote entries newer than local, or absent locally — download these.
  /// Empty in push-only v1; populated by the two-way path in Phase S3.
  final List<ManifestEntry> toPull;

  /// Content-addressed blob names to delete (tombstoned files).
  final List<String> toDelete;

  const SyncPlan({
    this.toPush = const [],
    this.toPull = const [],
    this.toDelete = const [],
  });

  bool get isEmpty => toPush.isEmpty && toPull.isEmpty && toDelete.isEmpty;
}

/// Pure sync logic. Stateless helpers — no I/O, no Riverpod, no network.
///
/// ponytail: the stateful orchestration (runSync, connectivity guard,
/// VaultStore + EncryptionService injection) lands Riverpod-native after the
/// Phase 4 refactor; these pure pieces are callable from there and tested now.
class SyncService {
  SyncService._();

  /// Encrypted manifest blob name on the remote store.
  static const String manifestName = 'manifest.enc';

  /// sha256 of [data] as a lowercase hex string.
  static String sha256Hex(Uint8List data) => sha256.convert(data).toString();

  /// Content-addressed, sharded blob name: `ab/cd/<hash>.enc`.
  /// Sharding keeps any one directory from bloating; the hash is the sha256 of
  /// the ciphertext, so identical ciphertext dedups to one blob.
  static String blobNameFor(String contentHashHex) {
    final padded =
        contentHashHex.length >= 4 ? contentHashHex : contentHashHex.padLeft(4, '0');
    final a = padded.substring(0, 2);
    final b = padded.substring(2, 4);
    return '$a/$b/$contentHashHex.enc';
  }

  /// Snapshot the current synced state of [files] into a manifest. Only files
  /// that carry a [VaultedFile.remoteHash] reference an uploaded blob; entries
  /// for tombstones keep their last hash so the blob can be reaped.
  static RemoteManifest buildManifest(
    List<VaultedFile> files, {
    required String deviceId,
    DateTime? now,
  }) {
    final generated = (now ?? DateTime.now()).toUtc();
    final entries = files
        .map(
          (f) => ManifestEntry(
            id: f.id,
            contentHash: f.remoteHash,
            modifiedAt: f.modifiedAt ?? f.dateModified ?? f.dateAdded,
            deleted: f.syncedDeleted,
          ),
        )
        .toList(growable: false);
    return RemoteManifest(
      version: 1,
      deviceId: deviceId,
      generatedAt: generated,
      entries: entries,
    );
  }

  /// Diff local files against the remote manifest → a [SyncPlan].
  /// Convergence is last-write-wins by modifiedAt; local/remote null
  /// modifiedAt falls back to dateModified then dateAdded.
  static SyncPlan reconcile({
    required List<VaultedFile> local,
    required RemoteManifest remote,
  }) {
    final remoteById = {for (final e in remote.entries) e.id: e};
    final localIds = {for (final f in local) f.id};
    final toPush = <VaultedFile>[];
    final toPull = <ManifestEntry>[];
    final toDelete = <String>[];

    for (final f in local) {
      final r = remoteById[f.id];
      if (f.syncedDeleted) {
        if (r != null && !r.deleted && r.contentHash != null) {
          toDelete.add(blobNameFor(r.contentHash!));
        }
        continue;
      }
      if (r == null || r.deleted) {
        toPush.add(f);
      } else {
        final localM = f.modifiedAt ?? f.dateModified ?? f.dateAdded;
        if (localM.isAfter(r.modifiedAt)) {
          toPush.add(f);
        } else if (r.modifiedAt.isAfter(localM)) {
          toPull.add(r);
        }
      }
    }

    // Remote files unknown locally (two-way pull). Skipped in push-only v1.
    for (final e in remote.entries) {
      if (!e.deleted && !localIds.contains(e.id)) {
        toPull.add(e);
      }
    }

    return SyncPlan(toPush: toPush, toPull: toPull, toDelete: toDelete);
  }

  /// Encrypt a manifest with the vault master key. Wire format:
  /// `[16-byte IV][ciphertext+GCM tag]`. Reuses AesGcmCipher — no new crypto.
  static Uint8List encryptManifest(RemoteManifest manifest, Uint8List masterKey) {
    final iv = KeyDerivation.generateIV();
    final ct = AesGcmCipher.process(
      masterKey,
      iv,
      Uint8List.fromList(utf8.encode(manifest.toJsonString())),
      true,
    );
    return Uint8List.fromList([...iv, ...ct]);
  }

  /// Decrypt a manifest blob. Throws [InvalidCipherTextException] if the GCM
  /// auth tag does not verify — callers MUST treat that as tampering/forgery.
  static RemoteManifest decryptManifest(Uint8List bytes, Uint8List masterKey) {
    if (bytes.length < 17) {
      throw const FormatException('Manifest blob too short');
    }
    final iv = Uint8List.fromList(bytes.sublist(0, 16));
    final ct = Uint8List.fromList(bytes.sublist(16));
    final pt = AesGcmCipher.process(masterKey, iv, ct, false);
    return RemoteManifest.fromJsonString(utf8.decode(pt));
  }
}
