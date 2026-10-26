import '../models/vaulted_file.dart';

/// Restricts browsing to the opened file's viewer without changing grid order.
///
/// Images and videos share a viewer; songs stay separate, and documents include
/// the other formats displayed in Docs. Virtual notes/passwords keep their
/// dedicated editors and must never appear as raw document previews.
List<VaultedFile> fileViewerContext(
    VaultedFile initialFile, Iterable<VaultedFile> visibleFiles) {
  final files = visibleFiles.where((file) {
    if (file.metadata?['noteId'] != null ||
        file.metadata?['passwordId'] != null) {
      return false;
    }
    if (initialFile.isImage || initialFile.isVideo) {
      return file.isImage || file.isVideo;
    }
    if (initialFile.isSong) return file.isSong;
    return file.isDocument || file.type == VaultedFileType.other;
  }).toList();

  // A stale/changed grid must never open an unrelated first item instead.
  return files.any((file) => file.id == initialFile.id) ? files : [initialFile];
}
