import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/remote_manifest.dart';
import 'package:locker/models/sync_profile.dart';
import 'package:locker/models/vaulted_file.dart';
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
      expect(dec.version, 1);
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
  });
}
