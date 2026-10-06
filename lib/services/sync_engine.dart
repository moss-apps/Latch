import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../models/remote_manifest.dart';
import '../models/sync_conflict.dart';
import '../models/sync_profile.dart';
import '../models/vaulted_file.dart';
import 'diagnostics.dart';
import 'remote/remote_store.dart';
import 'sync_control.dart';
import 'sync_service.dart';
import 'sync_state_store.dart';

class SyncEngine {
  static Future<String> hashFile(File file, SyncControl control) async {
    Stream<List<int>> chunks() async* {
      await for (final chunk in file.openRead()) {
        control.check();
        yield chunk;
      }
    }

    return (await sha256.bind(chunks()).first).toString();
  }

  static Future<SyncResult> run({
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
  }) async {
    final cancel = control ?? SyncControl();
    final date = (now ?? DateTime.now()).toUtc();
    final twoWay = direction == SyncDirection.twoWay;
    final streaming =
        remote is StreamingRemoteStore ? remote as StreamingRemoteStore : null;
    void report(SyncProgress progress) {
      cancel.check();
      onProgress?.call(progress);
    }

    report(const SyncProgress(phase: SyncPhase.connecting));
    final snapshot = streaming == null
        ? RemoteManifestSnapshot(await remote.getManifest(), null)
        : await streaming.readManifest(cancel);
    final manifest = snapshot.bytes == null
        ? null
        : SyncService.decryptManifest(snapshot.bytes!, masterKey);
    final remoteEntries = {
      for (final e in manifest?.entries ?? <ManifestEntry>[]) e.id: e
    };
    final candidates = Map<String, ManifestEntry>.from(remoteEntries);
    final files = {for (final file in local) file.id: file};
    final localEntries = <String, ManifestEntry>{};
    var skipped = 0;
    var hashed = 0;
    for (final file in local) {
      report(SyncProgress(
          phase: SyncPhase.hashing,
          filename: file.originalName,
          completed: hashed,
          total: local.length));
      if (!file.syncedDeleted && !await File(file.vaultPath).exists()) {
        skipped++;
        hashed++;
        continue;
      }
      final hash = file.syncedDeleted
          ? file.remoteHash
          : await hashFile(File(file.vaultPath), cancel);
      localEntries[file.id] = SyncService.buildManifest(
              [file.copyWith(remoteHash: hash)],
              deviceId: deviceId, now: date)
          .entries
          .single;
      hashed++;
    }
    // A missing index entry alone is not proof that the user deleted it.
    for (final baseline in checkpoint.baseline.values) {
      if (!files.containsKey(baseline.id) &&
          deletions.containsKey(baseline.id)) {
        localEntries[baseline.id] = baseline.copyWith(
            deleted: true, modifiedAt: deletions[baseline.id]);
      }
    }

    final pushes = <VaultedFile>[];
    final pulls = <ManifestEntry>[];
    final deletes = <String>[];
    final localDeletes = <String>[];
    final conflicts = <SyncConflict>[];
    final resolvedLocal = Map<String, VaultedFile>.from(files);
    final agreed = <String, ManifestEntry>{};
    for (final entry in localEntries.values.toList()) {
      final other = remoteEntries[entry.id];
      final baseline = checkpoint.baseline[entry.id];
      if (other == null) {
        if (!entry.deleted) {
          candidates[entry.id] = entry;
          pushes.add(files[entry.id]!);
          agreed[entry.id] = entry;
        }
        continue;
      }
      final equal = syncFingerprint(entry) == syncFingerprint(other);
      if (equal) {
        agreed[entry.id] = entry;
        final file = files[entry.id];
        if (file != null && !entry.deleted) {
          resolvedLocal[entry.id] =
              file.copyWith(remoteHash: entry.contentHash);
        }
        continue;
      }
      final localChanged = baseline == null ||
          syncFingerprint(entry) != syncFingerprint(baseline);
      final remoteChanged = baseline == null ||
          syncFingerprint(other) != syncFingerprint(baseline);
      ConflictChoice? choice;
      if (localChanged && remoteChanged) {
        for (final saved in checkpoint.conflicts) {
          if (saved.id == entry.id && saved.matches(entry, other)) {
            choice = saved.choice;
          }
        }
        if (choice == null) {
          conflicts.add(SyncConflict(local: entry, remote: other));
          continue;
        }
      }
      final useLocal =
          choice == ConflictChoice.local || (!remoteChanged && localChanged);
      if (useLocal) {
        candidates[entry.id] = entry;
        agreed[entry.id] = entry;
        if (entry.deleted) {
          deletes.add(entry.id);
        } else {
          pushes.add(files[entry.id]!);
        }
      } else if (twoWay || choice != null) {
        agreed[entry.id] = other;
        if (other.deleted) {
          localDeletes.add(entry.id);
          resolvedLocal.remove(entry.id);
        } else {
          pulls.add(other);
        }
        if (choice == ConflictChoice.both && !entry.deleted && !other.deleted) {
          final id = const Uuid().v5(Namespace.url.value,
              '${entry.id}:${syncFingerprint(entry)}:${syncFingerprint(other)}');
          final source = files[entry.id]!;
          final dot = source.originalName.lastIndexOf('.');
          final name = dot > 0
              ? '${source.originalName.substring(0, dot)} (local copy)${source.originalName.substring(dot)}'
              : '${source.originalName} (local copy)';
          final copyEntry = entry.copyWith(id: id, originalName: name);
          if (vaultRoot == null) {
            throw const FormatException('Missing vault destination');
          }
          final destination = File(
              SyncService.vaultPathFor(vaultRoot: vaultRoot, entry: copyEntry));
          await destination.parent.create(recursive: true);
          if (!await destination.exists()) {
            await File(source.vaultPath).copy(destination.path);
          }
          if (await hashFile(destination, cancel) != entry.contentHash) {
            throw const FormatException('Conflict copy hash mismatch');
          }
          final copy = source.copyWith(
              id: id, originalName: name, vaultPath: destination.path);
          resolvedLocal[id] = copy;
          localEntries[id] = copyEntry;
          candidates[id] = copyEntry;
          agreed[id] = copyEntry;
          pushes.add(copy);
        }
      }
    }
    if (twoWay) {
      for (final entry in remoteEntries.values) {
        if (!files.containsKey(entry.id) &&
            !localEntries.containsKey(entry.id) &&
            !entry.deleted) {
          pulls.add(entry);
          agreed[entry.id] = entry;
        }
      }
    }

    var pushed = 0;
    var reused = 0;
    var transferred = 0;
    var totalBytes =
        pushes.fold<int>(0, (n, f) => n + File(f.vaultPath).lengthSync());
    final downloadLengths = <String, int>{};
    for (final entry in pulls) {
      cancel.check();
      final hash = entry.contentHash;
      final length = streaming == null || hash == null
          ? null
          : await streaming.blobLength(SyncService.blobNameFor(hash), cancel);
      if (length == null) {
        totalBytes = -1;
      } else {
        downloadLengths[entry.id] = length;
        if (totalBytes >= 0) totalBytes += length;
      }
    }
    for (var i = 0; i < pushes.length; i++) {
      final file = pushes[i];
      final entry = candidates[file.id]!;
      final hash = entry.contentHash!;
      final name = SyncService.blobNameFor(hash);
      void progress(int bytes, int total) => report(SyncProgress(
          phase: SyncPhase.uploading,
          completed: i,
          total: pushes.length,
          filename: file.originalName,
          fileBytes: bytes,
          fileTotal: total,
          transferredBytes: transferred + bytes,
          totalBytes: totalBytes));
      progress(0, await File(file.vaultPath).length());
      cancel.check();
      var exists = false;
      if (streaming != null) {
        exists = await streaming.verifyBlob(name, hash, cancel);
        if (!exists) {
          await streaming.uploadFile(
              name, File(file.vaultPath), hash, cancel, progress);
        }
      } else {
        final existing = await remote.getBlob(name);
        exists = existing != null && SyncService.sha256Hex(existing) == hash;
        if (!exists) {
          final bytes = await File(file.vaultPath).readAsBytes();
          if (SyncService.sha256Hex(bytes) != hash) {
            throw const FormatException('Source changed during sync');
          }
          await remote.putBlob(name, bytes);
          progress(bytes.length, bytes.length);
        }
      }
      final length = await File(file.vaultPath).length();
      if (exists) {
        reused++;
        if (totalBytes >= 0) totalBytes -= length;
      } else {
        pushed++;
        transferred += length;
      }
      report(SyncProgress(
          phase: SyncPhase.uploading,
          completed: i + 1,
          total: pushes.length,
          filename: file.originalName,
          fileBytes: exists ? 0 : length,
          fileTotal: exists ? -1 : length,
          transferredBytes: transferred,
          totalBytes: totalBytes));
      resolvedLocal[file.id] =
          file.copyWith(remoteHash: hash, modifiedAt: file.modifiedAt ?? date);
    }

    var pulled = 0;
    for (final entry in pulls) {
      cancel.check();
      if (vaultRoot == null || entry.contentHash == null) {
        throw const FormatException('Incomplete restore metadata');
      }
      final name = SyncService.blobNameFor(entry.contentHash!);
      final destination =
          File(SyncService.vaultPathFor(vaultRoot: vaultRoot, entry: entry));
      await destination.parent.create(recursive: true);
      final temporary =
          File('$vaultRoot/temp/sync_${const Uuid().v4()}.partial');
      await temporary.parent.create(recursive: true);
      try {
        void progress(int bytes, int total) => report(SyncProgress(
            phase: SyncPhase.downloading,
            completed: pulled,
            total: pulls.length,
            filename: entry.originalName,
            fileBytes: bytes,
            fileTotal: total,
            transferredBytes: transferred + bytes,
            totalBytes: totalBytes));
        progress(0, downloadLengths[entry.id] ?? -1);
        if (streaming != null) {
          if (!await streaming.downloadFile(
              name, temporary, cancel, progress)) {
            throw const FormatException('Missing remote blob');
          }
        } else {
          final bytes = await remote.getBlob(name);
          if (bytes == null) throw const FormatException('Missing remote blob');
          await temporary.writeAsBytes(bytes, flush: true);
          progress(bytes.length, bytes.length);
        }
        if (await hashFile(temporary, cancel) != entry.contentHash) {
          throw const FormatException('Downloaded blob hash mismatch');
        }
        // Old payloads remain available until the local index is durable.
        if (await destination.exists()) {
          if (await hashFile(destination, cancel) != entry.contentHash) {
            throw const FormatException('Destination collision');
          }
        } else {
          await temporary.rename(destination.path);
        }
        resolvedLocal[entry.id] = SyncService.vaultedFileFromEntry(entry,
            vaultPath: destination.path);
        final length = await destination.length();
        transferred += length;
        pulled++;
        report(SyncProgress(
            phase: SyncPhase.downloading,
            completed: pulled,
            total: pulls.length,
            filename: entry.originalName,
            fileBytes: length,
            fileTotal: length,
            transferredBytes: transferred,
            totalBytes: totalBytes));
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    }

    final nextBaseline = Map<String, ManifestEntry>.from(checkpoint.baseline)
      ..addAll(agreed);
    final next = SyncCheckpoint(baseline: nextBaseline, conflicts: conflicts);
    final output = RemoteManifest(
        deviceId: deviceId,
        generatedAt: date,
        entries: candidates.values.toList());
    final bytes = SyncService.encryptManifest(output, masterKey);
    final refreshed =
        resolvedLocal.values.where((f) => !f.syncedDeleted).toList();
    final journal = {
      'manifestHash': SyncService.sha256Hex(bytes),
      'checkpoint': next.toJson(),
      'original': local.map((f) => f.toJson()).toList(),
      'refreshed': refreshed.map((f) => f.toJson()).toList(),
      'removed': localDeletes,
    };
    cancel.check();
    if (stateStore != null && target != null) {
      await stateStore.save(target, journal, journal: true);
    }
    cancel.check();
    cancel.committing = true;
    report(const SyncProgress(phase: SyncPhase.committing));
    if (streaming == null) {
      await remote.putManifest(bytes);
    } else {
      await streaming.publishManifest(bytes, snapshot.revision, cancel);
    }
    Diagnostics.event('sync.commit', {
      'uploaded': pushed,
      'reused': reused,
      'downloaded': pulled,
      'conflicts': conflicts.length,
      'skipped': skipped
    });
    report(const SyncProgress(phase: SyncPhase.done));
    return SyncResult(
        blobsPushed: pushed,
        blobsDeleted: 0,
        blobsPulled: pulled,
        blobsSkipped: skipped,
        blobsReused: reused,
        filesDeleted: deletes.length,
        plan: SyncPlan(
            toPush: pushes,
            toPull: pulls,
            toDelete: deletes,
            conflicts: conflicts.map((c) => c.id).toList(),
            toTombstoneLocal: localDeletes),
        refreshedLocal: refreshed,
        originalLocal: local,
        checkpoint: next,
        completedAt: date);
  }
}
