import 'album.dart';
import 'vault_file_filter.dart';
import 'vaulted_file.dart';

/// Relative time window evaluated at match time instead of a fixed range.
enum SmartCollectionWindow {
  none,
  thisMonth;

  String get displayName {
    switch (this) {
      case SmartCollectionWindow.none:
        return 'None';
      case SmartCollectionWindow.thisMonth:
        return 'This Month';
    }
  }

  static SmartCollectionWindow fromString(String value) {
    switch (value.toLowerCase()) {
      case 'thismonth':
      case 'this_month':
        return SmartCollectionWindow.thisMonth;
      default:
        return SmartCollectionWindow.none;
    }
  }
}

/// A saved file filter that resolves its membership from current vault
/// metadata instead of storing file ids.
///
/// Definitions are local-only, like albums and folders. Presets ship with the
/// app and cannot be deleted, but their filters stay editable.
class SmartCollection {
  static const int currentFilterVersion = 1;

  final String id;
  final String name;
  final VaultFileFilter filter;
  final SmartCollectionWindow window;
  final SortOption? sortOption;
  final bool isPreset;
  final int filterVersion;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SmartCollection({
    required this.id,
    required this.name,
    this.filter = const VaultFileFilter(),
    this.window = SmartCollectionWindow.none,
    this.sortOption,
    this.isPreset = false,
    this.filterVersion = currentFilterVersion,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isCustom => !isPreset;

  /// The filter with relative windows pinned to [now]'s local calendar.
  VaultFileFilter resolveFilter({DateTime? now}) {
    if (window == SmartCollectionWindow.none) return filter;
    final reference = (now ?? DateTime.now()).toLocal();
    return filter.copyWith(
      dateFrom: DateTime(reference.year, reference.month, 1),
      dateTo: DateTime(reference.year, reference.month + 1, 0),
    );
  }

  bool matches(VaultedFile file, {DateTime? now}) =>
      resolveFilter(now: now).matches(file);

  SmartCollection copyWith({
    String? name,
    VaultFileFilter? filter,
    SmartCollectionWindow? window,
    SortOption? sortOption,
    bool clearSortOption = false,
    int? filterVersion,
    DateTime? updatedAt,
  }) {
    return SmartCollection(
      id: id,
      name: name ?? this.name,
      filter: filter ?? this.filter,
      window: window ?? this.window,
      sortOption: clearSortOption ? null : (sortOption ?? this.sortOption),
      isPreset: isPreset,
      filterVersion: filterVersion ?? this.filterVersion,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'filter': filter.toJson(),
        'window': window.name,
        'sortOption': sortOption?.name,
        'isPreset': isPreset,
        'filterVersion': filterVersion,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory SmartCollection.fromJson(Map<String, dynamic> json) {
    final filterJson = json['filter'];
    return SmartCollection(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Collection',
      filter: filterJson is Map<String, dynamic>
          ? VaultFileFilter.fromJson(filterJson)
          : const VaultFileFilter(),
      window: SmartCollectionWindow.fromString(
        json['window'] as String? ?? 'none',
      ),
      sortOption: _sortOptionFromString(json['sortOption'] as String?),
      isPreset: json['isPreset'] as bool? ?? false,
      filterVersion: (json['filterVersion'] as num?)?.toInt() ??
          currentFilterVersion,
      createdAt: _parseDate(json['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updatedAt']) ?? DateTime.now(),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  static SortOption? _sortOptionFromString(String? value) {
    if (value == null) return null;
    for (final option in SortOption.values) {
      if (option.name == value) return option;
    }
    return null;
  }

  static List<SmartCollection> presets() {
    final created = DateTime.utc(2024, 1, 1);
    return [
      SmartCollection(
        id: 'preset_untagged',
        name: 'Untagged',
        filter: const VaultFileFilter(onlyUntagged: true),
        createdAt: created,
        updatedAt: created,
        isPreset: true,
      ),
      SmartCollection(
        id: 'preset_unencrypted',
        name: 'Unencrypted',
        filter: const VaultFileFilter(isEncrypted: false),
        createdAt: created,
        updatedAt: created,
        isPreset: true,
      ),
      SmartCollection(
        id: 'preset_large_videos',
        name: 'Large Videos',
        filter: const VaultFileFilter(
          type: VaultedFileType.video,
          minSizeBytes: 100 * 1024 * 1024,
        ),
        sortOption: SortOption.sizeLargest,
        createdAt: created,
        updatedAt: created,
        isPreset: true,
      ),
      SmartCollection(
        id: 'preset_added_this_month',
        name: 'Added This Month',
        window: SmartCollectionWindow.thisMonth,
        sortOption: SortOption.dateAddedNewest,
        createdAt: created,
        updatedAt: created,
        isPreset: true,
      ),
    ];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is SmartCollection && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'SmartCollection($id, $name)';
}
