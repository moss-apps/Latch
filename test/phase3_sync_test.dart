import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/remote_manifest.dart';
import 'package:locker/models/sync_conflict.dart';
import 'package:locker/models/sync_profile.dart';
import 'package:locker/models/vaulted_file.dart';
import 'package:locker/services/remote/remote_store.dart';
import 'package:locker/services/sensitive_isolate.dart';
import 'package:locker/services/sync_control.dart';
import 'package:locker/services/sync_service.dart';
import 'package:locker/services/sync_state_store.dart';

Future<int> _waitingWorker(SensitiveWorker worker) async {
  worker.emit('ready');
  while (!worker.control.cancelled) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  worker.control.check();
  return 1;
}

Future<int> _otherWorker() async {
  await Future<void>.delayed(const Duration(milliseconds: 100));
  return 7;
}

void main() {
  late Directory dir;
  late _FaultStore remote;
  final key = Uint8List(32);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('latch_phase3_');
    remote = _FaultStore();
  });
  tearDown(() async {
    SensitiveIsolate.cancelAll();
    await dir.delete(recursive: true);
  });

  Future<VaultedFile> file(String id, {List<int> bytes = const [1, 2, 3]}) async {
    final path = '${dir.path}/$id.enc';
    await File(path).writeAsBytes(bytes);
    return VaultedFile(id: id, originalName: '$id.jpg', vaultPath: path,
        type: VaultedFileType.image, mimeType: 'image/jpeg', fileSize: bytes.length,
        dateAdded: DateTime.utc(2024), modifiedAt: DateTime.utc(2024));
  }

  Future<SyncResult> run(List<VaultedFile> files, {SyncCheckpoint checkpoint = const SyncCheckpoint(),
      SyncDirection direction = SyncDirection.twoWay, SyncControl? control,
      Map<String, DateTime> deletions = const {},
      SyncStateStore? stateStore, void Function(SyncProgress)? progress}) =>
      SyncService.runSync(local: files, masterKey: key, remote: remote,
          deviceId: 'test', vaultRoot: dir.path, checkpoint: checkpoint,
          direction: direction, control: control, onProgress: progress,
          deletions: deletions, stateStore: stateStore, target: 'target');

  RemoteManifest manifest() => SyncService.decryptManifest(remote.manifest!, key);

  test('backup preserves remote-only files and remotely newer metadata', () async {
    final a = await file('a');
    final b = await file('b', bytes: [4, 5]);
    final seed = await run([a, b]);
    final changed = manifest().entries.map((e) => e.id == 'a' ? e.copyWith(tags: ['remote']) : e).toList();
    remote.manifest = SyncService.encryptManifest(RemoteManifest(deviceId: 'other',
        generatedAt: DateTime.now(), entries: changed), key);
    final result = await run([seed.refreshedLocal.firstWhere((f) => f.id == 'a')],
        // b never belonged to this device's baseline.
        checkpoint: SyncCheckpoint(baseline: {'a': seed.checkpoint.baseline['a']!}),
        direction: SyncDirection.pushOnly);
    expect(manifest().entries.map((e) => e.id), containsAll(['a', 'b']));
    expect(manifest().entries.firstWhere((e) => e.id == 'a').tags, ['remote']);
    expect(result.blobsPulled, 0);
  });

  test('metadata conflicts persist and keep both produces stable distinct IDs', () async {
    final seed = await run([await file('a')]);
    final original = seed.refreshedLocal.single;
    final editedRemote = manifest().entries.single.copyWith(tags: ['server']);
    remote.manifest = SyncService.encryptManifest(RemoteManifest(deviceId: 'other',
        generatedAt: DateTime.now(), entries: [editedRemote]), key);
    final local = original.copyWith(tags: ['device']);
    final conflict = await run([local], checkpoint: seed.checkpoint);
    expect(conflict.checkpoint.conflicts, hasLength(1));
    expect(manifest().entries.single.tags, ['server']);
    expect(conflict.refreshedLocal.single.tags, ['device']);

    final store = SyncStateStore(dir.path, key);
    await store.save('target', conflict.checkpoint.toJson());
    final persisted = await store.load('target');
    final pending = persisted.conflicts.single;
    final resolved = await run([local], checkpoint: SyncCheckpoint(
        baseline: persisted.baseline, conflicts: [SyncConflict(local: pending.local,
            remote: pending.remote, choice: ConflictChoice.both)]));
    expect(resolved.checkpoint.conflicts, isEmpty);
    expect(manifest().entries, hasLength(2));
    expect(manifest().entries.map((e) => e.id).toSet(), hasLength(2));
    expect(resolved.refreshedLocal.firstWhere((f) => f.id == 'a').tags, ['server']);
    expect(resolved.refreshedLocal.firstWhere((f) => f.id != 'a').tags, ['device']);
    final rerun = await run(resolved.refreshedLocal, checkpoint: resolved.checkpoint);
    expect(rerun.checkpoint.conflicts, isEmpty);
    expect(manifest().entries, hasLength(2));
  });

  test('stale conflict choice never overwrites a new remote edit', () async {
    final seed = await run([await file('a')]);
    final originalEntry = manifest().entries.single;
    final firstRemote = originalEntry.copyWith(tags: ['first']);
    remote.manifest = SyncService.encryptManifest(RemoteManifest(deviceId: 'other',
        generatedAt: DateTime.now(), entries: [firstRemote]), key);
    final local = seed.refreshedLocal.single.copyWith(tags: ['local']);
    final pending = (await run([local], checkpoint: seed.checkpoint)).checkpoint.conflicts.single;
    remote.manifest = SyncService.encryptManifest(RemoteManifest(deviceId: 'other',
        generatedAt: DateTime.now(), entries: [firstRemote.copyWith(tags: ['second'])]), key);
    final result = await run([local], checkpoint: SyncCheckpoint(baseline: seed.checkpoint.baseline,
        conflicts: [SyncConflict(local: pending.local, remote: pending.remote, choice: ConflictChoice.local)]));
    expect(result.checkpoint.conflicts.single.remote.tags, ['second']);
    expect(manifest().entries.single.tags, ['second']);
  });

  test('a recorded deletion becomes a durable tombstone', () async {
    final seed = await run([await file('a')]);
    final result = await run([], checkpoint: seed.checkpoint,
        deletions: {'a': DateTime.now().toUtc()});
    expect(manifest().entries.single.deleted, isTrue);
    expect(result.filesDeleted, 1);
    expect(remote.blobs, isNotEmpty);
    expect(remote.operations, isNot(contains('delete')));
  });

  test('a file missing without a recorded deletion is not treated as deleted', () async {
    final seed = await run([await file('a')]);
    final result = await run([], checkpoint: seed.checkpoint);
    expect(manifest().entries.single.deleted, isFalse);
    expect(result.filesDeleted, 0);
  });

  test('delete versus remote edit is reviewable rather than destructive', () async {
    final seed = await run([await file('a')]);
    remote.manifest = SyncService.encryptManifest(RemoteManifest(deviceId: 'other',
        generatedAt: DateTime.now(), entries: [manifest().entries.single.copyWith(tags: ['edit'])]), key);
    final result = await run([], checkpoint: seed.checkpoint,
        deletions: {'a': DateTime.now().toUtc()});
    expect(result.checkpoint.conflicts.single.local.deleted, isTrue);
    expect(manifest().entries.single.deleted, isFalse);
  });

  test('failed publication retains both payloads, manifest and encrypted journal', () async {
    final seed = await run([await file('a')]);
    final oldManifest = remote.manifest;
    final local = seed.refreshedLocal.single;
    await File(local.vaultPath).writeAsBytes([8, 8, 8]);
    remote.failPublication = true;
    final store = SyncStateStore(dir.path, key);
    await expectLater(run([local], checkpoint: seed.checkpoint, stateStore: store), throwsStateError);
    expect(remote.manifest, oldManifest);
    expect(remote.blobs, hasLength(2));
    expect(await store.read('target', journal: true), isNotNull);
    expect((await store.load('target')).baseline, isEmpty);
    expect(await File(local.vaultPath).readAsBytes(), [8, 8, 8]);
    remote.failPublication = false;
    final retry = await run([local], checkpoint: seed.checkpoint, stateStore: store);
    expect(retry.blobsPushed, 0);
    expect(retry.blobsReused, 1);
  });

  test('corrupt download never replaces the existing file or publishes', () async {
    final seed = await run([await file('a')]);
    final old = seed.refreshedLocal.single;
    final remoteBytes = Uint8List.fromList([7, 7]);
    final hash = SyncService.sha256Hex(remoteBytes);
    remote.blobs[SyncService.blobNameFor(hash)] = Uint8List.fromList([0]);
    remote.manifest = SyncService.encryptManifest(RemoteManifest(deviceId: 'other',
        generatedAt: DateTime.now(), entries: [manifest().entries.single.copyWith(contentHash: hash)]), key);
    final commits = remote.publications;
    await expectLater(run([old], checkpoint: seed.checkpoint), throwsFormatException);
    expect(await File(old.vaultPath).readAsBytes(), [1, 2, 3]);
    expect(remote.publications, commits);
    expect(await Directory('${dir.path}/temp').list().toList(), isEmpty);
  });

  test('remote revision race leaves the winning manifest intact', () async {
    final seed = await run([await file('a')]);
    final winner = remote.manifest;
    remote.race = true;
    await expectLater(run(seed.refreshedLocal, checkpoint: seed.checkpoint),
        throwsA(isA<RemoteRevisionChanged>()));
    expect(remote.manifest, winner);
  });

  test('cancellation before commit leaves the existing manifest intact', () async {
    final seed = await run([await file('a')]);
    final old = remote.manifest;
    final local = await file('b');
    final control = SyncControl();
    await expectLater(run([...seed.refreshedLocal, local], checkpoint: seed.checkpoint,
        control: control, progress: (p) {
          if (p.phase == SyncPhase.uploading) control.cancel();
        }), throwsA(isA<SyncCancelled>()));
    expect(remote.manifest, old);
  });

  test('pulled metadata and path apply while concurrent local changes survive', () async {
    final original = await file('a');
    final pulled = original.copyWith(vaultPath: '${dir.path}/new.enc', tags: ['server'],
        encryptionIv: 'new-iv', originalName: 'new.jpg');
    final merged = SyncService.mergeSyncedIntoCurrent([original], [pulled], original: [original]);
    expect(merged.single.vaultPath, pulled.vaultPath);
    expect(merged.single.encryptionIv, 'new-iv');
    expect(merged.single.tags, ['server']);
    final edited = original.copyWith(tags: ['local']);
    expect(SyncService.mergeSyncedIntoCurrent([edited], [pulled], original: [original]).single.tags, ['local']);
    expect(SyncService.mergeSyncedIntoCurrent([], [pulled], original: [original]), isEmpty);
    expect(SyncService.mergeSyncedIntoCurrent([edited], [], original: [original], removed: ['a']), [edited]);
    final samePath = original.copyWith(tags: ['metadata']);
    expect(SyncService.mergeSyncedIntoCurrent([original], [samePath], original: [original]).single.tags, ['metadata']);
  });

  test('cancel targets one worker and progress crosses the isolate boundary', () async {
    final ready = Completer<void>();
    final control = SyncControl();
    final other = SensitiveIsolate.run(_otherWorker);
    final cancelled = SensitiveIsolate.runWithEvents(_waitingWorker, control: control,
        onEvent: (_) => ready.complete());
    final expectation = expectLater(cancelled, throwsA(isA<SyncCancelled>()));
    await ready.future;
    control.cancel();
    await expectation;
    expect(await other, 7);
  });

  test('vault lock still terminates event-enabled sensitive workers', () async {
    final ready = Completer<void>();
    final task = SensitiveIsolate.runWithEvents(_waitingWorker, onEvent: (_) => ready.complete());
    final expectation = expectLater(task, throwsStateError);
    await ready.future;
    SensitiveIsolate.cancelAll();
    await expectation;
  });
}

class _FaultStore implements RemoteStore, StreamingRemoteStore {
  Uint8List? manifest;
  final blobs = <String, Uint8List>{};
  final operations = <String>[];
  int publications = 0;
  bool failPublication = false;
  bool race = false;

  @override
  Future<RemoteManifestSnapshot> readManifest(SyncControl control) async =>
      RemoteManifestSnapshot(manifest, manifest == null ? null : 'revision');
  @override
  Future<void> publishManifest(Uint8List bytes, String? revision, SyncControl control) async {
    if (race) throw RemoteRevisionChanged();
    if (failPublication) throw StateError('Injected publication failure');
    operations.add('publish');
    publications++;
    manifest = bytes;
  }
  @override
  Future<int?> blobLength(String name, SyncControl control) async => blobs[name]?.length;
  @override
  Future<bool> verifyBlob(String name, String hash, SyncControl control) async =>
      blobs[name] != null && SyncService.sha256Hex(blobs[name]!) == hash;
  @override
  Future<void> uploadFile(String name, File file, String hash, SyncControl control,
      void Function(int, int) progress) async {
    final data = <int>[];
    await for (final chunk in file.openRead()) {
      control.check();
      data.addAll(chunk);
      progress(data.length, await file.length());
    }
    control.check();
    blobs[name] = Uint8List.fromList(data);
    operations.add('upload');
  }
  @override
  Future<bool> downloadFile(String name, File destination, SyncControl control,
      void Function(int, int) progress) async {
    final data = blobs[name];
    if (data == null) return false;
    await destination.writeAsBytes(data);
    progress(data.length, data.length);
    return true;
  }
  @override
  Future<Uint8List?> getManifest() async => manifest;
  @override
  Future<void> putManifest(Uint8List bytes) => throw StateError('Buffered publication used');
  @override
  Future<Uint8List?> getBlob(String name) => throw StateError('Buffered download used');
  @override
  Future<void> putBlob(String name, Uint8List bytes) => throw StateError('Buffered upload used');
  @override
  Future<void> deleteBlob(String name) async { operations.add('delete'); }
  @override
  Future<List<String>> listBlobs() async => blobs.keys.toList();
  @override
  Future<void> testConnection() async {}
}
