import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/vault_folder.dart';
import '../models/vaulted_file.dart';
import '../providers/vault_providers.dart';
import '../providers/explorer_providers.dart';
import '../screens/media_viewer_screen.dart';
import '../screens/document_viewer_screen.dart';
import '../screens/song_player_screen.dart';
import '../themes/app_colors.dart';
import '../utils/responsive_utils.dart';
import 'optimized_image_widget.dart';

class ExplorerFileGrid extends ConsumerWidget {
  final void Function(VaultFolder folder)? onFolderLongPress;

  const ExplorerFileGrid({
    super.key,
    this.onFolderLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewMode = ref.watch(explorerViewModeProvider);
    final filesAsync = ref.watch(explorerFilesProvider);
    final subfoldersAsync = ref.watch(explorerSubfoldersProvider);
    final selectedFiles = ref.watch(selectedFilesProvider);
    final isSelectionMode = ref.watch(isSelectionModeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Type Filter Chips Bar
        _buildTypeFilterBar(ref),

        // Grid Content
        Expanded(
          child: subfoldersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Text(
                'Error loading folders',
                style: TextStyle(fontFamily: 'ProductSans', color: context.textSecondary),
              ),
            ),
            data: (folders) {
              return filesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Text(
                    'Error loading files',
                    style: TextStyle(fontFamily: 'ProductSans', color: context.textSecondary),
                  ),
                ),
                data: (files) {
                  // In Sidebar Mode, we only show files in the grid
                  final showFoldersInGrid = viewMode == ExplorerViewMode.navigation;
                  final displayFolders = showFoldersInGrid ? folders : <VaultFolder>[];

                  if (displayFolders.isEmpty && files.isEmpty) {
                    return _buildEmptyState(context);
                  }

                  // Combine folders and files into a single mixed list index
                  final folderCount = displayFolders.length;
                  final fileCount = files.length;
                  final totalItems = folderCount + fileCount;

                  return RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(explorerSubfoldersProvider);
                      ref.invalidate(explorerFilesProvider);
                      ref.invalidate(unfiledFilesProvider);
                    },
                    color: context.accentColor,
                    child: GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: ResponsiveGridDelegate.responsive(
                        context,
                        compact: 3,
                        medium: 4,
                        expanded: 6,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 1,
                      ),
                      itemCount: totalItems,
                      itemBuilder: (context, index) {
                        if (index < folderCount) {
                          // Render Folder Card
                          return _buildFolderGridItem(
                            context,
                            ref,
                            displayFolders[index],
                          );
                        } else {
                          // Render File Card
                          final fileIndex = index - folderCount;
                          final file = files[fileIndex];
                          final isSelected = selectedFiles.contains(file.id);

                          return _buildFileGridItem(
                            context,
                            ref,
                            file,
                            files, // Pass displaying files list for the viewer carousel
                            isSelected,
                            isSelectionMode,
                          );
                        }
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTypeFilterBar(WidgetRef ref) {
    final activeFilter = ref.watch(explorerFileTypeFilterProvider);

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildFilterChip(ref, label: 'All', value: null, isActive: activeFilter == null),
          _buildFilterChip(ref, label: 'Images', value: VaultedFileType.image, isActive: activeFilter == VaultedFileType.image),
          _buildFilterChip(ref, label: 'Videos', value: VaultedFileType.video, isActive: activeFilter == VaultedFileType.video),
          _buildFilterChip(ref, label: 'Songs', value: VaultedFileType.song, isActive: activeFilter == VaultedFileType.song),
          _buildFilterChip(ref, label: 'Documents', value: VaultedFileType.document, isActive: activeFilter == VaultedFileType.document),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
    WidgetRef ref, {
    required String label,
    required VaultedFileType? value,
    required bool isActive,
  }) {
    final context = ref.context;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            color: isActive ? Colors.white : context.textPrimary,
            fontSize: 12,
          ),
        ),
        selected: isActive,
        onSelected: (_) {
          ref.read(explorerFileTypeFilterProvider.notifier).state = value;
        },
        selectedColor: context.accentColor,
        backgroundColor: context.backgroundSecondary,
        checkmarkColor: Colors.white,
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isActive ? context.accentColor : context.borderColor.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildFolderGridItem(
    BuildContext context,
    WidgetRef ref,
    VaultFolder folder,
  ) {
    return GestureDetector(
      onTap: () {
        // Double tap or tap to navigate inside
        ref.read(explorerCurrentFolderIdProvider.notifier).state = folder.id;
      },
      onLongPress: onFolderLongPress != null ? () => onFolderLongPress!(folder) : null,
      child: Container(
        decoration: BoxDecoration(
          color: context.backgroundSecondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: context.borderColor.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: context.accentColor.withValues(alpha: 0.05),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Center(
                  child: Icon(
                    Icons.folder,
                    size: 40,
                    color: context.accentColor.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      folder.name,
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${folder.fileCount} file${folder.fileCount == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        fontSize: 9,
                        color: context.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileGridItem(
    BuildContext context,
    WidgetRef ref,
    VaultedFile file,
    List<VaultedFile> allFiles,
    bool isSelected,
    bool isSelectionMode,
  ) {
    return GestureDetector(
      onTap: () {
        if (isSelectionMode) {
          _toggleSelection(ref, file.id);
        } else {
          _openFile(context, ref, file, allFiles);
        }
      },
      onLongPress: () {
        if (!isSelectionMode) {
          ref.read(isSelectionModeProvider.notifier).state = true;
          ref.read(selectedFilesProvider.notifier).state = {file.id};
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Thumbnail / Content
          Container(
            decoration: BoxDecoration(
              color: context.backgroundSecondary,
              borderRadius: BorderRadius.circular(12),
              border: isSelected
                  ? Border.all(color: context.accentColor, width: 3)
                  : Border.all(color: context.borderColor.withValues(alpha: 0.5), width: 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(isSelected ? 9 : 11),
              child: _buildFileThumbnail(file, context),
            ),
          ),

          // Favorite badge
          if (file.isFavorite)
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.favorite,
                  size: 10,
                  color: Colors.red,
                ),
              ),
            ),

          // File Extension/Type text tag for non-images
          if (!file.isImage && !file.isVideo)
            Positioned(
              bottom: 6,
              left: 6,
              right: 6,
              child: Text(
                file.originalName,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 8,
                  fontFamily: 'ProductSans',
                  fontWeight: FontWeight.w500,
                  shadows: [Shadow(blurRadius: 3, color: Colors.black54)],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),

          // Video length/size badge
          if (file.isVideo)
            Positioned(
              bottom: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_arrow, size: 10, color: Colors.white),
                    const SizedBox(width: 1),
                    Text(
                      file.formattedSize,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontFamily: 'ProductSans',
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Checkbox overlaid in Selection Mode
          if (isSelectionMode)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                width: 20,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? context.accentColor : Colors.white70,
                  border: Border.all(
                    color: isSelected ? context.accentColor : Colors.black45,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFileThumbnail(VaultedFile file, BuildContext context) {
    if (file.isImage) {
      final path = file.thumbnailPath ?? file.vaultPath;
      return OptimizedImageWidget(
        imageFile: File(path),
        fit: BoxFit.cover,
        errorWidget: _buildFilePlaceholder(file, context),
      );
    } else if (file.thumbnailPath != null) {
      return OptimizedImageWidget(
        imageFile: File(file.thumbnailPath!),
        fit: BoxFit.cover,
        errorWidget: _buildFilePlaceholder(file, context),
      );
    }
    return _buildFilePlaceholder(file, context);
  }

  Widget _buildFilePlaceholder(VaultedFile file, BuildContext context) {
    IconData icon;
    switch (file.type) {
      case VaultedFileType.video:
        icon = Icons.play_circle_outline;
        break;
      case VaultedFileType.song:
        icon = Icons.audiotrack;
        break;
      case VaultedFileType.document:
        icon = Icons.description;
        break;
      default:
        icon = Icons.insert_drive_file;
    }
    return Container(
      color: context.accentColor.withValues(alpha: 0.05),
      child: Center(
        child: Icon(
          icon,
          size: 28,
          color: context.accentColor.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  void _toggleSelection(WidgetRef ref, String fileId) {
    final selected = Set<String>.from(ref.read(selectedFilesProvider));
    if (selected.contains(fileId)) {
      selected.remove(fileId);
      if (selected.isEmpty) {
        ref.read(isSelectionModeProvider.notifier).state = false;
      }
    } else {
      selected.add(fileId);
    }
    ref.read(selectedFilesProvider.notifier).state = selected;
  }

  void _openFile(
    BuildContext context,
    WidgetRef ref,
    VaultedFile file,
    List<VaultedFile> currentFiles,
  ) {
    if (file.isImage || file.isVideo) {
      // Filter the current view for all images & videos for slideshow swiping context
      final viewerFiles = currentFiles.where((f) => f.isImage || f.isVideo).toList();
      final startIndex = viewerFiles.indexWhere((f) => f.id == file.id);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MediaViewerScreen(
            initialFile: file,
            files: viewerFiles.isNotEmpty ? viewerFiles : [file],
            initialIndex: startIndex >= 0 ? startIndex : 0,
          ),
        ),
      );
    } else if (file.isSong) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SongPlayerScreen(file: file),
        ),
      );
    } else if (file.isDocument) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DocumentViewerScreen(file: file),
        ),
      );
    }
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open_outlined,
            size: 64,
            color: context.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            'This folder is empty',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFamily: 'ProductSans',
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add some files or create subfolders.',
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'ProductSans',
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
