import '../models/vault_file_filter.dart';
import '../models/vaulted_file.dart';
import 'vault_store.dart';

/// Read-only search over the file index. Splits out of `VaultService`.
class SearchService {
  final VaultStore _store;
  SearchService(this._store);

  Future<List<VaultedFile>> searchFiles(String query) async {
    final files = await _store.loadFileIndex();
    final lowerQuery = query.toLowerCase();
    return files
        .where((f) => f.originalName.toLowerCase().contains(lowerQuery))
        .toList();
  }

  /// Single source of truth for filtered reads.
  Future<List<VaultedFile>> searchWithFilter(
    VaultFileFilter filter, {
    bool isDecoy = false,
  }) async {
    final files = await _store.loadFileIndex(isDecoy: isDecoy);
    if (filter.isEmpty) return files;
    return files.where(filter.matches).toList();
  }

  /// Legacy named-argument entry point. Date bounds are inclusive calendar
  /// days: any file added on the selected start/end day matches.
  Future<List<VaultedFile>> searchFilesAdvanced({
    String? query,
    List<String>? tags,
    VaultedFileType? type,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool? isFavorite,
    String? albumId,
    bool isDecoy = false,
  }) {
    return searchWithFilter(
      VaultFileFilter(
        nameQuery: query,
        tags: tags ?? const [],
        type: type,
        dateFrom: dateFrom,
        dateTo: dateTo,
        isFavorite: isFavorite,
        albumId: albumId,
      ),
      isDecoy: isDecoy,
    );
  }
}
