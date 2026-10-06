import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/album.dart';
import 'package:locker/models/smart_collection.dart';
import 'package:locker/models/vault_file_filter.dart';
import 'package:locker/models/vaulted_file.dart';
import 'package:locker/providers/smart_collection_providers.dart';
import 'package:locker/providers/vault_providers.dart';
import 'package:locker/services/smart_collection_service.dart';

const _secureStorageChannel = 'plugins.it_nomads.com/flutter_secure_storage';

class _FakeVaultNotifier extends VaultNotifier {
  _FakeVaultNotifier(this._state);

  AsyncValue<List<VaultedFile>> _state;

  @override
  AsyncValue<List<VaultedFile>> build() => _state;

  void setFiles(List<VaultedFile> files) {
    _state = AsyncValue.data(files);
    ref.invalidateSelf();
  }
}

/// `.future` alone does not keep a provider active across a dependency-driven
/// rebuild, so a test that reads a future while `smartCollectionsProvider` is
/// still loading would hang. Widgets hold a real subscription; mirror that.
Future<T> readFuture<T>(
  ProviderContainer container,
  FutureProvider<T> provider,
) async {
  container.listen(provider, (_, __) {});
  return container.read(provider.future);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> storage;
  late bool failWrites;
  final service = SmartCollectionService.instance;

  setUp(() {
    storage = {};
    failWrites = false;
    service.clearCache();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(_secureStorageChannel),
      (call) async {
        final args = (call.arguments ?? {}) as Map;
        final key = args['key'] as String?;
        switch (call.method) {
          case 'read':
            return storage[key];
          case 'write':
            if (failWrites) {
              throw PlatformException(code: 'write_failed');
            }
            storage[key!] = args['value'] as String;
            return null;
          case 'delete':
            storage.remove(key);
            return null;
          case 'deleteAll':
            storage.clear();
            return null;
          case 'containsKey':
            return storage.containsKey(key);
          case 'readAll':
            return storage;
          default:
            return null;
        }
      },
    );
  });

  VaultedFile makeFile(
    String id, {
    VaultedFileType type = VaultedFileType.image,
    int fileSize = 1024,
    List<String> tags = const [],
    bool isEncrypted = false,
    DateTime? dateAdded,
  }) {
    return VaultedFile(
      id: id,
      originalName: '$id.jpg',
      vaultPath: '/tmp/$id',
      type: type,
      mimeType: 'application/octet-stream',
      fileSize: fileSize,
      dateAdded: dateAdded ?? DateTime(2024, 1, 1),
      dateModified: dateAdded ?? DateTime(2024, 1, 1),
      tags: tags,
      isEncrypted: isEncrypted,
    );
  }

  List<String> storedIds({bool isDecoy = false}) {
    final json = storage[isDecoy
        ? 'locker_smart_collections_decoy'
        : 'locker_smart_collections'];
    if (json == null) return const [];
    return (jsonDecode(json) as List)
        .map((e) => (e as Map)['id'] as String)
        .toList();
  }

  group('SmartCollectionService persistence', () {
    test('empty storage yields the four presets', () async {
      final collections = await service.load();
      expect(collections.length, 4);
      expect(collections.every((c) => c.isPreset), isTrue);
      expect(
        collections.map((c) => c.id),
        containsAll([
          'preset_untagged',
          'preset_unencrypted',
          'preset_large_videos',
          'preset_added_this_month',
        ]),
      );
    });

    test('missing presets are merged and persisted alongside customs',
        () async {
      final custom = SmartCollection(
        id: 'custom-1',
        name: 'My Search',
        filter: const VaultFileFilter(nameQuery: 'invoice'),
        createdAt: DateTime(2024, 6, 1),
        updatedAt: DateTime(2024, 6, 1),
      );
      storage['locker_smart_collections'] = jsonEncode([custom.toJson()]);

      final collections = await service.load();

      expect(collections.length, 5);
      expect(collections.first.isPreset, isTrue);
      expect(collections.last.id, 'custom-1');
      expect(storedIds(), containsAll(['custom-1', 'preset_untagged']));
    });

    test('corrupt storage falls back to presets without throwing', () async {
      storage['locker_smart_collections'] = 'not json at all';
      final collections = await service.load();
      expect(collections.length, 4);
      expect(collections.every((c) => c.isPreset), isTrue);
    });

    test('malformed entries are skipped, the rest survives', () async {
      final custom = SmartCollection(
        id: 'custom-2',
        name: 'Keep Me',
        createdAt: DateTime(2024, 6, 1),
        updatedAt: DateTime(2024, 6, 1),
      );
      storage['locker_smart_collections'] = jsonEncode([
        custom.toJson(),
        {'id': null},
        'garbage'
      ]);

      final collections = await service.load();
      expect(collections.any((c) => c.id == 'custom-2'), isTrue);
      expect(collections.length, 5);
    });

    test('real and decoy namespaces stay isolated', () async {
      await service.create(
        name: 'Real One',
        filter: const VaultFileFilter(nameQuery: 'real'),
      );
      await service.create(
        name: 'Decoy One',
        filter: const VaultFileFilter(nameQuery: 'decoy'),
        isDecoy: true,
      );

      final real = await service.load();
      final decoy = await service.load(isDecoy: true);

      expect(real.any((c) => c.name == 'Real One'), isTrue);
      expect(real.any((c) => c.name == 'Decoy One'), isFalse);
      expect(decoy.any((c) => c.name == 'Decoy One'), isTrue);
      expect(decoy.any((c) => c.name == 'Real One'), isFalse);
    });

    test('custom collections survive a cache clear (restart)', () async {
      final created = await service.create(
        name: 'Persisted',
        filter: const VaultFileFilter(onlyUntagged: true),
      );
      service.clearCache();

      final collections = await service.load();
      final restored = collections.where((c) => c.id == created.id).firstOrNull;
      expect(restored, isNotNull);
      expect(restored!.name, 'Persisted');
      expect(restored.filter.onlyUntagged, isTrue);
    });

    test('a failed write leaves previous definitions intact', () async {
      final created = await service.create(
        name: 'Stable',
        filter: const VaultFileFilter(nameQuery: 'keep'),
      );
      failWrites = true;

      await expectLater(
        service.update(created.copyWith(name: 'Changed')),
        throwsA(isA<PlatformException>()),
      );

      failWrites = false;
      service.clearCache();
      final collections = await service.load();
      final restored = collections.where((c) => c.id == created.id).first;
      expect(restored.name, 'Stable');
    });

    test('update replaces the definition by id', () async {
      final created = await service.create(
        name: 'Original',
        filter: const VaultFileFilter(nameQuery: 'a'),
      );
      await service.update(
        created.copyWith(
          name: 'Renamed',
          filter: const VaultFileFilter(nameQuery: 'b'),
          sortOption: SortOption.sizeSmallest,
        ),
      );

      final collections = await service.load();
      final updated = collections.where((c) => c.id == created.id).first;
      expect(updated.name, 'Renamed');
      expect(updated.filter.nameQuery, 'b');
      expect(updated.sortOption, SortOption.sizeSmallest);
      expect(updated.updatedAt.isBefore(created.updatedAt), isFalse);
    });

    test('presets cannot be deleted, customs can', () async {
      expect(await service.delete('preset_untagged'), isFalse);
      expect((await service.load()).length, 4);

      final created = await service.create(
        name: 'Temp',
        filter: const VaultFileFilter(),
      );
      expect(await service.delete(created.id), isTrue);
      final collections = await service.load();
      expect(collections.any((c) => c.id == created.id), isFalse);
      expect(collections.length, 4);
    });

    test('clear removes stored definitions and cache', () async {
      await service.create(
        name: 'Gone',
        filter: const VaultFileFilter(),
      );
      await service.clear();
      expect(storage.containsKey('locker_smart_collections'), isFalse);

      final collections = await service.load();
      expect(collections.length, 4);
    });

    test('clear only touches the requested namespace', () async {
      await service.create(
        name: 'Real',
        filter: const VaultFileFilter(),
      );
      await service.create(
        name: 'Decoy',
        filter: const VaultFileFilter(),
        isDecoy: true,
      );

      await service.clear();

      final real = await service.load();
      final decoy = await service.load(isDecoy: true);
      expect(real.any((c) => c.name == 'Real'), isFalse);
      expect(decoy.any((c) => c.name == 'Decoy'), isTrue);
    });
  });

  group('SmartCollection matching', () {
    test('untagged preset follows metadata changes', () {
      final preset = SmartCollection.presets()
          .firstWhere((c) => c.id == 'preset_untagged');
      final file = makeFile('a', tags: const ['work']);

      expect(preset.matches(file), isFalse);
      expect(preset.matches(file.copyWith(tags: const [])), isTrue);
    });

    test('unencrypted preset follows encryption state', () {
      final preset = SmartCollection.presets()
          .firstWhere((c) => c.id == 'preset_unencrypted');
      expect(preset.matches(makeFile('a', isEncrypted: false)), isTrue);
      expect(preset.matches(makeFile('b', isEncrypted: true)), isFalse);
    });

    test('large videos preset respects type and size', () {
      final preset = SmartCollection.presets()
          .firstWhere((c) => c.id == 'preset_large_videos');
      const big = 150 * 1024 * 1024;
      const small = 10 * 1024 * 1024;

      expect(
        preset
            .matches(makeFile('a', type: VaultedFileType.video, fileSize: big)),
        isTrue,
      );
      expect(
        preset.matches(
            makeFile('b', type: VaultedFileType.video, fileSize: small)),
        isFalse,
      );
      expect(
        preset
            .matches(makeFile('c', type: VaultedFileType.image, fileSize: big)),
        isFalse,
      );
    });

    test('added this month resolves against the injected clock', () {
      final preset = SmartCollection.presets()
          .firstWhere((c) => c.id == 'preset_added_this_month');

      final resolved = preset.resolveFilter(now: DateTime(2024, 1, 15));
      expect(resolved.dateFrom, DateTime(2024, 1, 1));
      expect(resolved.dateTo, DateTime(2024, 1, 31));

      expect(
        preset.matches(makeFile('a', dateAdded: DateTime(2024, 1, 31, 23, 59)),
            now: DateTime(2024, 1, 15)),
        isTrue,
      );
      expect(
        preset.matches(makeFile('b', dateAdded: DateTime(2024, 2, 1)),
            now: DateTime(2024, 1, 15)),
        isFalse,
      );
      expect(
        preset.matches(makeFile('c', dateAdded: DateTime(2024, 2, 10)),
            now: DateTime(2024, 2, 1)),
        isTrue,
      );
    });

    test('relative window rolls over month and year boundaries', () {
      final preset = SmartCollection.presets()
          .firstWhere((c) => c.id == 'preset_added_this_month');

      final december = preset.resolveFilter(now: DateTime(2023, 12, 10));
      expect(december.dateFrom, DateTime(2023, 12, 1));
      expect(december.dateTo, DateTime(2023, 12, 31));

      final january = preset.resolveFilter(now: DateTime(2024, 1, 1));
      expect(january.dateFrom, DateTime(2024, 1, 1));
      expect(january.dateTo, DateTime(2024, 1, 31));
    });

    test('custom filters still match resolved windows', () {
      final collection = SmartCollection(
        id: 'c',
        name: 'Work this month',
        filter: const VaultFileFilter(tags: ['work']),
        window: SmartCollectionWindow.thisMonth,
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      );

      expect(
        collection.matches(
          makeFile('a', tags: const ['work'], dateAdded: DateTime(2024, 3, 5)),
          now: DateTime(2024, 3, 20),
        ),
        isTrue,
      );
      expect(
        collection.matches(
          makeFile('b', tags: const ['work'], dateAdded: DateTime(2024, 2, 5)),
          now: DateTime(2024, 3, 20),
        ),
        isFalse,
      );
      expect(
        collection.matches(
          makeFile('c', tags: const ['other'], dateAdded: DateTime(2024, 3, 5)),
          now: DateTime(2024, 3, 20),
        ),
        isFalse,
      );
    });
  });

  group('SmartCollection model', () {
    test('json round trip keeps filter, window, and sort', () {
      final original = SmartCollection(
        id: 'round-trip',
        name: 'Round Trip',
        filter: VaultFileFilter(
          nameQuery: 'rep',
          type: VaultedFileType.video,
          tags: const ['a', 'b'],
          minSizeBytes: 512,
          dateFrom: DateTime(2024, 2, 1),
          dateTo: DateTime(2024, 2, 29),
        ),
        window: SmartCollectionWindow.thisMonth,
        sortOption: SortOption.dateAddedOldest,
        createdAt: DateTime(2024, 1, 1, 12),
        updatedAt: DateTime(2024, 1, 2, 13),
      );

      final restored = SmartCollection.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.filter, original.filter);
      expect(restored.window, SmartCollectionWindow.thisMonth);
      expect(restored.sortOption, SortOption.dateAddedOldest);
      expect(
        restored.createdAt.isAtSameMomentAs(original.createdAt),
        isTrue,
      );
    });

    test('copyWith preserves identity and supports clearing sort', () {
      final original = SmartCollection(
        id: 'keep-id',
        name: 'Original',
        filter: const VaultFileFilter(),
        sortOption: SortOption.nameAsc,
        isPreset: true,
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      );

      final renamed = original.copyWith(name: 'New Name');
      expect(renamed.id, 'keep-id');
      expect(renamed.isPreset, isTrue);
      expect(renamed.sortOption, SortOption.nameAsc);

      final cleared = renamed.copyWith(clearSortOption: true);
      expect(cleared.sortOption, isNull);
    });

    test('presets carry stable identifiers and sort preferences', () {
      final presets = SmartCollection.presets();
      expect(presets.length, 4);
      expect(presets.every((c) => c.isPreset), isTrue);

      final videos = presets.firstWhere((c) => c.id == 'preset_large_videos');
      expect(videos.sortOption, SortOption.sizeLargest);
      expect(videos.filter.type, VaultedFileType.video);
      expect(videos.filter.minSizeBytes, 100 * 1024 * 1024);

      final month =
          presets.firstWhere((c) => c.id == 'preset_added_this_month');
      expect(month.window, SmartCollectionWindow.thisMonth);
      expect(month.sortOption, SortOption.dateAddedNewest);
    });
  });

  group('smart collection providers', () {
    test('counts and results derive from the vault file list', () async {
      final fake = _FakeVaultNotifier(AsyncValue.data([
        makeFile('tagged'),
        makeFile('encrypted', tags: const ['x'], isEncrypted: true),
        makeFile('big-video',
            type: VaultedFileType.video, fileSize: 200 * 1024 * 1024),
      ]));
      final container = ProviderContainer(overrides: [
        vaultNotifierProvider.overrideWith(() => fake),
      ]);
      addTearDown(container.dispose);

      final counts = await readFuture(container, smartCollectionCountsProvider);
      expect(counts['preset_untagged'], 2);
      expect(counts['preset_unencrypted'], 2);
      expect(counts['preset_large_videos'], 1);

      final videos = await readFuture(
          container, smartCollectionResultsProvider('preset_large_videos'));
      expect(videos.map((f) => f.id), ['big-video']);
    });

    test('membership refresh after a metadata change', () async {
      final fake = _FakeVaultNotifier(AsyncValue.data([
        makeFile('a', tags: const ['work']),
      ]));
      final container = ProviderContainer(overrides: [
        vaultNotifierProvider.overrideWith(() => fake),
      ]);
      addTearDown(container.dispose);

      var counts = await readFuture(container, smartCollectionCountsProvider);
      expect(counts['preset_untagged'], 0);

      fake.setFiles([makeFile('a')]);

      counts = await readFuture(container, smartCollectionCountsProvider);
      expect(counts['preset_untagged'], 1);
    });

    test('created collections produce live results', () async {
      final container = ProviderContainer(overrides: [
        vaultNotifierProvider.overrideWith(() => _FakeVaultNotifier(
              AsyncValue.data([makeFile('old', dateAdded: DateTime(2000))]),
            )),
      ]);
      addTearDown(container.dispose);

      final notifier = container.read(smartCollectionsProvider.notifier);
      final created = await notifier.create(
        name: 'Everything',
        filter: const VaultFileFilter(),
      );
      expect(created, isNotNull);

      final results = await readFuture(
          container, smartCollectionResultsProvider(created!.id));
      expect(results.map((f) => f.id), ['old']);

      final ok = await notifier.deleteCollection(created.id);
      expect(ok, isTrue);
      final afterDelete = await readFuture(
          container, smartCollectionResultsProvider(created.id));
      expect(afterDelete, isEmpty);
    });

    test('added-this-month preset tracks the current clock', () async {
      final container = ProviderContainer(overrides: [
        vaultNotifierProvider.overrideWith(() => _FakeVaultNotifier(
              AsyncValue.data([
                makeFile('recent', dateAdded: DateTime.now()),
                makeFile('ancient', dateAdded: DateTime(2000)),
              ]),
            )),
      ]);
      addTearDown(container.dispose);

      final results = await readFuture(
          container, smartCollectionResultsProvider('preset_added_this_month'));
      expect(results.map((f) => f.id), ['recent']);
    });
  });
}
