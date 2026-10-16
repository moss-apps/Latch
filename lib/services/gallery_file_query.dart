import '../models/vault_category.dart';
import '../models/vault_file_filter.dart';
import '../models/vaulted_file.dart';

/// One predicate for the displayed grid and select-all / sliding selection.
/// Always returns a new list, so sorting cannot mutate the persisted index.
List<VaultedFile> queryGalleryFiles(
  Iterable<VaultedFile> files, {
  required VaultCategory category,
  String search = '',
  VaultFileFilter filter = const VaultFileFilter(),
}) {
  final type = category.filterType;
  final query = search.toLowerCase();
  return files.where((file) {
    final matchesType = type == null ||
        file.type == type ||
        (type == VaultedFileType.document &&
            file.type == VaultedFileType.other);
    return matchesType &&
        file.originalName.toLowerCase().contains(query) &&
        filter.matches(file);
  }).toList();
}
