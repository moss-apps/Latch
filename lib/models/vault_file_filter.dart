import 'vaulted_file.dart';

/// Typed, serializable description of a vault file query.
///
/// One shared matcher for search, gallery filtering, and smart collections so
/// every surface agrees on semantics (notably: date ranges are calendar-day
/// inclusive on both ends).
class VaultFileFilter {
  /// Case-insensitive substring match against [VaultedFile.originalName].
  final String? nameQuery;

  /// All tags must be present (AND semantics, not OR).
  final List<String> tags;

  final VaultedFileType? type;
  final bool? isFavorite;

  /// Only files with no tags at all.
  final bool onlyUntagged;

  final bool? isEncrypted;
  final String? albumId;
  final String? folderId;

  final int? minSizeBytes;
  final int? maxSizeBytes;

  /// Inclusive local calendar day. A file added any time on this day matches.
  final DateTime? dateFrom;

  /// Inclusive local calendar day. A file added any time on this day matches.
  final DateTime? dateTo;

  const VaultFileFilter({
    this.nameQuery,
    this.tags = const [],
    this.type,
    this.isFavorite,
    this.onlyUntagged = false,
    this.isEncrypted,
    this.albumId,
    this.folderId,
    this.minSizeBytes,
    this.maxSizeBytes,
    this.dateFrom,
    this.dateTo,
  });

  bool get hasActiveFilters {
    return (nameQuery?.trim().isNotEmpty ?? false) ||
        tags.isNotEmpty ||
        type != null ||
        isFavorite != null ||
        onlyUntagged ||
        isEncrypted != null ||
        albumId != null ||
        folderId != null ||
        minSizeBytes != null ||
        maxSizeBytes != null ||
        dateFrom != null ||
        dateTo != null;
  }

  bool get isEmpty => !hasActiveFilters;

  int get activeFilterCount {
    var count = 0;
    if (nameQuery?.trim().isNotEmpty ?? false) count++;
    if (tags.isNotEmpty) count++;
    if (type != null) count++;
    if (isFavorite != null) count++;
    if (onlyUntagged) count++;
    if (isEncrypted != null) count++;
    if (albumId != null) count++;
    if (folderId != null) count++;
    if (minSizeBytes != null || maxSizeBytes != null) count++;
    if (dateFrom != null || dateTo != null) count++;
    return count;
  }

  /// Local calendar day (midnight) for [date]. Built directly from Y/M/D so
  /// DST shifts never turn a day boundary into 23:00 or 01:00.
  static DateTime dayOf(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  /// The next local calendar day after [date]. Constructed directly instead of
  /// adding 24h so DST transitions stay correct.
  static DateTime nextDayOf(DateTime date) =>
      DateTime(date.year, date.month, date.day + 1);

  bool matches(VaultedFile file) {
    final query = nameQuery?.trim();
    if (query != null && query.isNotEmpty) {
      if (!file.originalName.toLowerCase().contains(query.toLowerCase())) {
        return false;
      }
    }

    if (tags.isNotEmpty && !tags.every(file.hasTag)) {
      return false;
    }

    if (type != null && file.type != type) {
      return false;
    }

    if (isFavorite != null && file.isFavorite != isFavorite) {
      return false;
    }

    if (onlyUntagged && file.tags.isNotEmpty) {
      return false;
    }

    if (isEncrypted != null && file.isEncrypted != isEncrypted) {
      return false;
    }

    if (albumId != null && !file.isInAlbum(albumId!)) {
      return false;
    }

    if (folderId != null && file.folderId != folderId) {
      return false;
    }

    if (minSizeBytes != null && file.fileSize < minSizeBytes!) {
      return false;
    }

    if (maxSizeBytes != null && file.fileSize > maxSizeBytes!) {
      return false;
    }

    if (dateFrom != null || dateTo != null) {
      final fileDay = dayOf(file.dateAdded.toLocal());
      if (dateFrom != null && fileDay.isBefore(dayOf(dateFrom!))) {
        return false;
      }
      if (dateTo != null && fileDay.isAfter(dayOf(dateTo!))) {
        return false;
      }
    }

    return true;
  }

  VaultFileFilter copyWith({
    String? nameQuery,
    List<String>? tags,
    VaultedFileType? type,
    bool? isFavorite,
    bool? onlyUntagged,
    bool? isEncrypted,
    String? albumId,
    String? folderId,
    int? minSizeBytes,
    int? maxSizeBytes,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool clearNameQuery = false,
    bool clearType = false,
    bool clearIsFavorite = false,
    bool clearIsEncrypted = false,
    bool clearAlbumId = false,
    bool clearFolderId = false,
    bool clearMinSize = false,
    bool clearMaxSize = false,
    bool clearDateFrom = false,
    bool clearDateTo = false,
  }) {
    return VaultFileFilter(
      nameQuery: clearNameQuery ? null : (nameQuery ?? this.nameQuery),
      tags: tags ?? List<String>.from(this.tags),
      type: clearType ? null : (type ?? this.type),
      isFavorite: clearIsFavorite ? null : (isFavorite ?? this.isFavorite),
      onlyUntagged: onlyUntagged ?? this.onlyUntagged,
      isEncrypted: clearIsEncrypted ? null : (isEncrypted ?? this.isEncrypted),
      albumId: clearAlbumId ? null : (albumId ?? this.albumId),
      folderId: clearFolderId ? null : (folderId ?? this.folderId),
      minSizeBytes: clearMinSize ? null : (minSizeBytes ?? this.minSizeBytes),
      maxSizeBytes: clearMaxSize ? null : (maxSizeBytes ?? this.maxSizeBytes),
      dateFrom: clearDateFrom ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDateTo ? null : (dateTo ?? this.dateTo),
    );
  }

  Map<String, dynamic> toJson() => {
        'nameQuery': nameQuery,
        'tags': tags,
        'type': type?.name,
        'isFavorite': isFavorite,
        'onlyUntagged': onlyUntagged,
        'isEncrypted': isEncrypted,
        'albumId': albumId,
        'folderId': folderId,
        'minSizeBytes': minSizeBytes,
        'maxSizeBytes': maxSizeBytes,
        'dateFrom': dateFrom?.toIso8601String(),
        'dateTo': dateTo?.toIso8601String(),
      };

  factory VaultFileFilter.fromJson(Map<String, dynamic> json) {
    return VaultFileFilter(
      nameQuery: json['nameQuery'] as String?,
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      type: json['type'] != null
          ? VaultedFileType.fromString(json['type'] as String)
          : null,
      isFavorite: json['isFavorite'] as bool?,
      onlyUntagged: json['onlyUntagged'] as bool? ?? false,
      isEncrypted: json['isEncrypted'] as bool?,
      albumId: json['albumId'] as String?,
      folderId: json['folderId'] as String?,
      minSizeBytes: (json['minSizeBytes'] as num?)?.toInt(),
      maxSizeBytes: (json['maxSizeBytes'] as num?)?.toInt(),
      dateFrom: json['dateFrom'] != null
          ? DateTime.parse(json['dateFrom'] as String)
          : null,
      dateTo: json['dateTo'] != null
          ? DateTime.parse(json['dateTo'] as String)
          : null,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! VaultFileFilter) return false;
    return other.nameQuery == nameQuery &&
        _listEquals(other.tags, tags) &&
        other.type == type &&
        other.isFavorite == isFavorite &&
        other.onlyUntagged == onlyUntagged &&
        other.isEncrypted == isEncrypted &&
        other.albumId == albumId &&
        other.folderId == folderId &&
        other.minSizeBytes == minSizeBytes &&
        other.maxSizeBytes == maxSizeBytes &&
        other.dateFrom == dateFrom &&
        other.dateTo == dateTo;
  }

  @override
  int get hashCode => Object.hash(
        nameQuery,
        Object.hashAll(tags),
        type,
        isFavorite,
        onlyUntagged,
        isEncrypted,
        albumId,
        folderId,
        minSizeBytes,
        maxSizeBytes,
        dateFrom,
        dateTo,
      );

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() => 'VaultFileFilter(${toJson()})';
}
