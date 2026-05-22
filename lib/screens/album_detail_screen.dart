import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../models/album.dart';
import '../models/vaulted_file.dart';
import '../providers/vault_providers.dart';
import '../services/auto_kill_service.dart';
import '../themes/app_colors.dart';
import '../utils/toast_utils.dart';
import '../utils/responsive_utils.dart';
import 'media_viewer_screen.dart';
import 'document_viewer_screen.dart';
import 'song_player_screen.dart';

/// Screen for viewing album details and files
class AlbumDetailScreen extends ConsumerStatefulWidget {
  final String albumId;

  const AlbumDetailScreen({super.key, required this.albumId});

  @override
  ConsumerState<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends ConsumerState<AlbumDetailScreen> {
  bool _isSelectionMode = false;
  final Set<String> _selectedFiles = {};

  @override
  Widget build(BuildContext context) {
    final albumAsync = ref.watch(albumProvider(widget.albumId));
    final filesAsync = ref.watch(filesInAlbumProvider(widget.albumId));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(albumAsync),
      body: filesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text(
            'Error loading files',
            style: TextStyle(
              fontFamily: 'ProductSans',
              color: context.textSecondary,
            ),
          ),
        ),
        data: (files) => _buildFilesGrid(files),
      ),
      floatingActionButton: _isSelectionMode
          ? null
          : FloatingActionButton.extended(
              onPressed: _showAddFilesSheet,
              backgroundColor: context.accentColor,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Add Files',
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
    );
  }

  PreferredSizeWidget _buildAppBar(AsyncValue<Album?> albumAsync) {
    if (_isSelectionMode) {
      final files =
          (ref.read(filesInAlbumProvider(widget.albumId)).value ?? []);
      final allSelected = files.isNotEmpty &&
          files.every((f) => _selectedFiles.contains(f.id));

      return AppBar(
        backgroundColor: context.accentColor,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: _exitSelectionMode,
        ),
        title: Text(
          '${_selectedFiles.length} selected',
          style: const TextStyle(
            fontFamily: 'ProductSans',
            color: Colors.white,
          ),
        ),
        actions: [
          if (files.isNotEmpty)
            TextButton(
              onPressed: _toggleSelectAll,
              child: Text(
                allSelected ? 'Deselect All' : 'Select All',
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'ProductSans',
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, color: Colors.white),
            onPressed: _removeSelectedFromAlbum,
            tooltip: 'Remove from album',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white),
            onPressed: _deleteSelectedFiles,
            tooltip: 'Delete files',
          ),
        ],
      );
    }

    return AppBar(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      foregroundColor: context.textPrimary,
      elevation: 0,
      title: albumAsync.when(
        loading: () => const Text('Loading...'),
        error: (_, __) => const Text('Album'),
        data: (album) => Text(
          album?.name ?? 'Album',
          style: const TextStyle(
            fontFamily: 'ProductSans',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      actions: [
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: context.textPrimary),
          onSelected: (value) {
            switch (value) {
              case 'sort':
                _showSortOptions();
                break;
              case 'add':
                _showAddFilesSheet();
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'sort',
              child: Row(
                children: [
                  Icon(Icons.sort, size: 20),
                  SizedBox(width: 12),
                  Text('Sort'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'add',
              child: Row(
                children: [
                  Icon(Icons.add_photo_alternate, size: 20),
                  SizedBox(width: 12),
                  Text('Add Files'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilesGrid(List<VaultedFile> files) {
    if (files.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(filesInAlbumProvider(widget.albumId));
      },
      color: context.accentColor,
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: ResponsiveGridDelegate.responsive(
          context,
          compact: 3,
          medium: 4,
          expanded: 6,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
          childAspectRatio: 1,
        ),
        itemCount: files.length,
        itemBuilder: (context, index) => _buildFileItem(files[index]),
      ),
    );
  }

  Widget _buildFileItem(VaultedFile file) {
    final isSelected = _selectedFiles.contains(file.id);

    return GestureDetector(
      onTap: () {
        if (_isSelectionMode) {
          _toggleSelection(file.id);
        } else {
          _openFile(file);
        }
      },
      onLongPress: () {
        if (!_isSelectionMode) {
          _enterSelectionMode(file.id);
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              color: context.backgroundSecondary,
              borderRadius: BorderRadius.circular(8),
              border: isSelected
                  ? Border.all(color: context.accentColor, width: 3)
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(isSelected ? 5 : 8),
              child: _buildFileThumbnail(file),
            ),
          ),
          if (_isSelectionMode)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? context.accentColor : Colors.white,
                  border: Border.all(
                    color:
                        isSelected ? context.accentColor : context.borderColor,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
            ),
          if (file.isFavorite)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(
                  Icons.favorite,
                  size: 14,
                  color: Colors.red,
                ),
              ),
            ),
          if (file.isVideo)
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_arrow, size: 14, color: Colors.white),
                    const SizedBox(width: 2),
                    Text(
                      file.formattedSize,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontFamily: 'ProductSans',
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFileThumbnail(VaultedFile file) {
    if (file.isImage) {
      final imageFile = File(file.vaultPath);
      return FutureBuilder<bool>(
        future: imageFile.exists(),
        builder: (context, snapshot) {
          if (snapshot.data != true) {
            return _buildPlaceholder(file);
          }
          return Image.file(
            imageFile,
            fit: BoxFit.cover,
            cacheWidth: 300,
            filterQuality: FilterQuality.low,
            errorBuilder: (context, error, stackTrace) =>
                _buildPlaceholder(file),
          );
        },
      );
    }
    return _buildPlaceholder(file);
  }

  Widget _buildPlaceholder(VaultedFile file) {
    IconData icon;
    Color color;

    switch (file.type) {
      case VaultedFileType.image:
        icon = Icons.image;
        color = context.accentColor;
        break;
      case VaultedFileType.video:
        icon = Icons.videocam;
        color = Colors.red;
        break;
      case VaultedFileType.song:
        icon = Icons.music_note;
        color = Colors.purple;
        break;
      case VaultedFileType.document:
        icon = Icons.description;
        color = Colors.green;
        break;
      case VaultedFileType.other:
        icon = Icons.insert_drive_file;
        color = Colors.grey;
        break;
    }

    return Container(
      color: color.withValues(alpha: 0.1),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 36, color: color),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              file.extension.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: color,
                fontFamily: 'ProductSans',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: context.backgroundSecondary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.folder_open_outlined,
              size: 64,
              color: context.textTertiary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No files in this album',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
              fontFamily: 'ProductSans',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add files from your vault',
            style: TextStyle(
              fontSize: 14,
              color: context.textSecondary,
              fontFamily: 'ProductSans',
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showAddFilesSheet,
            icon: const Icon(Icons.add),
            label: const Text('Add Files'),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.accentColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _enterSelectionMode(String fileId) {
    setState(() {
      _isSelectionMode = true;
      _selectedFiles.add(fileId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedFiles.clear();
    });
  }

  void _toggleSelection(String fileId) {
    setState(() {
      if (_selectedFiles.contains(fileId)) {
        _selectedFiles.remove(fileId);
        if (_selectedFiles.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedFiles.add(fileId);
      }
    });
  }

  void _toggleSelectAll() {
    final files =
        (ref.read(filesInAlbumProvider(widget.albumId)).value ?? []);
    final allSelected =
        files.isNotEmpty && files.every((f) => _selectedFiles.contains(f.id));

    setState(() {
      if (allSelected) {
        _selectedFiles.clear();
        _isSelectionMode = false;
      } else {
        _selectedFiles.addAll(files.map((f) => f.id));
        _isSelectionMode = true;
      }
    });
  }

  void _openFile(VaultedFile file) {
    // Get files in album for viewer navigation
    final filesAsync = ref.read(filesInAlbumProvider(widget.albumId));
    final allFiles = filesAsync.value ?? [];

    if (file.isImage || file.isVideo) {
      final viewerFiles =
          allFiles.where((f) => f.isImage || f.isVideo).toList();
      final initialIndex = viewerFiles.indexWhere((f) => f.id == file.id);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MediaViewerScreen(
            initialFile: file,
            files: viewerFiles.isNotEmpty ? viewerFiles : [file],
            initialIndex: initialIndex >= 0 ? initialIndex : 0,
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
    } else {
      _showFileOptionsSheet(file);
    }
  }

  void _showFileOptionsSheet(VaultedFile file) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: BoxDecoration(
          color: context.backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.borderColor,
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
                          child: const Icon(Icons.insert_drive_file,
                              size: 32, color: Colors.grey),
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
                                    color: context.textPrimary,
                                    fontFamily: 'ProductSans'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${file.extension.toUpperCase()} • ${file.formattedSize}',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: context.textSecondary,
                                    fontFamily: 'ProductSans'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text('Preview not available',
                        style: TextStyle(
                            fontSize: 13,
                            color: context.textSecondary,
                            fontFamily: 'ProductSans')),
                    const SizedBox(height: 12),
                    ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                            color: context.accentColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12)),
                        child: Icon(Icons.download_outlined,
                            color: context.accentColor),
                      ),
                      title: const Text('Export to Downloads',
                          style: TextStyle(
                              fontFamily: 'ProductSans',
                              fontWeight: FontWeight.w500)),
                      subtitle: Text('Save decrypted file to Downloads folder',
                          style: TextStyle(
                              fontFamily: 'ProductSans',
                              fontSize: 12,
                              color: AppColors.lightTextSecondary)),
                      contentPadding: EdgeInsets.zero,
                      onTap: () {
                        Navigator.pop(context);
                        _exportFileToDownloads(file);
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                            color: context.accentColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12)),
                        child:
                            Icon(Icons.open_in_new, color: context.accentColor),
                      ),
                      title: const Text('Open with...',
                          style: TextStyle(
                              fontFamily: 'ProductSans',
                              fontWeight: FontWeight.w500)),
                      subtitle: Text('Open file with an external app',
                          style: TextStyle(
                              fontFamily: 'ProductSans',
                              fontSize: 12,
                              color: AppColors.lightTextSecondary)),
                      contentPadding: EdgeInsets.zero,
                      onTap: () {
                        Navigator.pop(context);
                        _openWithExternalApp(file);
                      },
                    ),
                  ],
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportFileToDownloads(VaultedFile file) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          content: Row(
            children: [
              CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(context.accentColor)),
              const SizedBox(width: 20),
              Expanded(
                  child: Text('Exporting ${file.originalName}...',
                      style: const TextStyle(fontFamily: 'ProductSans'))),
            ],
          ),
        ),
      );

      Directory? downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
        if (!await downloadsDir.exists()) {
          downloadsDir = await getExternalStorageDirectory();
        }
      } else {
        downloadsDir = await getDownloadsDirectory();
      }

      if (downloadsDir == null) {
        if (mounted) Navigator.pop(context);
        ToastUtils.showError('Could not access Downloads folder');
        return;
      }

      final destinationPath = '${downloadsDir.path}/${file.originalName}';
      final vaultService = ref.read(vaultServiceProvider);
      final exportedFile =
          await vaultService.exportFile(file.id, destinationPath);

      if (mounted) Navigator.pop(context);

      if (exportedFile != null) {
        ToastUtils.showSuccess('Exported to Downloads/${file.originalName}');
      } else {
        ToastUtils.showError('Failed to export file');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint('Error exporting file: $e');
      ToastUtils.showError('Failed to export file: $e');
    }
  }

  Future<void> _openWithExternalApp(VaultedFile file) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          content: Row(
            children: [
              CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(context.accentColor)),
              const SizedBox(width: 20),
              Expanded(
                  child: Text('Preparing ${file.originalName}...',
                      style: const TextStyle(fontFamily: 'ProductSans'))),
            ],
          ),
        ),
      );

      final vaultService = ref.read(vaultServiceProvider);
      final decryptedFile = await vaultService.getVaultedFile(file.id);

      if (mounted) Navigator.pop(context);

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
      if (mounted) Navigator.pop(context);
      debugPrint('Error opening file: $e');
      ToastUtils.showError('Failed to open file: $e');
    }
  }

  Future<void> _removeSelectedFromAlbum() async {
    if (_selectedFiles.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          'Remove from Album',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textPrimary,
          ),
        ),
        content: Text(
          'Remove ${_selectedFiles.length} file(s) from this album? The files will remain in your vault.',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: context.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.accentColor,
              foregroundColor: Colors.white,
            ),
            child: const Text(
              'Remove',
              style: TextStyle(fontFamily: 'ProductSans'),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success =
          await ref.read(vaultNotifierProvider.notifier).removeFromAlbum(
                _selectedFiles.toList(),
                widget.albumId,
              );

      if (!mounted) return;
      if (success) {
        ToastUtils.showSuccess('Removed from album');
        ref.invalidate(filesInAlbumProvider(widget.albumId));
        ref.invalidate(albumsNotifierProvider);
      } else {
        ToastUtils.showError('Failed to remove from album');
      }
      _exitSelectionMode();
    }
  }

  Future<void> _deleteSelectedFiles() async {
    if (_selectedFiles.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          'Delete Files',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textPrimary,
          ),
        ),
        content: Text(
          'Are you sure you want to delete ${_selectedFiles.length} file(s)? This action cannot be undone.',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: context.textSecondary,
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
          await ref.read(vaultNotifierProvider.notifier).deleteFiles(
                _selectedFiles.toList(),
              );

      if (!mounted) return;
      if (success) {
        ToastUtils.showSuccess('Files deleted');
        ref.invalidate(filesInAlbumProvider(widget.albumId));
        ref.invalidate(albumsNotifierProvider);
      } else {
        ToastUtils.showError('Failed to delete files');
      }
      _exitSelectionMode();
    }
  }

  void _showSortOptions() {
    final currentSort = ref.read(sortOptionProvider);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        decoration: BoxDecoration(
          color: context.backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sort By',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                        fontFamily: 'ProductSans',
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...SortOption.values.map((option) => ListTile(
                          leading: Icon(
                            currentSort == option
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: currentSort == option
                                ? context.accentColor
                                : AppColors.lightTextTertiary,
                          ),
                          title: Text(
                            option.displayName,
                            style: TextStyle(
                              fontFamily: 'ProductSans',
                              color: context.textPrimary,
                            ),
                          ),
                          onTap: () {
                            ref.read(sortOptionProvider.notifier).state =
                                option;
                            Navigator.pop(context);
                          },
                          contentPadding: EdgeInsets.zero,
                        )),
                  ],
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddFilesSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _AddFilesToAlbumSheet(
        albumId: widget.albumId,
        onFilesAdded: () {
          ref.invalidate(filesInAlbumProvider(widget.albumId));
          ref.invalidate(albumProvider(widget.albumId));
          ref.invalidate(albumsNotifierProvider);
        },
      ),
    );
  }
}

/// Bottom sheet for adding files to album from vault
class _AddFilesToAlbumSheet extends ConsumerStatefulWidget {
  final String albumId;
  final VoidCallback onFilesAdded;

  const _AddFilesToAlbumSheet({
    required this.albumId,
    required this.onFilesAdded,
  });

  @override
  ConsumerState<_AddFilesToAlbumSheet> createState() =>
      _AddFilesToAlbumSheetState();
}

class _AddFilesToAlbumSheetState extends ConsumerState<_AddFilesToAlbumSheet> {
  final Set<String> _selectedFiles = {};
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final vaultFilesAsync = ref.watch(vaultNotifierProvider);
    final albumFilesAsync = ref.watch(filesInAlbumProvider(widget.albumId));

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: context.backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.borderColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add Files to Album',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimary,
                          fontFamily: 'ProductSans',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Select files from your vault',
                        style: TextStyle(
                          fontSize: 14,
                          color: context.textSecondary,
                          fontFamily: 'ProductSans',
                        ),
                      ),
                    ],
                  ),
                ),
                if (_selectedFiles.isNotEmpty)
                  ElevatedButton(
                    onPressed: _isLoading ? null : _addSelectedFiles,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.accentColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Add (${_selectedFiles.length})',
                            style: const TextStyle(fontFamily: 'ProductSans'),
                          ),
                  ),
              ],
            ),
          ),
          // File grid
          Expanded(
            child: vaultFilesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                child: Text(
                  'Failed to load files',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    color: context.textSecondary,
                  ),
                ),
              ),
              data: (allFiles) {
                // Get files already in album
                final albumFileIds =
                    albumFilesAsync.value?.map((f) => f.id).toSet() ?? {};

                // Filter out files already in album
                final availableFiles = allFiles
                    .where((f) => !albumFileIds.contains(f.id))
                    .toList();

                if (availableFiles.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 64,
                          color: context.textTertiary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'All files are already in this album',
                          style: TextStyle(
                            fontFamily: 'ProductSans',
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return GridView.builder(
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
                  itemCount: availableFiles.length,
                  itemBuilder: (context, index) =>
                      _buildFileItem(availableFiles[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileItem(VaultedFile file) {
    final isSelected = _selectedFiles.contains(file.id);

    return GestureDetector(
      onTap: () => _toggleSelection(file.id),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              color: context.backgroundSecondary,
              borderRadius: BorderRadius.circular(8),
              border: isSelected
                  ? Border.all(color: context.accentColor, width: 3)
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(isSelected ? 5 : 8),
              child: _buildFileThumbnail(file),
            ),
          ),
          // Selection indicator
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? context.accentColor : Colors.white,
                border: Border.all(
                  color: isSelected ? context.accentColor : context.borderColor,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
          ),
          // Video indicator
          if (file.isVideo)
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child:
                    const Icon(Icons.play_arrow, size: 16, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFileThumbnail(VaultedFile file) {
    if (file.isImage) {
      final imageFile = File(file.vaultPath);
      return FutureBuilder<bool>(
        future: imageFile.exists(),
        builder: (context, snapshot) {
          if (snapshot.data != true) {
            return _buildPlaceholder(file);
          }
          return Image.file(
            imageFile,
            fit: BoxFit.cover,
            cacheWidth: 200,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, __, ___) => _buildPlaceholder(file),
          );
        },
      );
    }

    if (file.isVideo) {
      return Container(
        color: Colors.black87,
        child: const Center(
          child: Icon(
            Icons.play_circle_outline,
            size: 32,
            color: Colors.white70,
          ),
        ),
      );
    }

    return _buildPlaceholder(file);
  }

  Widget _buildPlaceholder(VaultedFile file) {
    IconData icon;
    Color color;

    switch (file.type) {
      case VaultedFileType.image:
        icon = Icons.image;
        color = context.accentColor;
        break;
      case VaultedFileType.video:
        icon = Icons.videocam;
        color = Colors.red;
        break;
      case VaultedFileType.song:
        icon = Icons.music_note;
        color = Colors.purple;
        break;
      case VaultedFileType.document:
        icon = Icons.description;
        color = Colors.green;
        break;
      case VaultedFileType.other:
        icon = Icons.insert_drive_file;
        color = Colors.grey;
        break;
    }

    return Container(
      color: color.withValues(alpha: 0.1),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 28, color: color),
          const SizedBox(height: 4),
          Text(
            file.extension.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
              fontFamily: 'ProductSans',
            ),
          ),
        ],
      ),
    );
  }

  void _toggleSelection(String fileId) {
    setState(() {
      if (_selectedFiles.contains(fileId)) {
        _selectedFiles.remove(fileId);
      } else {
        _selectedFiles.add(fileId);
      }
    });
  }

  Future<void> _addSelectedFiles() async {
    if (_selectedFiles.isEmpty) return;

    setState(() => _isLoading = true);

    final success = await ref.read(vaultNotifierProvider.notifier).addToAlbum(
          _selectedFiles.toList(),
          widget.albumId,
        );

    setState(() => _isLoading = false);

    if (success) {
      widget.onFilesAdded();
      if (mounted) {
        Navigator.pop(context);
        ToastUtils.showSuccess('Added ${_selectedFiles.length} files to album');
      }
    } else {
      ToastUtils.showError('Failed to add files to album');
    }
  }
}
