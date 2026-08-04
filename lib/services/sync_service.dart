import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

import '../crypto/aes_gcm_cipher.dart';
import '../crypto/key_derivation.dart';
import '../models/remote_manifest.dart';
import '../models/sync_profile.dart';
import '../models/vaulted_file.dart';
import 'encryption_service.dart';
import 'remote/remote_store.dart';
import 'remote/webdav_store.dart';
import 'vault_store.dart';

/// Phase of an in-flight sync, surfaced to the UI via [SyncProgress].
enum SyncPhase { connecting, uploading, committing, done }

/// Coarse progress for the UI. [completed]/[total] are file counts.
class SyncProgress {
  final SyncPhase phase;
  final int completed;
  final int total;

  const SyncProgress({
    this.phase = SyncPhase.uploading,
    this.completed = 0,
    this.total = 0,
  });
}

/// Outcome of one [SyncService.runSync]. [refreshedLocal] is the local index
/// with pushed files' `remoteHash`/`modifiedAt` refreshed — the caller persists
/// it back into [VaultStore] so the next run skips unchanged files.
class SyncResult {
  final int blobsPushed;
  final int blobsDeleted;
  final int blobsPulled;
  final SyncPlan plan;
  final List<VaultedFile> refreshedLocal;
  final DateTime completedAt;

  const SyncResult({
    required this.blobsPushed,
    required this.blobsDeleted,
    required this.blobsPulled,
    required this.plan,
    required this.refreshedLocal,
    required this.completedAt,
  });

  bool get didAnything =>
      blobsPushed > 0 || blobsDeleted > 0 || blobsPulled > 0;
}

/// The result of diffing local vault state against a remote manifest.
class SyncPlan {
  /// Local files newer than (or absent from) the remote — upload these.
  final List<VaultedFile> toPush;

  /// Remote entries newer than local, or absent locally — download these.
  /// Populated only for two-way sync (Phase S3); push-only ignores it.
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

/// Vault sync. Pure diff/manifest logic lives as statics (tested directly);
/// [syncNow] is the Riverpod-constructed entrypoint that wires real I/O.
///
/// ponytail: NOT a singleton — constructed by `syncServiceProvider` with
/// [VaultStore] + [EncryptionService], matching the Phase 2 service style.
/// Per locked decision #5 this avoids a 13th `instance` singleton.
class SyncService {
  SyncService(this._store, this._crypto);

  final VaultStore _store;
  final EncryptionService _crypto;

  /// One-shot sync against [profile]'s WebDAV server. Reads the local index +
  /// master key, builds the transport, delegates to [runSync]. The caller
  /// persists [SyncResult.refreshedLocal] (the SyncProvider does this).
  Future<SyncResult> syncNow({
    required SyncProfile profile,
    required String password,
    required String deviceId,
    void Function(SyncProgress)? onProgress,
  }) async {
    final remote = WebDAVStore(
      baseUrl: profile.serverUrl,
      username: profile.username ?? '',
      password: password,
      basePath: profile.basePath,
    );
    final local = await _store.loadFileIndex();
    final masterKey = await _crypto.getMasterKey();
    return runSync(
      local: local,
      masterKey: masterKey,
      remote: remote,
      deviceId: deviceId,
      direction: profile.direction,
      onProgress: onProgress,
    );
  }

  /// Core push-only engine. Fetches + decrypts the remote manifest, reconciles,
  /// uploads new/changed blobs, reaps tombstones, then commits the encrypted
  /// manifest last (the commit point — a crash before this leaves the old
  /// manifest describing a consistent state, and the next run is idempotent).
  ///
  /// Pull execution (two-way restore) is Phase S3.1 — [plan.toPull] is computed
  /// but not imported yet. Throws if a non-deleted file's blob is unreadable;
  /// the caller treats that as a failed sync (content-addressed puts are
  /// idempotent, so a partial run is safe to retry).
  static Future<SyncResult> runSync({
    required List<VaultedFile> local,
    required Uint8List masterKey,
    required RemoteStore remote,
    required String deviceId,
    SyncDirection direction = SyncDirection.pushOnly,
    DateTime? now,
    void Function(SyncProgress)? onProgress,
  }) async {
    final completedAt = (now ?? DateTime.now()).toUtc();

    onProgress?.call(const SyncProgress(phase: SyncPhase.connecting));
    final remoteBytes = await remote.getManifest();
    final remoteManifest = remoteBytes == null
        ? null
        : decryptManifest(remoteBytes, masterKey);

    // First sync (no remote manifest) → everything non-deleted is a push.
    final plan = remoteManifest == null
        ? SyncPlan(
            toPush: local.where((f) => !f.syncedDeleted).toList(),
          )
        : reconcile(local: local, remote: remoteManifest);

    final pushIds = <String>{for (final p in plan.toPush) p.id};
    final refreshed = <VaultedFile>[];
    var pushed = 0;
    final total = local.where((f) => !f.syncedDeleted).length;
    var processed = 0;

    for (final f in local) {
      if (f.syncedDeleted) {
        refreshed.add(f);
        continue;
      }
      if (pushIds.contains(f.id)) {
        final blob = await File(f.vaultPath).readAsBytes();
        final hash = sha256Hex(blob);
        await remote.putBlob(blobNameFor(hash), blob);
        pushed++;
        refreshed.add(
          f.copyWith(
            remoteHash: hash,
            modifiedAt: f.modifiedAt ?? completedAt,
          ),
        );
      } else {
        refreshed.add(f);
      }
      processed++;
      onProgress?.call(SyncProgress(
        phase: SyncPhase.uploading,
        completed: processed,
        total: total,
      ));
    }

    for (final name in plan.toDelete) {
      await remote.deleteBlob(name);
    }

    // ponytail: pull import is S3.1; reconcile computed toPull, we don't act.

    onProgress?.call(const SyncProgress(phase: SyncPhase.committing));
    final manifest =
        buildManifest(refreshed, deviceId: deviceId, now: completedAt);
    await remote.putManifest(encryptManifest(manifest, masterKey));
    onProgress?.call(
        SyncProgress(phase: SyncPhase.done, completed: total, total: total));

    return SyncResult(
      blobsPushed: pushed,
      blobsDeleted: plan.toDelete.length,
      blobsPulled: 0,
      plan: plan,
      refreshedLocal: refreshed,
      completedAt: completedAt,
    );
  }

  // ---- Pure helpers (no I/O) ----

  /// Encrypted manifest blob name on the remote store.
  static const String manifestName = RemoteStore.manifestName;

  /// sha256 of [data] as a lowercase hex string.
  static String sha256Hex(Uint8List data) => sha256.convert(data).toString();

  /// Content-addressed, sharded blob name: `ab/cd/<hash>.enc`.
  /// Sharding keeps any one directory from bloating; the hash is the sha256 of
  /// the ciphertext, so identical ciphertext dedups to one blob.
  static String blobNameFor(String contentHashHex) {
    final padded = contentHashHex.length >= 4
        ? contentHashHex
        : contentHashHex.padLeft(4, '0');
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
