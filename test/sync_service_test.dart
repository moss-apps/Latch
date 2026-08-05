import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/encryption_algorithm.dart';
import 'package:locker/models/remote_manifest.dart';
import 'package:locker/models/sync_profile.dart';
import 'package:locker/models/vaulted_file.dart';
import 'package:locker/services/remote/remote_store.dart';
import 'package:locker/services/sync_service.dart';
import 'package:pointycastle/export.dart';

VaultedFile _file({
  required String id,
  DateTime? dateAdded,
  DateTime? dateModified,
  DateTime? modifiedAt,
  String? remoteHash,
  bool syncedDeleted = false,
}) {
  return VaultedFile(
    id: id,
    originalName: '$id.jpg',
    vaultPath: '/v/$id',
    type: VaultedFileType.image,
    mimeType: 'image/jpeg',
    fileSize: 100,
    dateAdded: dateAdded ?? DateTime(2024, 1, 1),
    dateModified: dateModified,
    modifiedAt: modifiedAt,
    remoteHash: remoteHash,
    syncedDeleted: syncedDeleted,
  );
}

void main() {
  group('blobNameFor', () {
    test('shards by first 4 hex chars into ab/cd/ paths', () {
      const hash = 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';
      expect(SyncService.blobNameFor(hash), 'ab/cd/$hash.enc');
    });

    test('sha256Hex is deterministic and 64 hex chars', () {
      final a = SyncService.sha256Hex(Uint8List.fromList([1, 2, 3]));
      final b = SyncService.sha256Hex(Uint8List.fromList([1, 2, 3]));
      expect(a, b);
      expect(a.length, 64);
    });
  });

  group('reconcile', () {
    test('empty local and remote yields empty plan', () {
      final plan = SyncService.reconcile(
        local: const [],
        remote: RemoteManifest(
          deviceId: 'd',
          generatedAt: DateTime.utc(2024, 1, 1),
        ),
      );
      expect(plan.isEmpty, isTrue);
    });

    test('new local file (absent from remote) is pushed', () {
      final local = [_file(id: 'a')];
      final plan = SyncService.reconcile(
        local: local,
        remote: RemoteManifest(
          deviceId: 'd',
          generatedAt: DateTime.utc(2024, 1, 1),
        ),
      );
      expect(plan.toPush.map((f) => f.id), ['a']);
      expect(plan.toPull, isEmpty);
      expect(plan.toDelete, isEmpty);
    });

    test('locally newer file is pushed', () {
      final local = [
        _file(
          id: 'a',
          modifiedAt: DateTime(2024, 6, 1),
          remoteHash: 'h1',
        ),
      ];
      final remote = RemoteManifest(
        deviceId: 'd',
        generatedAt: DateTime(2024, 1, 1),
        entries: [
          ManifestEntry(
            id: 'a',
            contentHash: 'h1',
            modifiedAt: DateTime(2024, 3, 1),
          ),
        ],
      );
      final plan = SyncService.reconcile(local: local, remote: remote);
      expect(plan.toPush.map((f) => f.id), ['a']);
    });

    test('remotely newer entry is pulled (two-way)', () {
      final local = [
        _file(
          id: 'a',
          modifiedAt: DateTime(2024, 3, 1),
          remoteHash: 'h1',
        ),
      ];
      final remote = RemoteManifest(
        deviceId: 'd',
        generatedAt: DateTime(2024, 6, 1),
        entries: [
          ManifestEntry(
            id: 'a',
            contentHash: 'h1',
            modifiedAt: DateTime(2024, 6, 1),
          ),
        ],
      );
      final plan = SyncService.reconcile(local: local, remote: remote);
      expect(plan.toPush, isEmpty);
      expect(plan.toPull.map((e) => e.id), ['a']);
    });

    test('remote entry unknown locally is pulled', () {
      final remote = RemoteManifest(
        deviceId: 'd',
        generatedAt: DateTime(2024, 1, 1),
        entries: [
          ManifestEntry(
            id: 'ghost',
            contentHash: 'hg',
            modifiedAt: DateTime(2024, 1, 1),
          ),
        ],
      );
      final plan = SyncService.reconcile(local: const [], remote: remote);
      expect(plan.toPull.map((e) => e.id), ['ghost']);
    });

    test('tombstone schedules remote blob deletion', () {
      final local = [_file(id: 'a', syncedDeleted: true, remoteHash: 'h1')];
      final remote = RemoteManifest(
        deviceId: 'd',
        generatedAt: DateTime(2024, 1, 1),
        entries: [
          ManifestEntry(
            id: 'a',
            contentHash: 'deadbeef',
            modifiedAt: DateTime(2024, 1, 1),
          ),
        ],
      );
      final plan = SyncService.reconcile(local: local, remote: remote);
      expect(plan.toDelete, ['de/ad/deadbeef.enc']);
      expect(plan.toPush, isEmpty);
    });

    test('in-sync file produces no work', () {
      final t = DateTime(2024, 5, 1);
      final local = [_file(id: 'a', modifiedAt: t, remoteHash: 'h1')];
      final remote = RemoteManifest(
        deviceId: 'd',
        generatedAt: t,
        entries: [ManifestEntry(id: 'a', contentHash: 'h1', modifiedAt: t)],
      );
      expect(SyncService.reconcile(local: local, remote: remote).isEmpty, isTrue);
    });

    test('conflict: local newer AND remote diverged since last sync', () {
      final local = [
        _file(id: 'a', modifiedAt: DateTime(2024, 6, 5), remoteHash: 'old'),
      ];
      final remote = RemoteManifest(
        deviceId: 'd',
        generatedAt: DateTime(2024, 6, 1),
        entries: [
          ManifestEntry(
            id: 'a',
            contentHash: 'new',
            modifiedAt: DateTime(2024, 6, 4),
          ),
        ],
      );
      final plan = SyncService.reconcile(local: local, remote: remote);
      expect(plan.toPush.map((f) => f.id), ['a']); // LWW: local still wins
      expect(plan.conflicts, ['a']); // but flagged
    });

    test('no conflict when remote unchanged though local is newer', () {
      final local = [
        _file(id: 'a', modifiedAt: DateTime(2024, 6, 5), remoteHash: 'same'),
      ];
      final remote = RemoteManifest(
        deviceId: 'd',
        generatedAt: DateTime(2024, 6, 1),
        entries: [
          ManifestEntry(
            id: 'a',
            contentHash: 'same',
            modifiedAt: DateTime(2024, 6, 1),
          ),
        ],
      );
      final plan = SyncService.reconcile(local: local, remote: remote);
      expect(plan.toPush.map((f) => f.id), ['a']);
      expect(plan.conflicts, isEmpty);
    });

    test('remote tombstone schedules local deletion (LWW: tombstone newer)',
        () {
      final local = [_file(id: 'a', modifiedAt: DateTime(2024, 1, 1))];
      final remote = RemoteManifest(
        deviceId: 'd',
        generatedAt: DateTime(2024, 6, 1),
        entries: [
          ManifestEntry(
            id: 'a',
            contentHash: 'h',
            modifiedAt: DateTime(2024, 6, 1),
            deleted: true,
          ),
        ],
      );
      final plan = SyncService.reconcile(local: local, remote: remote);
      expect(plan.toTombstoneLocal, ['a']);
      expect(plan.toPush, isEmpty);
    });

    test('local newer than remote tombstone resurrects (push)', () {
      final local = [_file(id: 'a', modifiedAt: DateTime(2024, 6, 5))];
      final remote = RemoteManifest(
        deviceId: 'd',
        generatedAt: DateTime(2024, 1, 1),
        entries: [
          ManifestEntry(
            id: 'a',
            contentHash: 'h',
            modifiedAt: DateTime(2024, 1, 1),
            deleted: true,
          ),
        ],
      );
      final plan = SyncService.reconcile(local: local, remote: remote);
      expect(plan.toTombstoneLocal, isEmpty);
      expect(plan.toPush.map((f) => f.id), ['a']);
    });
  });

  group('manifest crypto', () {
    test('encrypt/decrypt round-trips the manifest', () {
      final masterKey =
          Uint8List.fromList(List<int>.generate(32, (i) => i * 7 % 256));
      final manifest = SyncService.buildManifest(
        [
          _file(
            id: 'a',
            modifiedAt: DateTime(2024, 5, 1),
            remoteHash: 'hash-a',
          ),
          _file(id: 'b', remoteHash: 'hash-b', syncedDeleted: true),
        ],
        deviceId: 'device-1',
        now: DateTime.utc(2024, 5, 2),
      );

      final enc = SyncService.encryptManifest(manifest, masterKey);
      // Wire format: 16-byte IV prefix + ciphertext+tag.
      expect(enc.length, greaterThan(16 + 16));

      final dec = SyncService.decryptManifest(enc, masterKey);
      expect(dec.version, 2);
      expect(dec.deviceId, 'device-1');
      expect(dec.entries.map((e) => e.id), ['a', 'b']);
      expect(dec.entries.first.contentHash, 'hash-a');
      expect(dec.entries.last.deleted, isTrue);
    });

    test('tampered ciphertext fails GCM auth', () {
      final masterKey = Uint8List(32);
      final manifest = SyncService.buildManifest(
        [_file(id: 'a', remoteHash: 'h')],
        deviceId: 'd',
        now: DateTime.utc(2024, 1, 1),
      );
      final enc = SyncService.encryptManifest(manifest, masterKey);
      enc[enc.length - 1] ^= 0x01; // flip last byte (in the auth tag)
      expect(
        () => SyncService.decryptManifest(enc, masterKey),
        throwsA(isA<InvalidCipherTextException>()),
      );
    });
  });

  group('model serialization', () {
    test('SyncProfile round-trips through json string', () {
      final p = SyncProfile(
        id: 'p1',
        serverUrl: 'https://nas.local/dav',
        username: 'u',
        basePath: '/locker',
        direction: SyncDirection.twoWay,
        wifiOnly: false,
        enabled: true,
        lastSyncedAt: DateTime.utc(2024, 6, 1, 12, 0),
      );
      final rt = SyncProfile.fromJsonString(p.toJsonString());
      expect(rt.id, p.id);
      expect(rt.serverUrl, p.serverUrl);
      expect(rt.direction, SyncDirection.twoWay);
      expect(rt.wifiOnly, false);
      expect(rt.passwordStorageKey, 'sync_profile_pw_p1');
    });

    test('VaultedFile round-trips sync fields', () {
      final f = _file(
        id: 'x',
        modifiedAt: DateTime.utc(2024, 7, 1),
        remoteHash: 'rh',
        syncedDeleted: true,
      );
      final rt = VaultedFile.fromJsonString(f.toJsonString());
      expect(rt.modifiedAt, DateTime.utc(2024, 7, 1));
      expect(rt.remoteHash, 'rh');
      expect(rt.syncedDeleted, isTrue);
    });

    test('RemoteManifest round-trips entries', () {
      final m = RemoteManifest(
        version: 1,
        deviceId: 'd',
        generatedAt: DateTime.utc(2024, 1, 1),
        entries: [
          ManifestEntry(
            id: 'a',
            contentHash: 'h',
            modifiedAt: DateTime.utc(2024, 1, 2),
            deleted: false,
          ),
        ],
      );
      final rt = RemoteManifest.fromJsonString(m.toJsonString());
      expect(rt.entries.single.id, 'a');
      expect(rt.entries.single.contentHash, 'h');
      expect(rt.entries.single.deleted, isFalse);
    });

    test('manifest v2 round-trips restore metadata + tolerates v1 entries', () {
      final manifest = SyncService.buildManifest(
        [
          VaultedFile(
            id: 'a',
            originalName: 'a.jpg',
            vaultPath: '/v/a',
            type: VaultedFileType.image,
            mimeType: 'image/jpeg',
            fileSize: 5,
            dateAdded: DateTime(2024, 1, 1),
            modifiedAt: DateTime(2024, 1, 1),
            isEncrypted: true,
            encryptionIv: 'iv',
            keyDerivationSalt: 'salt',
            kdfIterations: 1000,
            encryptionAlgorithm: EncryptionAlgorithm.aes256Gcm,
            tags: const ['t'],
            isFavorite: true,
            albumIds: const ['al'],
            folderId: 'f1',
          ),
        ],
        deviceId: 'd',
        now: DateTime.utc(2024, 6, 1),
      );
      expect(manifest.version, 2);
      final e = RemoteManifest.fromJsonString(manifest.toJsonString())
          .entries
          .single;
      expect(e.originalName, 'a.jpg');
      expect(e.type, 'image');
      expect(e.mimeType, 'image/jpeg');
      expect(e.isEncrypted, isTrue);
      expect(e.encryptionIv, 'iv');
      expect(e.encryptionAlgorithm, 'aes256Gcm');
      expect(e.kdfIterations, 1000);
      expect(e.tags, ['t']);
      expect(e.isFavorite, isTrue);
      expect(e.albumIds, ['al']);
      expect(e.folderId, 'f1');

      // v1 read-compat: a manifest missing the v2 keys defaults sanely.
      const v1Json = '{"version":1,"deviceId":"d",'
          '"generatedAt":"2024-01-01T00:00:00.000Z",'
          '"entries":[{"id":"x","contentHash":null,'
          '"modifiedAt":"2024-01-01T00:00:00.000Z","deleted":false}]}';
      final v1 = RemoteManifest.fromJsonString(v1Json);
      expect(v1.entries.single.tags, isEmpty);
      expect(v1.entries.single.isEncrypted, isFalse);
      expect(v1.entries.single.encryptionAlgorithm, isNull);
    });
  });

  group('runSync', () {
    test('push-only: every local file gets a remote blob + manifest lists it, '
        'and re-running is idempotent', () async {
      final dir = await Directory.systemTemp.createTemp('locker_sync_');
      final payloads = [
        Uint8List.fromList([1, 2, 3, 4]),
        Uint8List.fromList([5, 6, 7, 8, 9]),
      ];
      final paths = <String>[];
      for (var i = 0; i < payloads.length; i++) {
        final f = File('${dir.path}/blob$i.enc');
        await f.writeAsBytes(payloads[i]);
        paths.add(f.path);
      }

      final local = [
        VaultedFile(
          id: 'a',
          originalName: 'a.jpg',
          vaultPath: paths[0],
          type: VaultedFileType.image,
          mimeType: 'image/jpeg',
          fileSize: 4,
          dateAdded: DateTime(2024, 1, 1),
          modifiedAt: DateTime(2024, 1, 1),
        ),
        VaultedFile(
          id: 'b',
          originalName: 'b.mp4',
          vaultPath: paths[1],
          type: VaultedFileType.video,
          mimeType: 'video/mp4',
          fileSize: 5,
          dateAdded: DateTime(2024, 1, 2),
          modifiedAt: DateTime(2024, 1, 2),
        ),
      ];
      final masterKey = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final remote = _MemStore();

      final result = await SyncService.runSync(
        local: local,
        masterKey: masterKey,
        remote: remote,
        deviceId: 'dev1',
        now: DateTime.utc(2024, 6, 1),
      );

      expect(result.blobsPushed, 2);
      expect(result.blobsDeleted, 0);
      expect(result.blobsPulled, 0);

      final listed = await remote.listBlobs();
      expect(listed.length, 2);

      final manifest = SyncService.decryptManifest(
        (await remote.getManifest())!,
        masterKey,
      );
      expect(manifest.deviceId, 'dev1');
      expect(manifest.entries.map((e) => e.id).toSet(), {'a', 'b'});
      expect(manifest.entries.every((e) => e.contentHash != null), isTrue);

      // Each manifest entry resolves to a real, matching blob.
      for (final entry in manifest.entries) {
        final blob =
            await remote.getBlob(SyncService.blobNameFor(entry.contentHash!));
        expect(blob, isNotNull);
        expect(SyncService.sha256Hex(blob!), entry.contentHash);
      }

      // Refreshed local carries the new remoteHashes.
      expect(
        result.refreshedLocal.every((f) => f.remoteHash != null),
        isTrue,
      );

      // Re-running with the refreshed index pushes nothing (in-sync).
      final result2 = await SyncService.runSync(
        local: result.refreshedLocal,
        masterKey: masterKey,
        remote: remote,
        deviceId: 'dev1',
        now: DateTime.utc(2024, 6, 2),
      );
      expect(result2.blobsPushed, 0);
      expect((await remote.listBlobs()).length, 2);

      await dir.delete(recursive: true);
    });

    test(
        'push-only: a local file whose blob is missing on disk is skipped, '
        'not fatal (e.g. a deleted password shadow entry)', () async {
      final dir = await Directory.systemTemp.createTemp('locker_sync_skip_');
      final live = File('${dir.path}/live.enc');
      await live.writeAsBytes(Uint8List.fromList([1, 2, 3, 4]));
      final masterKey = Uint8List.fromList(List<int>.generate(32, (i) => i));

      final local = [
        VaultedFile(
          id: 'live',
          originalName: 'live.jpg',
          vaultPath: live.path,
          type: VaultedFileType.image,
          mimeType: 'image/jpeg',
          fileSize: 4,
          dateAdded: DateTime(2024, 1, 1),
          modifiedAt: DateTime(2024, 1, 1),
        ),
        VaultedFile(
          id: 'orphan',
          originalName: 'orphan.pwd',
          vaultPath: '${dir.path}/passwords/never-written.enc',
          type: VaultedFileType.document,
          mimeType: 'application/octet-stream',
          fileSize: 0,
          dateAdded: DateTime(2024, 1, 2),
          modifiedAt: DateTime(2024, 1, 2),
        ),
      ];
      final remote = _MemStore();

      final result = await SyncService.runSync(
        local: local,
        masterKey: masterKey,
        remote: remote,
        deviceId: 'dev1',
        now: DateTime.utc(2024, 6, 1),
      );

      expect(result.blobsPushed, 1);
      expect(result.blobsSkipped, 1);
      // Only the live file produced a blob.
      expect((await remote.listBlobs()).length, 1);
      // The orphan is retained unchanged (sync never mutates local state
      // destructively) and carries no remote hash.
      final orphan = result.refreshedLocal.firstWhere((f) => f.id == 'orphan');
      expect(orphan.remoteHash, isNull);

      await dir.delete(recursive: true);
    });

    test('tombstone: reaps the remote blob and records a deleted entry',
        () async {
      final dir = await Directory.systemTemp.createTemp('locker_sync_tomb_');
      final f = File('${dir.path}/blob.enc');
      await f.writeAsBytes(Uint8List.fromList([10, 20, 30]));
      final masterKey = Uint8List(32);

      // First sync: push one live file.
      final remote = _MemStore();
      final live = VaultedFile(
        id: 'a',
        originalName: 'a',
        vaultPath: f.path,
        type: VaultedFileType.image,
        mimeType: 'image/jpeg',
        fileSize: 3,
        dateAdded: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );
      final r1 = await SyncService.runSync(
        local: [live],
        masterKey: masterKey,
        remote: remote,
        deviceId: 'dev1',
        now: DateTime.utc(2024, 6, 1),
      );
      expect((await remote.listBlobs()).length, 1);

      // Second sync: the file is now a tombstone locally.
      final tombstoned = r1.refreshedLocal.first
          .copyWith(syncedDeleted: true, modifiedAt: DateTime(2024, 6, 2));
      final r2 = await SyncService.runSync(
        local: [tombstoned],
        masterKey: masterKey,
        remote: remote,
        deviceId: 'dev1',
        now: DateTime.utc(2024, 6, 3),
      );
      expect(r2.blobsDeleted, 1);
      expect((await remote.listBlobs()).length, 0);

      final manifest = SyncService.decryptManifest(
        (await remote.getManifest())!,
        masterKey,
      );
      expect(manifest.entries.single.deleted, isTrue);

      await dir.delete(recursive: true);
    });

    test('two-way: device B pulls a file device A pushed', () async {
      final dirA = await Directory.systemTemp.createTemp('locker_tw_a_');
      final dirB = await Directory.systemTemp.createTemp('locker_tw_b_');
      final masterKey = Uint8List(32);
      final remote = _MemStore();

      final blobA = Uint8List.fromList([1, 2, 3, 4, 5]);
      final pathA = '${dirA.path}/images/a.jpg';
      await File(pathA).parent.create(recursive: true);
      await File(pathA).writeAsBytes(blobA);
      final fileA = VaultedFile(
        id: 'a',
        originalName: 'a.jpg',
        vaultPath: pathA,
        type: VaultedFileType.image,
        mimeType: 'image/jpeg',
        fileSize: 5,
        dateAdded: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
        isEncrypted: true,
        encryptionIv: 'iv',
        keyDerivationSalt: 'salt',
        kdfIterations: 1000,
        encryptionAlgorithm: EncryptionAlgorithm.aes256Gcm,
        tags: const ['t'],
      );

      // A pushes.
      final rA = await SyncService.runSync(
        local: [fileA],
        masterKey: masterKey,
        remote: remote,
        deviceId: 'A',
        vaultRoot: dirA.path,
        direction: SyncDirection.twoWay,
        now: DateTime.utc(2024, 6, 1),
      );
      expect(rA.blobsPushed, 1);

      // B pulls (empty local).
      final rB = await SyncService.runSync(
        local: const [],
        masterKey: masterKey,
        remote: remote,
        deviceId: 'B',
        vaultRoot: dirB.path,
        direction: SyncDirection.twoWay,
        now: DateTime.utc(2024, 6, 2),
      );
      expect(rB.blobsPulled, 1);
      expect(rB.refreshedLocal.length, 1);
      final pulled = rB.refreshedLocal.single;
      expect(pulled.id, 'a');
      expect(pulled.originalName, 'a.jpg');
      expect(pulled.type, VaultedFileType.image);
      expect(pulled.isEncrypted, isTrue);
      expect(pulled.encryptionIv, 'iv');
      expect(pulled.encryptionAlgorithm, EncryptionAlgorithm.aes256Gcm);
      expect(pulled.kdfIterations, 1000);
      expect(pulled.tags, ['t']);
      expect(pulled.remoteHash, rA.refreshedLocal.first.remoteHash);
      expect(await File(pulled.vaultPath).exists(), isTrue);
      expect(await File(pulled.vaultPath).readAsBytes(), blobA);

      await dirA.delete(recursive: true);
      await dirB.delete(recursive: true);
    });

    test('two-way: device B edits → device A pulls the edit', () async {
      final dirA = await Directory.systemTemp.createTemp('locker_edit_a_');
      final dirB = await Directory.systemTemp.createTemp('locker_edit_b_');
      final masterKey = Uint8List(32);
      final remote = _MemStore();

      // Seed A with a file and push.
      final pathA = '${dirA.path}/images/a.jpg';
      await File(pathA).parent.create(recursive: true);
      await File(pathA).writeAsBytes(Uint8List.fromList([1, 1, 1]));
      final seeded = VaultedFile(
        id: 'a',
        originalName: 'a.jpg',
        vaultPath: pathA,
        type: VaultedFileType.image,
        mimeType: 'image/jpeg',
        fileSize: 3,
        dateAdded: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );
      await SyncService.runSync(
        local: [seeded],
        masterKey: masterKey,
        remote: remote,
        deviceId: 'A',
        vaultRoot: dirA.path,
        direction: SyncDirection.twoWay,
        now: DateTime.utc(2024, 6, 1),
      );

      // B pulls.
      final rB = await SyncService.runSync(
        local: const [],
        masterKey: masterKey,
        remote: remote,
        deviceId: 'B',
        vaultRoot: dirB.path,
        direction: SyncDirection.twoWay,
        now: DateTime.utc(2024, 6, 2),
      );
      final onB = rB.refreshedLocal.single;

      // B edits: new ciphertext bytes + bumped modifiedAt (remoteHash goes stale).
      final edited = Uint8List.fromList([2, 2, 2, 2]);
      await File(onB.vaultPath).writeAsBytes(edited);
      final bEdited = onB.copyWith(modifiedAt: DateTime(2024, 6, 3));

      // B pushes the edit.
      await SyncService.runSync(
        local: [bEdited],
        masterKey: masterKey,
        remote: remote,
        deviceId: 'B',
        vaultRoot: dirB.path,
        direction: SyncDirection.twoWay,
        now: DateTime.utc(2024, 6, 3),
      );

      // A pulls the edit using A's refreshed index from the first push.
      final rA2 = await SyncService.runSync(
        local: [
          VaultedFile(
            id: 'a',
            originalName: 'a.jpg',
            vaultPath: pathA,
            type: VaultedFileType.image,
            mimeType: 'image/jpeg',
            fileSize: 3,
            dateAdded: DateTime(2024, 1, 1),
            modifiedAt: DateTime(2024, 1, 1),
            remoteHash: rB.refreshedLocal.first.remoteHash,
          ),
        ],
        masterKey: masterKey,
        remote: remote,
        deviceId: 'A',
        vaultRoot: dirA.path,
        direction: SyncDirection.twoWay,
        now: DateTime.utc(2024, 6, 4),
      );
      expect(rA2.blobsPulled, 1);
      final onA = rA2.refreshedLocal.single;
      expect(await File(onA.vaultPath).readAsBytes(), edited);
      expect(onA.remoteHash, isNot(rB.refreshedLocal.first.remoteHash));

      await dirA.delete(recursive: true);
      await dirB.delete(recursive: true);
    });

    test('two-way: device A deletes → device B tombstones locally', () async {
      final dirA = await Directory.systemTemp.createTemp('locker_del_a_');
      final dirB = await Directory.systemTemp.createTemp('locker_del_b_');
      final masterKey = Uint8List(32);
      final remote = _MemStore();

      // A seeds + pushes.
      final pathA = '${dirA.path}/images/a.jpg';
      await File(pathA).parent.create(recursive: true);
      await File(pathA).writeAsBytes(Uint8List.fromList([9, 9]));
      final rA = await SyncService.runSync(
        local: [
          VaultedFile(
            id: 'a',
            originalName: 'a.jpg',
            vaultPath: pathA,
            type: VaultedFileType.image,
            mimeType: 'image/jpeg',
            fileSize: 2,
            dateAdded: DateTime(2024, 1, 1),
            modifiedAt: DateTime(2024, 1, 1),
          ),
        ],
        masterKey: masterKey,
        remote: remote,
        deviceId: 'A',
        vaultRoot: dirA.path,
        direction: SyncDirection.twoWay,
        now: DateTime.utc(2024, 6, 1),
      );

      // B pulls the live file.
      final rB = await SyncService.runSync(
        local: const [],
        masterKey: masterKey,
        remote: remote,
        deviceId: 'B',
        vaultRoot: dirB.path,
        direction: SyncDirection.twoWay,
        now: DateTime.utc(2024, 6, 2),
      );
      final onB = rB.refreshedLocal.single;
      expect(await File(onB.vaultPath).exists(), isTrue);

      // A deletes (tombstone) + pushes; blob reaped.
      final tombstoned =
          rA.refreshedLocal.first.copyWith(syncedDeleted: true);
      await SyncService.runSync(
        local: [tombstoned],
        masterKey: masterKey,
        remote: remote,
        deviceId: 'A',
        vaultRoot: dirA.path,
        direction: SyncDirection.twoWay,
        now: DateTime.utc(2024, 6, 3),
      );
      expect((await remote.listBlobs()).length, 0);

      // B syncs again → remote tombstone propagates, B's file is deleted.
      final rB2 = await SyncService.runSync(
        local: rB.refreshedLocal,
        masterKey: masterKey,
        remote: remote,
        deviceId: 'B',
        vaultRoot: dirB.path,
        direction: SyncDirection.twoWay,
        now: DateTime.utc(2024, 6, 4),
      );
      final bAfter = rB2.refreshedLocal.single;
      expect(bAfter.syncedDeleted, isTrue);
      expect(await File(onB.vaultPath).exists(), isFalse);

      await dirA.delete(recursive: true);
      await dirB.delete(recursive: true);
    });
  });
}

/// In-memory RemoteStore for runSync tests — no network.
class _MemStore implements RemoteStore {
  final Map<String, Uint8List> _blobs = {};
  Uint8List? _manifest;

  @override
  Future<void> testConnection() async {}

  @override
  Future<Uint8List?> getManifest() async => _manifest;

  @override
  Future<void> putManifest(Uint8List bytes) async => _manifest = bytes;

  @override
  Future<void> putBlob(String name, Uint8List bytes) async =>
      _blobs[name] = bytes;

  @override
  Future<Uint8List?> getBlob(String name) async => _blobs[name];

  @override
  Future<void> deleteBlob(String name) async => _blobs.remove(name);

  @override
  Future<List<String>> listBlobs() async => _blobs.keys.toList();
}
