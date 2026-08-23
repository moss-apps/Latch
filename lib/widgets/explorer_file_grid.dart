import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import '../utils/path_utils.dart';
import '../models/vault_folder.dart';
import '../models/vaulted_file.dart';
import '../providers/vault_providers.dart';
import '../providers/explorer_providers.dart';
import '../services/file_open_service.dart';
import '../services/auto_kill_service.dart';
import '../themes/app_colors.dart';
import '../utils/responsive_utils.dart';
import '../utils/toast_utils.dart';
import '../widgets/file_info_sheet.dart';
import '../widgets/media_hold_action_sheet.dart';
import 'encrypted_thumbnail.dart';
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
                style: TextStyle(
                    fontFamily: 'ProductSans', color: context.textSecondary),
              ),
            ),
            data: (folders) {
              return filesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Text(
                    'Error loading files',
                    style: TextStyle(
                        fontFamily: 'ProductSans',
                        color: context.textSecondary),
                  ),
                ),
                data: (files) {
                  final isListView = viewMode == ExplorerViewMode.list;
                  final displayFolders = folders;

                  if (displayFolders.isEmpty && files.isEmpty) {
                    return _buildEmptyState(context);
                  }

                  // Combine folders and files into a single mixed list index
                  final folderCount = displayFolders.length;
                  final totalItems = folderCount + files.length;

                  return RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(explorerSubfoldersProvider);
                      ref.invalidate(explorerFilesProvider);
                      ref.invalidate(unfiledFilesProvider);
                    },
                    color: context.accentColor,
                    child: isListView
                        ? ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: totalItems,
                            itemBuilder: (context, index) {
                              if (index < folderCount) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _buildFolderListItem(
                                    context,
                                    ref,
                                    displayFolders[index],
                                  ),
                                );
                              }
                              final file = files[index - folderCount];
                              final isSelected =
                                  selectedFiles.contains(file.id);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _buildFileListItem(
                                  context,
                                  ref,
                                  file,
                                  files,
                                  isSelected,
                                  isSelectionMode,
                                ),
                              );
                            },
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(12),
                            gridDelegate:
                                ResponsiveGridDelegate.responsive(
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
                                final isSelected =
                                    selectedFiles.contains(file.id);

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
          _buildFilterChip(ref,
              label: 'All', value: null, isActive: activeFilter == null),
          _buildFilterChip(ref,
              label: 'Images',
              value: VaultedFileType.image,
              isActive: activeFilter == VaultedFileType.image),
          _buildFilterChip(ref,
              label: 'Videos',
              value: VaultedFileType.video,
              isActive: activeFilter == VaultedFileType.video),
          _buildFilterChip(ref,
              label: 'Songs',
              value: VaultedFileType.song,
              isActive: activeFilter == VaultedFileType.song),
          _buildFilterChip(ref,
              label: 'Documents',
              value: VaultedFileType.document,
              isActive: activeFilter == VaultedFileType.document),
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
            color: isActive
                ? context.accentColor
                : context.borderColor.withValues(alpha: 0.5),
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
      onLongPress:
          onFolderLongPress != null ? () => onFolderLongPress!(folder) : null,
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
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(12)),
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

  Widget _buildFolderListItem(
    BuildContext context,
    WidgetRef ref,
    VaultFolder folder,
  ) {
    return GestureDetector(
      onTap: () {
        ref.read(explorerCurrentFolderIdProvider.notifier).state = folder.id;
      },
      onLongPress:
          onFolderLongPress != null ? () => onFolderLongPress!(folder) : null,
      child: Container(
        decoration: BoxDecoration(
          color: context.backgroundSecondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: context.borderColor.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: context.accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.folder, color: context.accentColor, size: 24),
          ),
          title: Text(
            folder.name,
            style: TextStyle(
              fontFamily: 'ProductSans',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${folder.fileCount} file${folder.fileCount == 1 ? '' : 's'}',
            style: TextStyle(
              fontFamily: 'ProductSans',
              fontSize: 11,
              color: context.textSecondary,
            ),
          ),
          trailing: Icon(Icons.chevron_right, color: context.textTertiary),
        ),
      ),
    );
  }

  Widget _buildFileListItem(
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
          _showMediaHoldActionSheet(context, ref, file, allFiles);
        }
      },
      onLongPress: () {
        if (!isSelectionMode) {
          HapticFeedback.mediumImpact();
          _showMediaHoldActionSheet(context, ref, file, allFiles);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? context.accentColor.withValues(alpha: 0.08)
              : context.backgroundSecondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? context.accentColor
                : context.borderColor.withValues(alpha: 0.5),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: _buildFileThumbnail(file, context),
                ),
              ),
              if (isSelectionMode)
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? context.accentColor : Colors.white,
                      border: Border.all(
                        color:
                            isSelected ? context.accentColor : Colors.black45,
                        width: 2,
                      ),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: isSelected
                        ? const Icon(Icons.check,
                            size: 12, color: Colors.white)
                        : const SizedBox(width: 12, height: 12),
                  ),
                ),
            ],
          ),
          title: Row(
            children: [
              if (file.isFavorite)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.favorite, size: 14, color: Colors.red),
                ),
              Expanded(
                child: Text(
                  file.originalName,
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          subtitle: Text(
            '${file.type.displayName} \u2022 ${file.formattedSize} \u2022 ${file.formattedDateAdded}',
            style: TextStyle(
              fontFamily: 'ProductSans',
              fontSize: 11,
              color: context.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: file.isVideo
              ? Icon(Icons.play_circle_outline,
                  color: context.textSecondary, size: 22)
              : null,
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
          _showMediaHoldActionSheet(context, ref, file, allFiles);
        }
      },
      onLongPress: () {
        if (!isSelectionMode) {
          HapticFeedback.mediumImpact();
          _showMediaHoldActionSheet(context, ref, file, allFiles);
        }
      },
      child: AnimatedScale(
        scale: 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
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
                    : Border.all(
                        color: context.borderColor.withValues(alpha: 0.5),
                        width: 1),
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

            // Filename overlay for all file types
            Positioned(
              bottom: 6,
              left: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (file.isVideo) ...[
                      const Icon(Icons.play_arrow,
                          size: 10, color: Colors.white),
                      const SizedBox(width: 1),
                    ],
                    Expanded(
                      child: Text(
                        file.originalName,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 8,
                          fontFamily: 'ProductSans',
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (file.isVideo) ...[
                      const SizedBox(width: 2),
                      Text(
                        file.formattedSize,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 8,
                          fontFamily: 'ProductSans',
                        ),
                      ),
                    ],
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
      ),
    );
  }

  Widget _buildFileThumbnail(VaultedFile file, BuildContext context) {
    if (file.isImage) {
      if (file.isEncrypted) {
        return EncryptedThumbnail(file: file);
      }
      final path = file.thumbnailPath ?? file.vaultPath;
      return OptimizedImageWidget(
        imageFile: File(path),
        fit: BoxFit.cover,
        errorWidget: _buildFilePlaceholder(file, context),
      );
    } else if (file.isEncrypted) {
      return EncryptedThumbnail(file: file);
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
    FileOpenService.open(
      context,
      ref,
      file,
      currentFiles: currentFiles,
      onUnsupported: () => _showFileOptionsSheet(context, ref, file),
    );
  }

  void _showFileOptionsSheet(
    BuildContext ctx,
    WidgetRef ref,
    VaultedFile file,
  ) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: ctx.backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ctx.borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _getFileIcon(file.extension),
                          size: 32,
                          color: _getFileColor(ctx, file.extension),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              file.originalName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: ctx.textPrimary,
                                fontFamily: 'ProductSans',
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${file.extension.toUpperCase()} \u2022 ${file.formattedSize}',
                              style: TextStyle(
                                fontSize: 13,
                                color: ctx.textSecondary,
                                fontFamily: 'ProductSans',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Preview not available',
                    style: TextStyle(
                      fontSize: 13,
                      color: ctx.textSecondary,
                      fontFamily: 'ProductSans',
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: ctx.accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.download_outlined,
                        color: ctx.accentColor,
                      ),
                    ),
                    title: const Text(
                      'Export to Downloads',
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      'Save decrypted file to Downloads folder',
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        fontSize: 12,
                        color: ctx.textSecondary,
                      ),
                    ),
                    contentPadding: EdgeInsets.zero,
                    onTap: () {
                      Navigator.pop(ctx);
                      _exportFileToDownloads(ctx, ref, file);
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: ctx.accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.open_in_new,
                        color: ctx.accentColor,
                      ),
                    ),
                    title: const Text(
                      'Open with...',
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      'Open file with an external app',
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        fontSize: 12,
                        color: ctx.textSecondary,
                      ),
                    ),
                    contentPadding: EdgeInsets.zero,
                    onTap: () {
                      Navigator.pop(ctx);
                      _openWithExternalApp(ctx, ref, file);
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.info_outline,
                        color: ctx.textSecondary,
                      ),
                    ),
                    title: const Text(
                      'File Info',
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      'View file details',
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        fontSize: 12,
                        color: ctx.textSecondary,
                      ),
                    ),
                    contentPadding: EdgeInsets.zero,
                    onTap: () {
                      Navigator.pop(ctx);
                      _showFileInfo(ctx, file);
                    },
                  ),
                ],
              ),
            ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom),
          ],
        ),
      ),
    );
  }

  void _showMediaHoldActionSheet(
    BuildContext ctx,
    WidgetRef ref,
    VaultedFile file,
    List<VaultedFile> allFiles,
  ) {
    MediaHoldActionSheet.show(
      ctx,
      file: file,
      onFavorite: () async {
        await ref.read(vaultNotifierProvider.notifier).toggleFavorite(file.id);
        ToastUtils.showSuccess(
          file.isFavorite ? 'Removed from favorites' : 'Added to favorites',
        );
      },
      onShare: () => _exportFileToDownloads(ctx, ref, file),
      onDelete: () => _confirmDeleteFile(ctx, ref, file),
      onInfo: () => _showFileInfo(ctx, file),
      onSelect: () {
        ref.read(isSelectionModeProvider.notifier).state = true;
        ref.read(selectedFilesProvider.notifier).state = {file.id};
      },
      onOpen: () => _openFile(ctx, ref, file, allFiles),
      onExport: () => _exportFileToDownloads(ctx, ref, file),
    );
  }

  Future<void> _confirmDeleteFile(
    BuildContext ctx,
    WidgetRef ref,
    VaultedFile file,
  ) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
        title: Text(
          'Delete File',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: ctx.textPrimary,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${file.originalName}"?',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: ctx.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: ctx.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text(
              'Delete',
              style: TextStyle(fontFamily: 'ProductSans'),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success =
          await ref.read(vaultNotifierProvider.notifier).deleteFiles([file.id]);
      if (success) {
        ToastUtils.showSuccess('File deleted');
      } else {
        ToastUtils.showError('Failed to delete file');
      }
    }
  }

  Future<void> _exportFileToDownloads(
    BuildContext ctx,
    WidgetRef ref,
    VaultedFile file,
  ) async {
    try {
      showDialog(
        context: ctx,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
          content: Row(
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(ctx.accentColor),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  'Exporting ${file.originalName}...',
                  style: const TextStyle(fontFamily: 'ProductSans'),
                ),
              ),
            ],
          ),
        ),
      );

      final downloadsDir = await PathUtils.getDownloadsDirectory();

      if (downloadsDir == null) {
        if (ctx.mounted) Navigator.pop(ctx);
        ToastUtils.showError('Could not access Downloads folder');
        return;
      }

      final destinationPath = '${downloadsDir.path}/${file.originalName}';

      final vaultService = ref.read(vaultServiceProvider);
      final exportedFile =
          await vaultService.exportFile(file.id, destinationPath);

      if (ctx.mounted) Navigator.pop(ctx);

      if (exportedFile != null) {
        ToastUtils.showSuccess('Exported to Downloads/${file.originalName}');
      } else {
        ToastUtils.showError('Failed to export file');
      }
    } catch (e) {
      if (ctx.mounted) Navigator.pop(ctx);
      debugPrint('Error exporting file: $e');
      ToastUtils.showError('Failed to export file');
    }
  }

  Future<void> _openWithExternalApp(
    BuildContext ctx,
    WidgetRef ref,
    VaultedFile file,
  ) async {
    try {
      showDialog(
        context: ctx,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
          content: Row(
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(ctx.accentColor),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  'Preparing ${file.originalName}...',
                  style: const TextStyle(fontFamily: 'ProductSans'),
                ),
              ),
            ],
          ),
        ),
      );

      final vaultService = ref.read(vaultServiceProvider);
      final decryptedFile = await vaultService.getVaultedFile(file.id);

      if (ctx.mounted) Navigator.pop(ctx);

      if (decryptedFile != null && await decryptedFile.exists()) {
        final result = await AutoKillService.runSafe(
            () => OpenFilex.open(decryptedFile.path));
        if (result.type != ResultType.done) {
          ToastUtils.showError('No app found to open this file type');
        }
      } else {
        ToastUtils.showError('Failed to prepare file');
      }
    } catch (e) {
      if (ctx.mounted) Navigator.pop(ctx);
      debugPrint('Error opening file: $e');
      ToastUtils.showError('Failed to open file');
    }
  }

  void _showFileInfo(BuildContext ctx, VaultedFile file) {
    FileInfoSheet.show(ctx, file, title: 'File Info');
  }

  IconData _getFileIcon(String extension) {
    switch (extension.toLowerCase()) {
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Icons.folder_zip;
      case 'apk':
        return Icons.android;
      case 'exe':
      case 'msi':
        return Icons.computer;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'aac':
      case 'ogg':
        return Icons.music_note;
      case 'json':
      case 'xml':
      case 'html':
      case 'css':
      case 'js':
        return Icons.code;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileColor(BuildContext context, String extension) {
    switch (extension.toLowerCase()) {
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Colors.amber;
      case 'apk':
        return Colors.green;
      case 'exe':
      case 'msi':
        return context.accentColor;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'aac':
      case 'ogg':
        return Colors.purple;
      case 'json':
      case 'xml':
      case 'html':
      case 'css':
      case 'js':
        return Colors.orange;
      default:
        return Colors.grey;
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
