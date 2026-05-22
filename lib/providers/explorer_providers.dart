import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../models/vault_folder.dart';
import '../models/vaulted_file.dart';
import 'vault_providers.dart';

/// View modes supported by the vault file explorer
enum ExplorerViewMode {
  sidebar,
  navigation;

  String get displayName {
    switch (this) {
      case ExplorerViewMode.sidebar:
        return 'Sidebar Tree';
      case ExplorerViewMode.navigation:
        return 'Grid Navigation';
    }
  }
}

/// Provider for current explorer view mode
final explorerViewModeProvider = StateProvider<ExplorerViewMode>((ref) {
  return ExplorerViewMode.navigation;
});

/// Provider for the currently viewed folder ID (null represents the root vault folder)
final explorerCurrentFolderIdProvider = StateProvider<String?>((ref) {
  return null;
});

/// Provider for file type filtering in the explorer
final explorerFileTypeFilterProvider = StateProvider<VaultedFileType?>((ref) {
  return null;
});

/// Provider for unfiled files (files that do not belong to any folder)
final unfiledFilesProvider = FutureProvider<List<VaultedFile>>((ref) async {
  final allFiles = await ref.watch(allFilesProvider.future);
  return allFiles.where((file) => file.folderId == null).toList();
});

/// Provider for files to display in the current explorer view (handles root vs folder + type filters + sorting)
final explorerFilesProvider = FutureProvider<List<VaultedFile>>((ref) async {
  final folderId = ref.watch(explorerCurrentFolderIdProvider);
  final typeFilter = ref.watch(explorerFileTypeFilterProvider);
  final sortOption = ref.watch(sortOptionProvider);
  final vaultService = ref.watch(vaultServiceProvider);

  List<VaultedFile> files = [];
  if (folderId == null) {
    files = await ref.watch(unfiledFilesProvider.future);
  } else {
    files = await ref.watch(filesInFolderProvider(folderId).future);
  }

  // Filter by type
  if (typeFilter != null) {
    files = files.where((f) => f.type == typeFilter).toList();
  }

  // Sort files
  return vaultService.sortFiles(files, sortOption);
});

/// Provider for subfolders to display in the current explorer folder
final explorerSubfoldersProvider = FutureProvider<List<VaultFolder>>((ref) async {
  final folderId = ref.watch(explorerCurrentFolderIdProvider);
  if (folderId == null) {
    return ref.watch(rootFoldersProvider.future);
  } else {
    return ref.watch(subfoldersProvider(folderId).future);
  }
});

/// Provider for current viewed folder metadata
final explorerCurrentFolderProvider = FutureProvider<VaultFolder?>((ref) async {
  final folderId = ref.watch(explorerCurrentFolderIdProvider);
  if (folderId == null) return null;
  return ref.watch(folderProvider(folderId).future);
});
