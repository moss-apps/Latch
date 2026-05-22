import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../models/album.dart';
import '../models/encryption_algorithm.dart';
import '../models/vaulted_file.dart';
import '../services/vault_service.dart';
import '../services/decoy_service.dart';
import '../services/encryption_service.dart';

// ========== SERVICE PROVIDERS ==========

/// Provider for VaultService singleton
final vaultServiceProvider = Provider<VaultService>((ref) {
  return VaultService.instance;
});

/// Provider for DecoyService singleton
final decoyServiceProvider = Provider<DecoyService>((ref) {
  return DecoyService.instance;
});

/// Provider for EncryptionService singleton
final encryptionServiceProvider = Provider<EncryptionService>((ref) {
  return EncryptionService.instance;
});

// ========== STATE PROVIDERS ==========

/// Provider for current sort option
final sortOptionProvider = StateProvider<SortOption>((ref) {
  return SortOption.dateAddedNewest;
});

/// Provider for decoy mode status
final isDecoyModeProvider = StateProvider<bool>((ref) {
  return DecoyService.instance.isDecoyModeActive;
});

/// Provider for selected files (multi-select mode)
final selectedFilesProvider = StateProvider<Set<String>>((ref) {
  return {};
});

/// Provider for selection mode status
final isSelectionModeProvider = StateProvider<bool>((ref) {
  return false;
});

/// Provider for search query
final searchQueryProvider = StateProvider<String>((ref) {
  return '';
});

/// Provider for selected tags filter
final selectedTagsProvider = StateProvider<List<String>>((ref) {
  return [];
});

/// Provider for selected album filter
final selectedAlbumIdProvider = StateProvider<String?>((ref) {
  return null;
});

/// Provider for file type filter
final fileTypeFilterProvider = StateProvider<VaultedFileType?>((ref) {
  return null;
});

// ========== ASYNC PROVIDERS ==========

/// Provider for all vaulted files
final allFilesProvider = FutureProvider<List<VaultedFile>>((ref) async {
  final vaultService = ref.watch(vaultServiceProvider);
  final isDecoy = ref.watch(isDecoyModeProvider);
  return await vaultService.getAllFiles(isDecoy: isDecoy);
});

/// Provider for sorted and filtered files
final filteredFilesProvider = FutureProvider<List<VaultedFile>>((ref) async {
  final vaultService = ref.watch(vaultServiceProvider);
  final sortOption = ref.watch(sortOptionProvider);
  final isDecoy = ref.watch(isDecoyModeProvider);
  final searchQuery = ref.watch(searchQueryProvider);
  final selectedTags = ref.watch(selectedTagsProvider);
  final selectedAlbumId = ref.watch(selectedAlbumIdProvider);
  final fileTypeFilter = ref.watch(fileTypeFilterProvider);

  // Get files based on filters
  final files = await vaultService.searchFilesAdvanced(
    query: searchQuery.isEmpty ? null : searchQuery,
    tags: selectedTags.isEmpty ? null : selectedTags,
    albumId: selectedAlbumId,
    type: fileTypeFilter,
  );

  // Filter out decoy files if not in decoy mode
  final filteredByDecoy = files.where((f) => f.isDecoy == isDecoy).toList();

  // Sort files
  return vaultService.sortFiles(filteredByDecoy, sortOption);
});

/// Provider for files by type
final filesByTypeProvider =
    FutureProvider.family<List<VaultedFile>, VaultedFileType>(
        (ref, type) async {
  final vaultService = ref.watch(vaultServiceProvider);
  final isDecoy = ref.watch(isDecoyModeProvider);
  final sortOption = ref.watch(sortOptionProvider);

  final files = await vaultService.getFilesByType(type, isDecoy: isDecoy);
  return vaultService.sortFiles(files, sortOption);
});

/// Provider for all albums
final albumsProvider = FutureProvider<List<Album>>((ref) async {
  final vaultService = ref.watch(vaultServiceProvider);
  return await vaultService.getAllAlbums();
});

/// Provider for album by ID
final albumProvider =
    FutureProvider.family<Album?, String>((ref, albumId) async {
  final vaultService = ref.watch(vaultServiceProvider);
  return await vaultService.getAlbumById(albumId);
});

/// Provider for files in album
final filesInAlbumProvider =
    FutureProvider.family<List<VaultedFile>, String>((ref, albumId) async {
  final vaultService = ref.watch(vaultServiceProvider);
  final sortOption = ref.watch(sortOptionProvider);

  final files = await vaultService.getFilesInAlbum(albumId);
  return vaultService.sortFiles(files, sortOption);
});

/// Provider for all tags
final tagsProvider = FutureProvider<List<TagInfo>>((ref) async {
  final vaultService = ref.watch(vaultServiceProvider);
  return await vaultService.getAllTags();
});

/// Provider for files by tag
final filesByTagProvider =
    FutureProvider.family<List<VaultedFile>, String>((ref, tag) async {
  final vaultService = ref.watch(vaultServiceProvider);
  final sortOption = ref.watch(sortOptionProvider);

  final files = await vaultService.getFilesByTag(tag);
  return vaultService.sortFiles(files, sortOption);
});

/// Provider for favorite files
final favoriteFilesProvider = FutureProvider<List<VaultedFile>>((ref) async {
  final vaultService = ref.watch(vaultServiceProvider);
  final sortOption = ref.watch(sortOptionProvider);

  final files = await vaultService.getFavoriteFiles();
  return vaultService.sortFiles(files, sortOption);
});

/// Provider for vault settings
final vaultSettingsProvider = FutureProvider<VaultSettings>((ref) async {
  final vaultService = ref.watch(vaultServiceProvider);
  return await vaultService.getSettings();
});

/// Provider for decoy settings
final decoySettingsProvider = FutureProvider<DecoySettings>((ref) async {
  final decoyService = ref.watch(decoyServiceProvider);
  return await decoyService.getSettings();
});

/// Provider for file counts by type
final fileCountsProvider =
    FutureProvider<Map<VaultedFileType, int>>((ref) async {
  final vaultService = ref.watch(vaultServiceProvider);
  return await vaultService.getFileCounts();
});

/// Provider for total storage used
final totalStorageProvider = FutureProvider<int>((ref) async {
  final vaultService = ref.watch(vaultServiceProvider);
  return await vaultService.getTotalStorageUsed();
});

/// Provider for single file by ID
final fileByIdProvider =
    FutureProvider.family<VaultedFile?, String>((ref, fileId) async {
  final vaultService = ref.watch(vaultServiceProvider);
  final isDecoy = ref.watch(isDecoyModeProvider);
  return await vaultService.getFileById(fileId, isDecoy: isDecoy);
});

// ========== NOTIFIER PROVIDERS ==========

/// Notifier for managing vault state
class VaultNotifier extends Notifier<AsyncValue<List<VaultedFile>>> {
  @override
  AsyncValue<List<VaultedFile>> build() {
    loadFiles();
    return const AsyncValue.loading();
  }

  VaultService get _vaultService => ref.read(vaultServiceProvider);

  Future<void> loadFiles() async {
    state = const AsyncValue.loading();
    try {
      final isDecoy = ref.read(isDecoyModeProvider);
      final files = await _vaultService.getAllFiles(isDecoy: isDecoy);
      state = AsyncValue.data(files);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() async {
    await _vaultService.refresh();
    await loadFiles();
  }

  Future<bool> deleteFiles(
    List<String> fileIds, {
    void Function(int current, int total, {int currentSize, int totalSize})?
        onProgress,
  }) async {
    final isDecoy = ref.read(isDecoyModeProvider);
    final deleted = await _vaultService.removeFiles(
      fileIds,
      isDecoy: isDecoy,
      onProgress: onProgress,
    );
    if (deleted > 0) {
      await loadFiles();
      // Clear selection
      ref.read(selectedFilesProvider.notifier).state = {};
      ref.read(isSelectionModeProvider.notifier).state = false;
    }
    return deleted == fileIds.length;
  }

  Future<VaultedFile?> toggleFavorite(String fileId) async {
    final result = await _vaultService.toggleFavorite(fileId);
    if (result != null) {
      await loadFiles();
    }
    return result;
  }

  Future<bool> addToAlbum(List<String> fileIds, String albumId) async {
    bool success = true;
    for (final fileId in fileIds) {
      final result = await _vaultService.addFileToAlbum(fileId, albumId);
      if (!result) success = false;
    }
    if (success) {
      await loadFiles();
    }
    return success;
  }

  Future<bool> removeFromAlbum(List<String> fileIds, String albumId) async {
    bool success = true;
    for (final fileId in fileIds) {
      final result = await _vaultService.removeFileFromAlbum(fileId, albumId);
      if (!result) success = false;
    }
    if (success) {
      await loadFiles();
    }
    return success;
  }

  Future<VaultedFile?> addTag(String fileId, String tag) async {
    final result = await _vaultService.addTagToFile(fileId, tag);
    if (result != null) {
      await loadFiles();
    }
    return result;
  }

  Future<VaultedFile?> removeTag(String fileId, String tag) async {
    final result = await _vaultService.removeTagFromFile(fileId, tag);
    if (result != null) {
      await loadFiles();
    }
    return result;
  }
}

/// Provider for vault notifier
final vaultNotifierProvider =
    NotifierProvider<VaultNotifier, AsyncValue<List<VaultedFile>>>(() {
  return VaultNotifier();
});

/// Notifier for managing albums
class AlbumsNotifier extends Notifier<AsyncValue<List<Album>>> {
  @override
  AsyncValue<List<Album>> build() {
    loadAlbums();
    return const AsyncValue.loading();
  }

  VaultService get _vaultService => ref.read(vaultServiceProvider);

  Future<void> loadAlbums() async {
    state = const AsyncValue.loading();
    try {
      final albums = await _vaultService.getAllAlbums();
      state = AsyncValue.data(albums);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<Album?> createAlbum({
    required String name,
    String? description,
    String? coverImageId,
  }) async {
    final album = await _vaultService.createAlbum(
      name: name,
      description: description,
      coverImageId: coverImageId,
    );
    if (album != null) {
      await loadAlbums();
    }
    return album;
  }

  Future<Album?> updateAlbum(Album album) async {
    final updated = await _vaultService.updateAlbum(album);
    if (updated != null) {
      await loadAlbums();
    }
    return updated;
  }

  Future<bool> deleteAlbum(String albumId) async {
    final deleted = await _vaultService.deleteAlbum(albumId);
    if (deleted) {
      await loadAlbums();
    }
    return deleted;
  }
}

/// Provider for albums notifier
final albumsNotifierProvider =
    NotifierProvider<AlbumsNotifier, AsyncValue<List<Album>>>(() {
  return AlbumsNotifier();
});

// ========== UTILITY PROVIDERS ==========

/// Provider for formatted total storage
final formattedStorageProvider = FutureProvider<String>((ref) async {
  final bytes = await ref.watch(totalStorageProvider.future);

  if (bytes < 1024) {
    return '$bytes B';
  } else if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  } else if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  } else {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
});

/// Provider for file count summary
final fileCountSummaryProvider = FutureProvider<String>((ref) async {
  final counts = await ref.watch(fileCountsProvider.future);
  final total = counts.values.fold<int>(0, (sum, count) => sum + count);
  return '$total files';
});

class ReEncryptProgress {
  final bool isInProgress;
  final int current;
  final int total;
  final String? error;

  const ReEncryptProgress({
    this.isInProgress = false,
    this.current = 0,
    this.total = 0,
    this.error,
  });
}

class ReEncryptNotifier extends Notifier<ReEncryptProgress> {
  @override
  ReEncryptProgress build() {
    return const ReEncryptProgress();
  }

  VaultService get _vaultService => ref.read(vaultServiceProvider);

  Future<int> reEncryptVault(EncryptionAlgorithm targetAlgorithm) async {
    state = const ReEncryptProgress(isInProgress: true, current: 0, total: 0);
    try {
      final result = await _vaultService.reEncryptVault(
        targetAlgorithm,
        onProgress: (current, total) {
          state = ReEncryptProgress(
            isInProgress: true,
            current: current,
            total: total,
          );
        },
      );

      if (result < 0) {
        state = const ReEncryptProgress(error: 'Re-encryption failed');
      } else {
        state = ReEncryptProgress(current: result, total: result);
      }

      ref.invalidate(vaultSettingsProvider);
      ref.invalidate(allFilesProvider);
      return result;
    } catch (e) {
      state = ReEncryptProgress(error: e.toString());
      return -1;
    }
  }
}

final reEncryptProvider =
    NotifierProvider<ReEncryptNotifier, ReEncryptProgress>(() {
  return ReEncryptNotifier();
});
