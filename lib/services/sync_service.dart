import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

import '../crypto/aes_gcm_cipher.dart';
import '../crypto/key_derivation.dart';
import '../models/encryption_algorithm.dart';
import '../models/remote_manifest.dart';
import '../models/sync_profile.dart';
import '../models/vaulted_file.dart';
import 'encryption_service.dart';
import 'remote/remote_store.dart';
import 'remote/webdav_store.dart';
import 'vault_store.dart';

/// Phase of an in-flight sync, surfaced to the UI via [SyncProgress].
enum SyncPhase { connecting, uploading, downloading, committing, done }

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
  final int blobsSkipped;
  final SyncPlan plan;
  final List<VaultedFile> refreshedLocal;
  final DateTime completedAt;

  const SyncResult({
    required this.blobsPushed,
    required this.blobsDeleted,
    required this.blobsPulled,
    this.blobsSkipped = 0,
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

  /// Live local ids where both sides changed since the last sync. Last-write-
  /// wins still resolves the outcome; this is surfaced as a UI note only.
  /// only local-newer conflicts; remote-newer needs local hashing — three-way merge is a non-goal.
  final List<String> conflicts;

  /// Live local ids a remote tombstone should delete (two-way only, LWW: the
  /// tombstone must be at least as new as the local copy).
  final List<String> toTombstoneLocal;

  const SyncPlan({
    this.toPush = const [],
    this.toPull = const [],
    this.toDelete = const [],
    this.conflicts = const [],
    this.toTombstoneLocal = const [],
  });

  bool get isEmpty =>
      toPush.isEmpty &&
      toPull.isEmpty &&
      toDelete.isEmpty &&
      conflicts.isEmpty &&
      toTombstoneLocal.isEmpty;
}

/// Vault sync. Pure diff/manifest logic lives as statics (tested directly);
/// [syncNow] is the Riverpod-constructed entrypoint that wires real I/O.
///
/// not a singleton — provider-constructed (locked decision #5).
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
  }) async {
    final remote = WebDAVStore(
      baseUrl: profile.serverUrl,
      username: profile.username ?? '',
      password: password,
      basePath: profile.basePath,
    );
    final local = await _store.loadFileIndex();
    // Ensure the vault dir + subdirs exist before a two-way pull writes into it.
    final dir = await _store.ensureVaultDirectory();
    final masterKey = await _crypto.getMasterKey();
    // Isolate.run keeps file+hash I/O off the UI thread; per-file progress dropped (SendPort if needed).
    return Isolate.run(() => runSync(
      local: local,
      masterKey: masterKey,
      remote: remote,
      deviceId: deviceId,
      vaultRoot: dir.path,
      direction: profile.direction,
    ));
  }

  /// Core sync engine. Fetches + decrypts the remote manifest, reconciles,
  /// then for two-way sync: uploads new/changed blobs, downloads missing/
  /// changed blobs, reaps tombstoned remote blobs, applies remote tombstones
  /// locally, and finally commits the encrypted manifest last (the commit
  /// point — a crash before this leaves the old manifest describing a
  /// consistent state, and the next run is idempotent).
  ///
  /// Push-only (`direction == pushOnly`, the default) skips the pull and
  /// local-tombstone phases: it is backup only. [vaultRoot] is the local vault
  /// directory root; required for two-way pull (where downloaded blobs are
  /// written). Throws if a blob to pull is missing or its sha256 does not match
  /// the GCM-authenticated manifest — the caller treats that as a failed sync.
  /// Content-addressed puts/deletes are idempotent, so a partial run is safe to
  /// retry (the manifest write is the single commit point).
  static Future<SyncResult> runSync({
    required List<VaultedFile> local,
    required Uint8List masterKey,
    required RemoteStore remote,
    required String deviceId,
    String? vaultRoot,
    SyncDirection direction = SyncDirection.pushOnly,
    DateTime? now,
    void Function(SyncProgress)? onProgress,
  }) async {
    final completedAt = (now ?? DateTime.now()).toUtc();
    final twoWay = direction == SyncDirection.twoWay;

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
    final tombstoneLocalIds = <String>{for (final id in plan.toTombstoneLocal) id};
    final refreshed = <VaultedFile>[];
    var pushed = 0;
    var skipped = 0;
    final totalPush = local.where((f) => !f.syncedDeleted).length;
    var processed = 0;

    // ---- PUSH phase: upload new/changed local blobs ----
    for (final f in local) {
      if (f.syncedDeleted) {
        refreshed.add(f);
        continue;
      }
      if (pushIds.contains(f.id)) {
        final file = File(f.vaultPath);
        if (await file.exists()) {
          final blob = await file.readAsBytes();
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
          // skip missing on-disk blobs; never silently mutate the index. Root cause tracked separately.
          skipped++;
          refreshed.add(f);
        }
      } else {
        refreshed.add(f);
      }
      processed++;
      onProgress?.call(SyncProgress(
        phase: SyncPhase.uploading,
        completed: processed,
        total: totalPush,
      ));
    }

    // ---- REMOTE-BLOB DELETE phase: reap tombstoned remote blobs ----
    for (final name in plan.toDelete) {
      await remote.deleteBlob(name);
    }

    var pulled = 0;

    // ---- PULL phase (two-way only) ----
    // manifest GCM + sha256 match makes decrypt-to-verify redundant; blobs are always our own.
    if (twoWay && vaultRoot != null && plan.toPull.isNotEmpty) {
      final totalPull = plan.toPull.length;
      var done = 0;
      for (final e in plan.toPull) {
        final hash = e.contentHash;
        if (hash == null) {
          throw StateError('Remote entry ${e.id} has no content hash');
        }
        final blob = await remote.getBlob(blobNameFor(hash));
        if (blob == null) {
          throw StateError('Missing blob for remote entry ${e.id}');
        }
        if (sha256Hex(blob) != hash) {
          // Blob does not match the authenticated manifest → tamper/corruption.
          throw StateError('Blob hash mismatch for remote entry ${e.id}');
        }
        final vp = _localVaultPath(vaultRoot: vaultRoot, entry: e);
        await File(vp).parent.create(recursive: true);
        await File(vp).writeAsBytes(blob);
        final existingIdx = refreshed.indexWhere((f) => f.id == e.id);
        if (existingIdx >= 0) {
          final old = refreshed[existingIdx];
          if (old.vaultPath != vp) {
            await _deleteIfExists(old.vaultPath);
          }
          refreshed[existingIdx] = _vaultedFileFromEntry(e, vaultPath: vp);
        } else {
          refreshed.add(_vaultedFileFromEntry(e, vaultPath: vp));
        }
        pulled++;
        done++;
        onProgress?.call(SyncProgress(
          phase: SyncPhase.downloading,
          completed: done,
          total: totalPull,
        ));
      }
    }

    // ---- LOCAL TOMBSTONE phase: remote delete → local (two-way only) ----
    if (twoWay && tombstoneLocalIds.isNotEmpty) {
      for (var i = 0; i < refreshed.length; i++) {
        final f = refreshed[i];
        if (tombstoneLocalIds.contains(f.id) && !f.syncedDeleted) {
          await _deleteIfExists(f.vaultPath);
          refreshed[i] = f.copyWith(
            syncedDeleted: true,
            remoteHash: null,
            modifiedAt: completedAt,
          );
        }
      }
    }

    // ---- COMMIT manifest (single commit point) ----
    onProgress?.call(const SyncProgress(phase: SyncPhase.committing));
    final manifest =
        buildManifest(refreshed, deviceId: deviceId, now: completedAt);
    await remote.putManifest(encryptManifest(manifest, masterKey));
    final grandTotal = totalPush + pulled;
    onProgress?.call(SyncProgress(
      phase: SyncPhase.done,
      completed: grandTotal,
      total: grandTotal,
    ));

    return SyncResult(
      blobsPushed: pushed,
      blobsDeleted: plan.toDelete.length,
      blobsPulled: pulled,
      blobsSkipped: skipped,
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
  /// for tombstones keep their last hash so the blob can be reaped. v2 carries
  /// the full restore metadata (S3) so a fresh device can reconstruct files.
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
            originalName: f.originalName,
            type: f.type.name,
            mimeType: f.mimeType,
            fileSize: f.fileSize,
            dateAdded: f.dateAdded,
            dateModified: f.dateModified,
            isEncrypted: f.isEncrypted,
            encryptionIv: f.encryptionIv,
            encryptionAlgorithm: f.encryptionAlgorithm?.name,
            keyDerivationSalt: f.keyDerivationSalt,
            kdfIterations: f.kdfIterations,
            tags: f.tags,
            isFavorite: f.isFavorite,
            albumIds: f.albumIds,
            folderId: f.folderId,
          ),
        )
        .toList(growable: false);
    return RemoteManifest(
      version: 2,
      deviceId: deviceId,
      generatedAt: generated,
      entries: entries,
    );
  }

  /// Diff local files against the remote manifest → a [SyncPlan].
  /// Convergence is last-write-wins by modifiedAt; local/remote null
  /// modifiedAt falls back to dateModified then dateAdded.
  ///
  /// Tombstone policy: a local tombstone reaps a still-live remote blob
  /// (existing S2 semantics). A remote tombstone deletes the local copy, but
  /// only when it is at least as new as the local file (LWW) — a strictly newer
  /// local copy resurrects via push instead. ponytail ceiling: the local→remote
  /// reap is unconditional, so a delete-then-edit race can lose the resurrected
  /// edit; symmetric three-way tombstone LWW is deferred.
  static SyncPlan reconcile({
    required List<VaultedFile> local,
    required RemoteManifest remote,
  }) {
    final remoteById = {for (final e in remote.entries) e.id: e};
    final localIds = {for (final f in local) f.id};
    final toPush = <VaultedFile>[];
    final toPull = <ManifestEntry>[];
    final toDelete = <String>[];
    final conflicts = <String>[];
    final toTombstoneLocal = <String>[];

    for (final f in local) {
      final r = remoteById[f.id];
      if (f.syncedDeleted) {
        // Local tombstone → reap the remote blob if it's still live there.
        if (r != null && !r.deleted && r.contentHash != null) {
          toDelete.add(blobNameFor(r.contentHash!));
        }
        continue;
      }
      if (r == null) {
        toPush.add(f);
        continue;
      }
      if (r.deleted) {
        // Remote tombstone: propagate delete locally (LWW), else resurrect.
        final localM = f.modifiedAt ?? f.dateModified ?? f.dateAdded;
        if (!r.modifiedAt.isBefore(localM)) {
          toTombstoneLocal.add(f.id);
        } else {
          toPush.add(f);
        }
        continue;
      }
      // Both sides live.
      final localM = f.modifiedAt ?? f.dateModified ?? f.dateAdded;
      final remoteChanged =
          f.remoteHash != null && f.remoteHash != r.contentHash;
      if (localM.isAfter(r.modifiedAt)) {
        toPush.add(f);
        if (remoteChanged) {
          // Local newer AND remote diverged since last sync → both changed.
          conflicts.add(f.id);
        }
      } else if (r.modifiedAt.isAfter(localM)) {
        toPull.add(r);
      } else if (f.remoteHash != r.contentHash) {
        // Equal timestamps, different content → deterministic tiebreak: pull.
        toPull.add(r);
      }
    }

    // Remote files unknown locally → pull (two-way).
    for (final e in remote.entries) {
      if (!e.deleted && !localIds.contains(e.id)) {
        toPull.add(e);
      }
    }

    return SyncPlan(
      toPush: toPush,
      toPull: toPull,
      toDelete: toDelete,
      conflicts: conflicts,
      toTombstoneLocal: toTombstoneLocal,
    );
  }

  /// Destination vault path for a pulled blob. subdir by type (mirrors
  /// VaultStore), filename derived from the content hash (deterministic +
  /// dedup-friendly) with the original extension preserved.
  static String _localVaultPath({
    required String vaultRoot,
    required ManifestEntry entry,
  }) {
    final type = _typeFromName(entry.type);
    final subdir = VaultStore.subdirFor(type);
    final hash = entry.contentHash ?? entry.id;
    final stem = hash.length >= 16 ? hash.substring(0, 16) : hash;
    final ext = _extOf(entry.originalName);
    final name = ext.isEmpty ? '$stem.enc' : '$stem.$ext';
    return '$vaultRoot/$subdir/$name';
  }

  /// Reconstruct a [VaultedFile] from a manifest entry at [vaultPath]. The
  /// inverse of [buildManifest]'s per-file mapping.
  static VaultedFile _vaultedFileFromEntry(
    ManifestEntry e, {
    required String vaultPath,
  }) {
    return VaultedFile(
      id: e.id,
      originalName: e.originalName ?? 'file',
      vaultPath: vaultPath,
      type: _typeFromName(e.type),
      mimeType: e.mimeType ?? 'application/octet-stream',
      fileSize: e.fileSize ?? 0,
      dateAdded: e.dateAdded ?? e.modifiedAt,
      dateModified: e.dateModified,
      isEncrypted: e.isEncrypted,
      encryptionIv: e.encryptionIv,
      encryptionAlgorithm: _algoFromName(e.encryptionAlgorithm),
      keyDerivationSalt: e.keyDerivationSalt,
      kdfIterations: e.kdfIterations,
      tags: e.tags,
      isFavorite: e.isFavorite,
      albumIds: e.albumIds,
      folderId: e.folderId,
      modifiedAt: e.modifiedAt,
      remoteHash: e.contentHash,
    );
  }

  static VaultedFileType _typeFromName(String? name) {
    if (name == null) return VaultedFileType.other;
    return VaultedFileType.values.firstWhere(
      (t) => t.name == name,
      orElse: () => VaultedFileType.other,
    );
  }

  static EncryptionAlgorithm? _algoFromName(String? name) {
    if (name == null) return null;
    return EncryptionAlgorithm.values.firstWhere(
      (a) => a.name == name,
      orElse: () => EncryptionAlgorithm.aes256Ctr,
    );
  }

  static String _extOf(String? originalName) {
    if (originalName == null) return '';
    final dot = originalName.lastIndexOf('.');
    if (dot <= 0 || dot == originalName.length - 1) return '';
    return originalName.substring(dot + 1).toLowerCase();
  }

  static Future<void> _deleteIfExists(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
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
