import 'dart:convert';
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
import '../models/sync_conflict.dart';
import 'encryption_service.dart';
import 'sync_engine.dart';
import 'sync_control.dart';
import 'sync_state_store.dart';
import 'sensitive_isolate.dart';
import 'remote/remote_store.dart';
import 'remote/webdav_store.dart';
import 'vault_store.dart';
import 'diagnostics.dart';

/// Phase of an in-flight sync, surfaced to the UI via [SyncProgress].
enum SyncPhase { connecting, hashing, uploading, downloading, committing, done }

/// File and byte progress; -1 means the server did not provide a byte total.
class SyncProgress {
  final SyncPhase phase;
  final int completed;
  final int total;
  final String? filename;
  final int fileBytes;
  final int fileTotal;
  final int transferredBytes;
  final int totalBytes;

  const SyncProgress({
    this.phase = SyncPhase.uploading,
    this.completed = 0,
    this.total = 0,
    this.filename,
    this.fileBytes = 0,
    this.fileTotal = -1,
    this.transferredBytes = 0,
    this.totalBytes = -1,
  });
}

/// Apply this result with [SyncService.complete] before reporting success.
class SyncResult {
  final int blobsPushed;
  final int blobsDeleted;
  final int blobsPulled;
  final int blobsSkipped;
  final int blobsReused;
  final int filesDeleted;
  final List<VaultedFile> originalLocal;
  final SyncCheckpoint checkpoint;
  final SyncPlan plan;
  final List<VaultedFile> refreshedLocal;
  final DateTime completedAt;

  const SyncResult({
    required this.blobsPushed,
    required this.blobsDeleted,
    required this.blobsPulled,
    this.blobsSkipped = 0,
    this.blobsReused = 0,
    this.filesDeleted = 0,
    this.originalLocal = const [],
    this.checkpoint = const SyncCheckpoint(),
    required this.plan,
    required this.refreshedLocal,
    required this.completedAt,
  });

  bool get didAnything =>
      blobsPushed > 0 ||
      blobsDeleted > 0 ||
      blobsPulled > 0 ||
      filesDeleted > 0;
}

/// The result of diffing local vault state against a remote manifest.
class SyncPlan {
  /// Local versions selected for publication.
  final List<VaultedFile> toPush;

  /// Remote versions selected for download.
  final List<ManifestEntry> toPull;

  /// Logical deletions. Phase 3 retains the payloads for recovery.
  final List<String> toDelete;

  /// IDs awaiting review; neither version is replaced automatically.
  final List<String> conflicts;

  /// IDs removed from the local index after the manifest is committed.
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
    void Function(SyncProgress)? onProgress,
    SyncControl? control,
  }) async {
    final cancellation = control ?? SyncControl();
    cancellation.check();
    final generation = _crypto.cacheGeneration;
    final remote = WebDAVStore(
      baseUrl: profile.serverUrl,
      username: profile.username ?? '',
      password: password,
      basePath: profile.basePath,
    );
    // Ensure the vault dir + subdirs exist before a two-way pull writes into it.
    final dir = await _store.ensureVaultDirectory();
    final masterKey = await _crypto.getMasterKey();
    if (!_crypto.isCurrentSession(generation)) {
      throw StateError('Vault session expired');
    }
    final stateStore = SyncStateStore(dir.path, masterKey);
    final target = SyncStateStore.targetId(profile);
    final journal = await stateStore.read(target, journal: true);
    if (journal != null) {
      cancellation.check();
      final published = (await remote.readManifest(cancellation)).bytes;
      if (published != null &&
          sha256Hex(published) == journal['manifestHash']) {
        final original = (journal['original'] as List)
            .map((f) => VaultedFile.fromJson(f as Map<String, dynamic>))
            .toList();
        final refreshed = (journal['refreshed'] as List)
            .map((f) => VaultedFile.fromJson(f as Map<String, dynamic>))
            .toList();
        await _apply(refreshed, original,
            (journal['removed'] as List).cast<String>(), generation);
        await stateStore.save(
            target, journal['checkpoint'] as Map<String, dynamic>);
        await stateStore.clearJournal(target);
        Diagnostics.event('sync.recovered', {});
      }
    }
    final local = List<VaultedFile>.of(await _store.loadFileIndex());
    final checkpoint = await stateStore.load(target);
    final deletions = await SyncStateStore.deletions();
    if (!_crypto.isCurrentSession(generation)) {
      throw StateError('Vault session expired');
    }
    cancellation.check();
    final direction = profile.direction;
    final workerRemote = WebDAVStore(
        baseUrl: profile.serverUrl,
        username: profile.username ?? '',
        password: password,
        basePath: profile.basePath);
    return _startWorker(local, masterKey, workerRemote, deviceId, dir.path,
        direction, checkpoint, deletions, target, onProgress, cancellation);
  }

  static Future<SyncResult> _startWorker(
      List<VaultedFile> local,
      Uint8List key,
      RemoteStore remote,
      String deviceId,
      String root,
      SyncDirection direction,
      SyncCheckpoint checkpoint,
      Map<String, DateTime> deletions,
      String target,
      void Function(SyncProgress)? onProgress,
      SyncControl? control) {
    return SensitiveIsolate.runWithEvents(
        _workerTask(local, key, remote, deviceId, root, direction, checkpoint,
            deletions, target), onEvent: (event) {
      if (event is SyncProgress) {
        if (event.phase == SyncPhase.committing) control?.committing = true;
        onProgress?.call(event);
      }
    }, control: control);
  }

  static Future<SyncResult> Function(SensitiveWorker) _workerTask(
          List<VaultedFile> local,
          Uint8List key,
          RemoteStore remote,
          String deviceId,
          String root,
          SyncDirection direction,
          SyncCheckpoint checkpoint,
          Map<String, DateTime> deletions,
          String target) =>
      (worker) => runSync(
            local: local,
            masterKey: key,
            remote: remote,
            deviceId: deviceId,
            vaultRoot: root,
            direction: direction,
            checkpoint: checkpoint,
            deletions: deletions,
            control: worker.control,
            onProgress: worker.emit,
            stateStore: SyncStateStore(root, key),
            target: target,
          );

  Future<List<SyncConflict>> pendingConflicts(SyncProfile profile) async {
    final generation = _crypto.cacheGeneration;
    final key = await _crypto.getMasterKey();
    final dir = await _store.ensureVaultDirectory();
    if (!_crypto.isCurrentSession(generation)) {
      throw StateError('Vault session expired');
    }
    return (await SyncStateStore(dir.path, key)
            .load(SyncStateStore.targetId(profile)))
        .conflicts;
  }

  Future<void> chooseConflict(
      SyncProfile profile, String id, ConflictChoice choice) async {
    final generation = _crypto.cacheGeneration;
    final key = await _crypto.getMasterKey();
    final dir = await _store.ensureVaultDirectory();
    final stateStore = SyncStateStore(dir.path, key);
    final target = SyncStateStore.targetId(profile);
    final saved = await stateStore.load(target);
    if (!_crypto.isCurrentSession(generation)) {
      throw StateError('Vault session expired');
    }
    final conflicts = saved.conflicts
        .map((c) => c.id == id
            ? SyncConflict(local: c.local, remote: c.remote, choice: choice)
            : c)
        .toList();
    await stateStore.save(
        target,
        SyncCheckpoint(baseline: saved.baseline, conflicts: conflicts)
            .toJson());
  }

  Future<void> complete(
      SyncProfile profile, SyncResult result, int generation) async {
    await _apply(result.refreshedLocal, result.originalLocal,
        result.plan.toTombstoneLocal, generation);
    final dir = await _store.ensureVaultDirectory();
    final key = await _crypto.getMasterKey();
    if (!_crypto.isCurrentSession(generation)) {
      throw StateError('Vault session expired');
    }
    final stateStore = SyncStateStore(dir.path, key);
    final target = SyncStateStore.targetId(profile);
    await stateStore.save(target, result.checkpoint.toJson());
    await stateStore.clearJournal(target);
  }

  Future<void> _apply(List<VaultedFile> refreshed, List<VaultedFile> original,
      List<String> removed, int generation) async {
    if (!_crypto.isCurrentSession(generation)) {
      throw StateError('Vault session expired');
    }
    final current = await _store.loadFileIndex();
    if (!_crypto.isCurrentSession(generation)) {
      throw StateError('Vault session expired');
    }
    final merged = mergeSyncedIntoCurrent(current, refreshed,
        original: original,
        removed: removed,
        blobExists: (f) => File(f.vaultPath).existsSync());
    final keptIds = merged.map((f) => f.id).toSet();
    _store.cachedFiles = merged;
    await _store.saveFileIndex(
        strict: true,
        allowEmpty: true,
        removedIds: current
            .where((f) => !keptIds.contains(f.id))
            .map((f) => f.id)
            .toSet());
    if (!_crypto.isCurrentSession(generation)) {
      throw StateError('Vault session expired');
    }
  }

  /// Stream transfers, retain conflicts and publish the manifest last.
  static Future<SyncResult> runSync({
    required List<VaultedFile> local,
    required Uint8List masterKey,
    required RemoteStore remote,
    required String deviceId,
    String? vaultRoot,
    SyncDirection direction = SyncDirection.pushOnly,
    DateTime? now,
    void Function(SyncProgress)? onProgress,
    SyncControl? control,
    SyncCheckpoint checkpoint = const SyncCheckpoint(),
    Map<String, DateTime> deletions = const {},
    SyncStateStore? stateStore,
    String? target,
  }) =>
      SyncEngine.run(
          local: local,
          masterKey: masterKey,
          remote: remote,
          deviceId: deviceId,
          vaultRoot: vaultRoot,
          direction: direction,
          now: now,
          onProgress: onProgress,
          control: control,
          checkpoint: checkpoint,
          deletions: deletions,
          stateStore: stateStore,
          target: target);

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
  /// for tombstones keep their last hash for recovery. v2 carries
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

  /// Legacy timestamp planner. The production engine uses durable baselines.
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

  /// Apply pulls only to unchanged snapshots and preserve concurrent edits.
  static List<VaultedFile> mergeSyncedIntoCurrent(
    List<VaultedFile> current,
    List<VaultedFile> synced, {
    bool Function(VaultedFile)? blobExists,
    List<VaultedFile>? original,
    List<String> removed = const [],
  }) {
    final syncedById = {for (final f in synced) f.id: f};
    final originalById = {for (final f in original ?? <VaultedFile>[]) f.id: f};
    final out = <VaultedFile>[];
    final seen = <String>{};
    for (final f in current) {
      seen.add(f.id);
      final s = syncedById[f.id];
      final before = originalById[f.id];
      if (original != null) {
        final unchanged = before != null && _sameLocal(f, before);
        if (removed.contains(f.id) && unchanged) continue;
        if (s != null && unchanged) {
          out.add(s.copyWith(
              viewCount: f.viewCount,
              lastViewed: f.lastViewed,
              notes: f.notes,
              thumbnailPath:
                  s.vaultPath == f.vaultPath ? f.thumbnailPath : null,
              thumbnailIv: s.vaultPath == f.vaultPath ? f.thumbnailIv : null));
        } else {
          out.add(f);
        }
        continue;
      }
      if (s == null ||
          (s.remoteHash == f.remoteHash &&
              s.syncedDeleted == f.syncedDeleted)) {
        out.add(f);
      } else {
        out.add(f.copyWith(
          remoteHash: s.remoteHash,
          syncedDeleted: s.syncedDeleted,
        ));
      }
    }
    for (final s in synced) {
      if (seen.contains(s.id)) continue;
      if (originalById.containsKey(s.id)) continue;
      if (blobExists != null && !blobExists(s)) continue;
      out.add(s);
    }
    return out;
  }

  static bool _sameLocal(VaultedFile a, VaultedFile b) =>
      a.vaultPath == b.vaultPath &&
      a.modifiedAt == b.modifiedAt &&
      a.dateModified == b.dateModified &&
      syncFingerprint(buildManifest([a], deviceId: '').entries.single) ==
          syncFingerprint(buildManifest([b], deviceId: '').entries.single);

  /// Separate local payloads by ID; deleting one copy must not break another.
  static String vaultPathFor({
    required String vaultRoot,
    required ManifestEntry entry,
  }) {
    final type = _typeFromName(entry.type);
    final subdir = VaultStore.subdirFor(type);
    final hash = entry.contentHash ?? entry.id;
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('Invalid blob hash');
    }
    final stem = '${sha256.convert(utf8.encode(entry.id))}_$hash';
    final ext = _extOf(entry.originalName);
    final name = ext.isEmpty ? '$stem.enc' : '$stem.$ext';
    return '$vaultRoot/$subdir/$name';
  }

  /// Reconstruct a [VaultedFile] from a manifest entry at [vaultPath]. The
  /// inverse of [buildManifest]'s per-file mapping.
  static VaultedFile vaultedFileFromEntry(
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
    final ext = originalName.substring(dot + 1).toLowerCase();
    return RegExp(r'^[a-z0-9]{1,12}$').hasMatch(ext) ? ext : '';
  }

  /// Encrypt a manifest with the vault master key. Wire format:
  /// `[16-byte IV][ciphertext+GCM tag]`. Reuses AesGcmCipher — no new crypto.
  static Uint8List encryptManifest(
      RemoteManifest manifest, Uint8List masterKey) {
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
