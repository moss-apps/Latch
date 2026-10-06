import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../models/album.dart';
import '../models/smart_collection.dart';
import '../models/vault_file_filter.dart';
import '../models/vaulted_file.dart';
import '../services/smart_collection_service.dart';
import 'vault_providers.dart';

final smartCollectionServiceProvider = Provider<SmartCollectionService>((ref) {
  return SmartCollectionService.instance;
});

/// Bumped when the local calendar month rolls over so relative-date
/// collections recompute even while the app stays open.
final smartCollectionClockProvider = StateProvider<int>((ref) => 0);

class SmartCollectionsNotifier
    extends Notifier<AsyncValue<List<SmartCollection>>> {
  Timer? _monthTimer;

  @override
  AsyncValue<List<SmartCollection>> build() {
    ref.watch(isDecoyModeProvider);
    _scheduleMonthBoundary();
    ref.onDispose(() => _monthTimer?.cancel());
    _load();
    return const AsyncValue.loading();
  }

  void _scheduleMonthBoundary() {
    _monthTimer?.cancel();
    final now = DateTime.now();
    final nextMonth = DateTime(now.year, now.month + 1, 1);
    final delay = nextMonth.difference(now) + const Duration(seconds: 1);
    _monthTimer = Timer(delay, () {
      if (!ref.mounted) return;
      ref.read(smartCollectionClockProvider.notifier).state++;
      _scheduleMonthBoundary();
    });
  }

  Future<void> _load() async {
    final isDecoy = ref.read(isDecoyModeProvider);
    try {
      final collections = await ref
          .read(smartCollectionServiceProvider)
          .load(isDecoy: isDecoy);
      if (!ref.mounted) return;
      state = AsyncValue.data(collections);
    } catch (e, st) {
      if (!ref.mounted) return;
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> reload() async {
    final isDecoy = ref.read(isDecoyModeProvider);
    try {
      final collections = await ref
          .read(smartCollectionServiceProvider)
          .load(isDecoy: isDecoy, forceReload: true);
      if (!ref.mounted) return;
      state = AsyncValue.data(collections);
    } catch (e, st) {
      if (!ref.mounted) return;
      state = AsyncValue.error(e, st);
    }
  }

  Future<SmartCollection?> create({
    required String name,
    required VaultFileFilter filter,
    SmartCollectionWindow window = SmartCollectionWindow.none,
    SortOption? sortOption,
  }) async {
    final isDecoy = ref.read(isDecoyModeProvider);
    try {
      final collection =
          await ref.read(smartCollectionServiceProvider).create(
                name: name,
                filter: filter,
                window: window,
                sortOption: sortOption,
                isDecoy: isDecoy,
              );
      await _load();
      return collection;
    } catch (_) {
      return null;
    }
  }

  Future<bool> updateCollection(SmartCollection collection) async {
    final isDecoy = ref.read(isDecoyModeProvider);
    try {
      await ref
          .read(smartCollectionServiceProvider)
          .update(collection, isDecoy: isDecoy);
      await _load();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteCollection(String id) async {
    final isDecoy = ref.read(isDecoyModeProvider);
    try {
      final deleted = await ref
          .read(smartCollectionServiceProvider)
          .delete(id, isDecoy: isDecoy);
      if (deleted) await _load();
      return deleted;
    } catch (_) {
      return false;
    }
  }
}

final smartCollectionsProvider =
    NotifierProvider<SmartCollectionsNotifier, AsyncValue<List<SmartCollection>>>(
        () {
  return SmartCollectionsNotifier();
});

SmartCollection? _collectionById(
  List<SmartCollection> collections,
  String id,
) {
  for (final collection in collections) {
    if (collection.id == id) return collection;
  }
  return null;
}

Future<List<VaultedFile>> _evaluate(
  Ref ref,
  SmartCollection collection,
) async {
  final all = ref.watch(vaultNotifierProvider).value ?? const [];
  final now = DateTime.now();
  final files =
      all.where((file) => collection.matches(file, now: now)).toList();
  final SortOption option = collection.sortOption ?? ref.watch(sortOptionProvider);
  return ref.read(vaultServiceProvider).sortFiles(files, option);
}

/// Live results for one collection. Watches vault state, the collection
/// definition, and the month-rollover clock.
final smartCollectionResultsProvider =
    FutureProvider.family<List<VaultedFile>, String>((ref, collectionId) async {
  ref.watch(smartCollectionClockProvider);
  final collections = ref.watch(smartCollectionsProvider).value;
  if (collections == null) return const [];
  final collection = _collectionById(collections, collectionId);
  if (collection == null) return const [];
  return _evaluate(ref, collection);
});

/// Live counts for every collection, used by the drawer and list screen.
final smartCollectionCountsProvider =
    FutureProvider<Map<String, int>>((ref) async {
  ref.watch(smartCollectionClockProvider);
  final collections = ref.watch(smartCollectionsProvider).value;
  final all = ref.watch(vaultNotifierProvider).value;
  if (collections == null || all == null) return const {};
  final now = DateTime.now();
  return {
    for (final collection in collections)
      collection.id:
          all.where((file) => collection.matches(file, now: now)).length,
  };
});
