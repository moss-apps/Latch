import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/remote_manifest.dart';
import 'package:locker/models/sync_conflict.dart';
import 'package:locker/models/sync_profile.dart';
import 'package:locker/services/sync_state_store.dart';

const _secureStorageChannel = 'plugins.it_nomads.com/flutter_secure_storage';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storage = <String, String>{};
  late Directory root;
  final key = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('latch_state_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(_secureStorageChannel),
      (call) async {
        final args = (call.arguments ?? {}) as Map;
        final name = args['key'] as String?;
        switch (call.method) {
          case 'read':
            return storage[name];
          case 'write':
            storage[name!] = args['value'] as String;
            return null;
          case 'delete':
            storage.remove(name);
            return null;
          case 'deleteAll':
            storage.clear();
            return null;
        }
        return null;
      },
    );
  });

  tearDown(() {
    storage.clear();
  });

  tearDownAll(() async {
    await root.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel(_secureStorageChannel), null);
  });

  test('deletion records persist and accumulate durably', () async {
    expect(await SyncStateStore.deletions(), isEmpty);
    await SyncStateStore.recordDeletion('a');
    await SyncStateStore.recordDeletion('b');
    final saved = await SyncStateStore.deletions();
    expect(saved.keys.toSet(), {'a', 'b'});
    expect(saved['a']!.isUtc, isTrue);
    final raw = storage['locker_sync_deletions']!;
    expect(jsonDecode(raw), isA<Map<String, dynamic>>());
  });

  test('checkpoint state round-trips encrypted and journal clears', () async {
    final store = SyncStateStore(root.path, key);
    final entry = ManifestEntry(
      id: 'a',
      contentHash: 'hash',
      modifiedAt: DateTime.utc(2024, 1, 2),
      originalName: 'a.jpg',
      tags: const ['one'],
    );
    final checkpoint = SyncCheckpoint(baseline: {'a': entry}, conflicts: [
      SyncConflict(
          local: entry,
          remote: entry.copyWith(tags: const ['two']),
          choice: ConflictChoice.remote),
    ]);
    await store.save('target', checkpoint.toJson());
    final loaded = await store.load('target');
    expect(loaded.baseline['a']!.tags, ['one']);
    expect(loaded.conflicts.single.choice, ConflictChoice.remote);

    await store.save('target', {'journal': true}, journal: true);
    expect(await store.read('target', journal: true), {'journal': true});
    await store.clearJournal('target');
    expect(await store.read('target', journal: true), isNull);
    expect(await store.load('target'), isNotNull);
  });

  test('no staging file survives and corrupt state fails loudly', () async {
    final store = SyncStateStore(root.path, key);
    await store.save('t2', {'baseline': {}, 'conflicts': []});
    final stateDir = Directory('${root.path}/.sync-state');
    expect(
        stateDir
            .listSync()
            .where((e) => e.path.endsWith('.tmp'))
            .isEmpty,
        isTrue);
    await File('${stateDir.path}/t2.state').writeAsBytes([1, 2, 3]);
    await expectLater(store.load('t2'), throwsFormatException);
  });

  test('target id is stable and distinguishes server, path and user', () {
    SyncProfile profile(String url, String path, String? user) => SyncProfile(
        id: 'p',
        serverUrl: url,
        basePath: path,
        username: user,
        direction: SyncDirection.twoWay,
        wifiOnly: false,
        enabled: true);
    final a = SyncStateStore.targetId(profile('https://nas/dav/', '/locker/', 'u'));
    final b = SyncStateStore.targetId(profile('https://nas/dav', '/locker', 'u'));
    final c = SyncStateStore.targetId(profile('https://other/dav', '/locker', 'u'));
    final d = SyncStateStore.targetId(profile('https://nas/dav', '/locker', 'v'));
    expect(a, b);
    expect(a, isNot(c));
    expect(a, isNot(d));
  });
}
