import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../models/album.dart';
import '../models/smart_collection.dart';
import '../models/vault_file_filter.dart';

/// Persists smart collection definitions (filter JSON only, never membership).
///
/// Local-only for now, same scope as albums and folders. Definitions live in
/// secure storage under separate real/decoy keys.
class SmartCollectionService {
  SmartCollectionService._();
  static final SmartCollectionService instance = SmartCollectionService._();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  static const String _collectionsKey = 'locker_smart_collections';
  static const String _collectionsDecoyKey = 'locker_smart_collections_decoy';

  final Map<bool, List<SmartCollection>> _cache = {};

  String _keyFor(bool isDecoy) =>
      isDecoy ? _collectionsDecoyKey : _collectionsKey;

  /// Stored definitions merged with any preset missing from storage.
  Future<List<SmartCollection>> load({
    bool isDecoy = false,
    bool forceReload = false,
  }) async {
    if (!forceReload) {
      final cached = _cache[isDecoy];
      if (cached != null) return cached;
    }

    final json = await _secureStorage.read(key: _keyFor(isDecoy));
    final collections = <SmartCollection>[];
    if (json != null && json.isNotEmpty) {
      try {
        final decoded = jsonDecode(json) as List<dynamic>;
        for (final entry in decoded) {
          try {
            collections.add(
              SmartCollection.fromJson(entry as Map<String, dynamic>),
            );
          } catch (_) {
            // ponytail: skip malformed entry, keep the rest
          }
        }
      } catch (_) {
        // unreadable index falls back to presets below
      }
    }

    final existingIds = collections.map((c) => c.id).toSet();
    final missing =
        SmartCollection.presets().where((p) => !existingIds.contains(p.id));
    if (missing.isNotEmpty) {
      collections.addAll(missing);
    }

    collections.sort((a, b) {
      if (a.isPreset != b.isPreset) return a.isPreset ? -1 : 1;
      return a.createdAt.compareTo(b.createdAt);
    });

    _cache[isDecoy] = collections;
    if (missing.isNotEmpty && json != null && json.isNotEmpty) {
      try {
        await _persist(collections, isDecoy: isDecoy);
      } catch (_) {
        // keep the merged view in cache even if storage rejects the update
      }
    }
    return collections;
  }

  /// Writes first, then updates the cache so a failed write leaves the
  /// previous definitions intact.
  Future<void> save(
    List<SmartCollection> collections, {
    bool isDecoy = false,
  }) async {
    await _persist(collections, isDecoy: isDecoy);
    _cache[isDecoy] = List.of(collections);
  }

  Future<void> _persist(
    List<SmartCollection> collections, {
    required bool isDecoy,
  }) async {
    final json = jsonEncode(collections.map((c) => c.toJson()).toList());
    await _secureStorage.write(key: _keyFor(isDecoy), value: json);
  }

  Future<SmartCollection> create({
    required String name,
    required VaultFileFilter filter,
    SmartCollectionWindow window = SmartCollectionWindow.none,
    SortOption? sortOption,
    bool isDecoy = false,
  }) async {
    final now = DateTime.now();
    final collection = SmartCollection(
      id: const Uuid().v4(),
      name: name.trim(),
      filter: filter,
      window: window,
      sortOption: sortOption,
      createdAt: now,
      updatedAt: now,
    );
    final current = await load(isDecoy: isDecoy);
    await save([...current, collection], isDecoy: isDecoy);
    return collection;
  }

  Future<void> update(SmartCollection collection, {bool isDecoy = false}) async {
    final current = await load(isDecoy: isDecoy);
    final updated = collection.copyWith(updatedAt: DateTime.now());
    final next = [
      for (final existing in current)
        existing.id == updated.id ? updated : existing,
    ];
    await save(next, isDecoy: isDecoy);
  }

  /// Presets are not deletable; returns false instead of throwing.
  Future<bool> delete(String id, {bool isDecoy = false}) async {
    final current = await load(isDecoy: isDecoy);
    SmartCollection? target;
    for (final collection in current) {
      if (collection.id == id) {
        target = collection;
        break;
      }
    }
    if (target == null || target.isPreset) return false;
    await save(
      current.where((c) => c.id != id).toList(),
      isDecoy: isDecoy,
    );
    return true;
  }

  Future<void> clear({bool isDecoy = false}) async {
    await _secureStorage.delete(key: _keyFor(isDecoy));
    _cache.remove(isDecoy);
  }

  /// Called on lock so definitions re-read from secure storage next session.
  void clearCache() {
    _cache.clear();
  }
}
