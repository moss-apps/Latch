// Live WebDAV roundtrip: S0.5 (transport) + Phase 3 two-device two-way.
// Env-gated — runs only with LOCKER_LIVE_WEBDAV_URL set. See
// docs/local_server_testing.md for server setup and the hardware guide.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
// import 'package:locker/models/encryption_algorithm.dart';
import 'package:locker/models/sync_profile.dart';
import 'package:locker/models/vaulted_file.dart';
import 'package:locker/services/remote/remote_store.dart';
import 'package:locker/services/remote/webdav_store.dart';
import 'package:locker/services/sync_control.dart';
import 'package:locker/services/sync_service.dart';

Map<String, String> get _env => Platform.environment;

bool get _liveEnabled => _env.containsKey('LOCKER_LIVE_WEBDAV_URL');

WebDAVStore _store(String basePath) => WebDAVStore(
      baseUrl: _env['LOCKER_LIVE_WEBDAV_URL']!,
      username: _env['LOCKER_LIVE_WEBDAV_USER'] ?? '',
      password: _env['LOCKER_LIVE_WEBDAV_PASS'] ?? '',
      basePath: basePath,
    );

// Isolates each run from prior runs.
String get _basePath => '/locker-live-${DateTime.now().microsecondsSinceEpoch}';

Future<void> _cleanup(WebDAVStore store) async {
  // listBlobs gives absolute paths; deleteBlob wants names relative to basePath.
  final base = store.basePath;
  try {
    for (final full in await store.listBlobs()) {
      final idx = full.indexOf(base);
      var rel = idx >= 0 ? full.substring(idx + base.length) : full;
      rel = rel.replaceAll(RegExp(r'^/+'), '');
      if (rel.isEmpty) continue;
      await store.deleteBlob(rel);
    }
  } catch (_) {}
}

VaultedFile _file({
  required String id,
  required String vaultPath,
  DateTime? modifiedAt,
  String? remoteHash,
  bool syncedDeleted = false,
}) {
  return VaultedFile(
    id: id,
    originalName: '$id.jpg',
    vaultPath: vaultPath,
    type: VaultedFileType.image,
    mimeType: 'image/jpeg',
    fileSize: 0,
    dateAdded: DateTime(2024, 1, 1),
    modifiedAt: modifiedAt,
    remoteHash: remoteHash,
    syncedDeleted: syncedDeleted,
  );
}

Future<String> _seedBlob(Directory dir, List<int> bytes, String name) async {
  final p = '${dir.path}/images/$name';
  await File(p).parent.create(recursive: true);
  await File(p).writeAsBytes(bytes);
  return p;
}

void main() {
  if (!_liveEnabled) {
    test('live WebDAV roundtrip (skipped: set LOCKER_LIVE_WEBDAV_URL to run)',
        () {});
    return;
  }

  group('S0.5 — WebDAVStore raw transport', () {
    test('ping, manifest + nested blob roundtrip, delete, list', () async {
      final basePath = _basePath;
      final store = _store(basePath);
      addTearDown(() => _cleanup(store));

      await store.testConnection();

      final manifest = Uint8List.fromList([1, 2, 3, 4, 5]);
      await store.putManifest(manifest);
      expect(await store.getManifest(), manifest);

      // Nested sharded path (ab/cd/…): proves parent-collection auto-create —
      // the spec-strict-server case the unit suite can't reach.
      final blob = Uint8List.fromList(List<int>.generate(64, (i) => i));
      final hash = SyncService.sha256Hex(blob);
      final name = SyncService.blobNameFor(hash);
      await store.putBlob(name, blob);
      expect(await store.getBlob(name), blob);
      expect(SyncService.sha256Hex((await store.getBlob(name))!), hash);

      expect(await store.getBlob('ff/00/does-not-exist.enc'), isNull);

      final listed = await store.listBlobs();
      expect(listed.any((p) => p.endsWith('manifest.enc')), isTrue);
      expect(listed.any((p) => p.endsWith('$hash.enc')), isTrue);

      await store.deleteBlob(name);
      expect(await store.getBlob(name), isNull);
      expect(await store.getManifest(), manifest);
    });
  });

  group('S3.5 — guarded publication over a live server', () {
    test('publish, replace under the probe, and refuse a stale revision', () async {
      final store = _store(_basePath);
      addTearDown(() => _cleanup(store));

      await store.publishManifest(Uint8List.fromList([1, 2, 3]), null, SyncControl());
      // rclone cannot honor ETag preconditions; the probe must fall back to locks.
      expect(store.usesLockPublication, isTrue);
      final first = await store.readManifest(SyncControl());
      expect(first.bytes, Uint8List.fromList([1, 2, 3]));

      await store.publishManifest(Uint8List.fromList([4, 5, 6]), first.revision, SyncControl());
      final second = await store.readManifest(SyncControl());
      expect(second.bytes, Uint8List.fromList([4, 5, 6]));

      // The first revision is stale now; the guard must refuse it.
      await expectLater(
        store.publishManifest(Uint8List.fromList([7]), first.revision, SyncControl()),
        throwsA(isA<RemoteRevisionChanged>()),
      );
      expect((await store.readManifest(SyncControl())).bytes, Uint8List.fromList([4, 5, 6]));
    });
  });

  group('S3.4 — two-device two-way runSync over a live server', () {
    final masterKey = Uint8List(32);

    test('A pushes → B pulls; B edits → A pulls; A deletes → B tombstones',
        () async {
      final basePath = _basePath;
      final remote = _store(basePath);
      addTearDown(() => _cleanup(remote));

      final dirA = await Directory.systemTemp.createTemp('locker_live_a_');
      final dirB = await Directory.systemTemp.createTemp('locker_live_b_');
      addTearDown(() async {
        await dirA.delete(recursive: true);
        await dirB.delete(recursive: true);
      });

      // --- A seeds one file and pushes. ---
      final blobA = [10, 20, 30, 40];
      final pathA = await _seedBlob(dirA, blobA, 'a.jpg');
      final rA = await SyncService.runSync(
        local: [
          _file(id: 'a', vaultPath: pathA, modifiedAt: DateTime(2024, 1, 1))
        ],
        masterKey: masterKey,
        remote: remote,
        deviceId: 'A',
        vaultRoot: dirA.path,
        direction: SyncDirection.twoWay,
        now: DateTime.utc(2024, 6, 1),
      );
      expect(rA.blobsPushed, 1);

      final mBytes = await remote.getManifest();
      expect(mBytes, isNotNull);
      expect(mBytes!.length, greaterThan(16 + 16)); // IV + GCM tag + ciphertext
      final manifest = SyncService.decryptManifest(mBytes, masterKey);
      expect(manifest.entries.single.id, 'a');
      final aHash = manifest.entries.single.contentHash!;
      final liveBlob = await remote.getBlob(SyncService.blobNameFor(aHash));
      expect(liveBlob, Uint8List.fromList(blobA));

      // --- B pulls (empty local) and reconstructs the file. ---
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
      final onB = rB.refreshedLocal.single;
      expect(onB.id, 'a');
      expect(
          await File(onB.vaultPath).readAsBytes(), Uint8List.fromList(blobA));

      // --- B edits, pushes (baseline from its pull run). ---
      final edited = [99, 98, 97, 96, 95];
      await File(onB.vaultPath).writeAsBytes(edited);
      final editHash = SyncService.sha256Hex(Uint8List.fromList(edited));
      final rB3 = await SyncService.runSync(
        local: [
          onB.copyWith(modifiedAt: DateTime(2024, 6, 3)),
        ],
        masterKey: masterKey,
        remote: remote,
        deviceId: 'B',
        vaultRoot: dirB.path,
        direction: SyncDirection.twoWay,
        checkpoint: rB.checkpoint,
        now: DateTime.utc(2024, 6, 3),
      );
      expect(rB3.blobsPushed, 1);

      // --- A pulls the edit (baseline from A's push run). ---
      final rA2 = await SyncService.runSync(
        local: [
          _file(
            id: 'a',
            vaultPath: pathA,
            modifiedAt: DateTime(2024, 1, 1),
            remoteHash: onB.remoteHash, // original hash, now stale
          ),
        ],
        masterKey: masterKey,
        remote: remote,
        deviceId: 'A',
        vaultRoot: dirA.path,
        direction: SyncDirection.twoWay,
        checkpoint: rA.checkpoint,
        now: DateTime.utc(2024, 6, 4),
      );
      expect(rA2.blobsPulled, 1);
      // Pull writes a content-addressed path; the old seed file is retained.
      final onA = rA2.refreshedLocal.first;
      expect(
          await File(onA.vaultPath).readAsBytes(), Uint8List.fromList(edited));

      // --- A tombstones + pushes; the manifest marks it deleted but the
      // remote blob is retained for recovery (Phase 3 keeps payloads). ---
      final tomb = rA2.refreshedLocal.first.copyWith(syncedDeleted: true);
      final rA3 = await SyncService.runSync(
        local: [tomb],
        masterKey: masterKey,
        remote: remote,
        deviceId: 'A',
        vaultRoot: dirA.path,
        direction: SyncDirection.twoWay,
        checkpoint: rA2.checkpoint,
        now: DateTime.utc(2024, 6, 5),
      );
      expect(rA3.filesDeleted, 1);
      final listed = await remote.listBlobs();
      expect(listed.any((p) => p.endsWith('$editHash.enc')), isTrue);
      final tombManifest = SyncService.decryptManifest(
        (await remote.getManifest())!,
        masterKey,
      );
      expect(tombManifest.entries.single.id, 'a');
      expect(tombManifest.entries.single.deleted, isTrue);

      // --- B syncs again: the remote tombstone drops B's index entry, and
      // B's payload stays on disk for recovery. ---
      final rB2 = await SyncService.runSync(
        local: [
          onB.copyWith(remoteHash: editHash),
        ],
        masterKey: masterKey,
        remote: remote,
        deviceId: 'B',
        vaultRoot: dirB.path,
        direction: SyncDirection.twoWay,
        checkpoint: rB3.checkpoint,
        now: DateTime.utc(2024, 6, 6),
      );
      expect(rB2.plan.toTombstoneLocal, contains('a'));
      expect(rB2.refreshedLocal, isEmpty);
      expect(await File(onB.vaultPath).exists(), isTrue);
    });

    test('pull rejects a tampered blob (hash mismatch)', () async {
      final basePath = _basePath;
      final remote = _store(basePath);
      addTearDown(() => _cleanup(remote));

      final dirA = await Directory.systemTemp.createTemp('locker_live_tamp_a_');
      final dirB = await Directory.systemTemp.createTemp('locker_live_tamp_b_');
      addTearDown(() async {
        await dirA.delete(recursive: true);
        await dirB.delete(recursive: true);
      });

      final pathA = await _seedBlob(dirA, [1, 2, 3], 'a.jpg');
      await SyncService.runSync(
        local: [
          _file(id: 'a', vaultPath: pathA, modifiedAt: DateTime(2024, 1, 1))
        ],
        masterKey: masterKey,
        remote: remote,
        deviceId: 'A',
        vaultRoot: dirA.path,
        direction: SyncDirection.twoWay,
        now: DateTime.utc(2024, 6, 1),
      );

      // Swap ciphertext bytes; the blob sha256 no longer matches the manifest.
      final m =
          SyncService.decryptManifest((await remote.getManifest())!, masterKey);
      final name = SyncService.blobNameFor(m.entries.single.contentHash!);
      final good = (await remote.getBlob(name))!;
      good[0] ^= 0xFF;
      await remote.putBlob(name, good);

      await expectLater(
        SyncService.runSync(
          local: const [],
          masterKey: masterKey,
          remote: remote,
          deviceId: 'B',
          vaultRoot: dirB.path,
          direction: SyncDirection.twoWay,
          now: DateTime.utc(2024, 6, 2),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
