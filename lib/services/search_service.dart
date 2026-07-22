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

  Future<List<VaultedFile>> searchFilesAdvanced({
    String? query,
    List<String>? tags,
    VaultedFileType? type,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool? isFavorite,
    String? albumId,
  }) async {
    var files = await _store.loadFileIndex();

    if (query != null && query.isNotEmpty) {
      final lowerQuery = query.toLowerCase();
      files = files
          .where((f) => f.originalName.toLowerCase().contains(lowerQuery))
          .toList();
    }

    if (tags != null && tags.isNotEmpty) {
      files = files.where((f) => tags.every((tag) => f.hasTag(tag))).toList();
    }

    if (type != null) {
      files = files.where((f) => f.type == type).toList();
    }

    if (dateFrom != null) {
      files = files.where((f) => f.dateAdded.isAfter(dateFrom)).toList();
    }
    if (dateTo != null) {
      files = files.where((f) => f.dateAdded.isBefore(dateTo)).toList();
    }

    if (isFavorite != null) {
      files = files.where((f) => f.isFavorite == isFavorite).toList();
    }

    if (albumId != null) {
      files = files.where((f) => f.isInAlbum(albumId)).toList();
    }

    return files;
  }
}