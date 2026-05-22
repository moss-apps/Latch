import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../models/album.dart';
import '../models/vault_folder.dart';
import '../models/vaulted_file.dart';
import '../providers/vault_providers.dart';
import '../services/file_import_service.dart';
import '../services/vault_service.dart';
import '../themes/app_colors.dart';
import '../utils/toast_utils.dart';
import '../utils/responsive_utils.dart';
import 'media_viewer_screen.dart';
import 'document_viewer_screen.dart';
import 'song_player_screen.dart';

class FolderDetailScreen extends ConsumerStatefulWidget {
  final String folderId;

  const FolderDetailScreen({super.key, required this.folderId});

  @override
  ConsumerState<FolderDetailScreen> createState() => _FolderDetailScreenState();
}

class _FolderDetailScreenState extends ConsumerState<FolderDetailScreen> {
  bool _isSelectionMode = false;
  final Set<String> _selectedFiles = {};

  @override
  Widget build(BuildContext context) {
    final folderAsync = ref.watch(folderProvider(widget.folderId));
    final filesAsync = ref.watch(filesInFolderProvider(widget.folderId));
    final subfoldersAsync = ref.watch(subfoldersProvider(widget.folderId));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(folderAsync),
      body: folderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            'Error loading folder',
            style: TextStyle(fontFamily: 'ProductSans', color: context.textSecondary),
          ),
        ),
        data: (folder) {
          if (folder == null) {
            return Center(
              child: Text(
                'Folder not found',
                style: TextStyle(fontFamily: 'ProductSans', color: context.textSecondary),
              ),
            );
          }
          return _buildContent(folder, filesAsync, subfoldersAsync);
        },
      ),
      floatingActionButton: _isSelectionMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showAddOptions,
              backgroundColor: context.accentColor,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Add',
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
    );
  }

  PreferredSizeWidget _buildAppBar(AsyncValue<VaultFolder?> folderAsync) {
    if (_isSelectionMode) {
      final files = ref.read(filesInFolderProvider(widget.folderId)).value ?? [];
      final allSelected = files.isNotEmpty && files.every((f) => _selectedFiles.contains(f.id));

      return AppBar(
        backgroundColor: context.accentColor,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: _exitSelectionMode,
        ),
        title: Text(
          '${_selectedFiles.length} selected',
          style: const TextStyle(fontFamily: 'ProductSans', color: Colors.white),
        ),
        actions: [
          if (files.isNotEmpty)
            TextButton(
              onPressed: _toggleSelectAll,
              child: Text(
                allSelected ? 'Deselect All' : 'Select All',
                style: const TextStyle(color: Colors.white, fontFamily: 'ProductSans'),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, color: Colors.white),
            onPressed: _removeSelectedFromFolder,
            tooltip: 'Remove from folder',
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
      title: folderAsync.when(
        loading: () => const Text('Loading...'),
        error: (_, __) => const Text('Folder'),
        data: (folder) => Text(
          folder?.name ?? 'Folder',
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
              case 'add_subfolder':
                _showCreateSubfolderDialog();
                break;
              case 'import':
                _importFolderFromDevice();
                break;
              case 'add_files':
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
              value: 'add_subfolder',
              child: Row(
                children: [
                  Icon(Icons.create_new_folder_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('Add Subfolder'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'import',
              child: Row(
                children: [
                  Icon(Icons.drive_folder_upload_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('Import into Folder'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'add_files',
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

  Widget _buildContent(
    VaultFolder folder,
    AsyncValue<List<VaultedFile>> filesAsync,
    AsyncValue<List<VaultFolder>> subfoldersAsync,
  ) {
    return filesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text(
          'Error loading files',
          style: TextStyle(fontFamily: 'ProductSans', color: context.textSecondary),
        ),
      ),
      data: (files) {
        return subfoldersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Text(
              'Error loading subfolders',
              style: TextStyle(fontFamily: 'ProductSans', color: context.textSecondary),
            ),
          ),
          data: (subfolders) {
            if (files.isEmpty && subfolders.isEmpty) {
              return _buildEmptyState();
            }
            return _buildFolderContent(folder, subfolders, files);
          },
        );
      },
    );
  }

  Widget _buildFolderContent(
    VaultFolder folder,
    List<VaultFolder> subfolders,
    List<VaultedFile> files,
  ) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(filesInFolderProvider(widget.folderId));
        ref.invalidate(subfoldersProvider(widget.folderId));
        ref.invalidate(folderProvider(widget.folderId));
      },
      color: context.accentColor,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (subfolders.isNotEmpty) ...[
            _buildSectionHeader('Subfolders'),
            const SizedBox(height: 12),
            _buildSubfoldersGrid(subfolders),
            const SizedBox(height: 24),
          ],
          if (files.isNotEmpty) ...[
            _buildSectionHeader('Files (${files.length})'),
            const SizedBox(height: 12),
            _buildFilesGrid(files),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: context.textTertiary,
        fontFamily: 'ProductSans',
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildSubfoldersGrid(List<VaultFolder> subfolders) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: ResponsiveGridDelegate.responsive(
        context,
        compact: 2,
        medium: 3,
        expanded: 4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      itemCount: subfolders.length,
      itemBuilder: (context, index) => _buildSubfolderCard(subfolders[index]),
    );
  }

  Widget _buildSubfolderCard(VaultFolder subfolder) {
    return GestureDetector(
      onTap: () => _openSubfolder(subfolder),
      onLongPress: () => _showSubfolderOptions(subfolder),
      child: Container(
        decoration: BoxDecoration(
          color: context.backgroundSecondary,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: Container(
                  color: context.accentColor.withValues(alpha: 0.1),
                  child: Center(
                    child: Icon(
                      Icons.folder,
                      size: 48,
                      color: context.accentColor,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          subfolder.name,
                          style: TextStyle(
                            fontFamily: 'ProductSans',
                            fontWeight: FontWeight.w600,
                            color: context.textPrimary,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getFolderItemCount(subfolder),
                    style: TextStyle(
                      fontFamily: 'ProductSans',
                      color: context.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getFolderItemCount(VaultFolder folder) {
    final parts = <String>[];
    if (folder.fileCount > 0) {
      parts.add('${folder.fileCount} file${folder.fileCount == 1 ? '' : 's'}');
    }
    if (folder.subfolderCount > 0) {
      parts.add('${folder.subfolderCount} folder${folder.subfolderCount == 1 ? '' : 's'}');
    }
    if (parts.isEmpty) return 'Empty';
    return parts.join(', ');
  }

  Widget _buildFilesGrid(List<VaultedFile> files) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
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
                    color: isSelected ? context.accentColor : context.borderColor,
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
            return _buildFilePlaceholder(file);
          }
          return Image.file(
            imageFile,
            fit: BoxFit.cover,
            cacheWidth: 200,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, __, ___) => _buildFilePlaceholder(file),
          );
        },
      );
    }
    return _buildFilePlaceholder(file);
  }

  Widget _buildFilePlaceholder(VaultedFile file) {
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
      color: context.accentColor.withValues(alpha: 0.1),
      child: Center(
        child: Icon(icon, size: 32, color: context.accentColor),
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
              Icons.folder_open,
              size: 64,
              color: context.textTertiary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'This folder is empty',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
              fontFamily: 'ProductSans',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add files or create subfolders',
            style: TextStyle(
              fontSize: 14,
              color: context.textSecondary,
              fontFamily: 'ProductSans',
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _showCreateSubfolderDialog,
                icon: const Icon(Icons.create_new_folder, size: 18),
                label: const Text('Subfolder'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _showAddFilesSheet,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Files'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.accentColor,
                  side: BorderSide(color: context.accentColor),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openSubfolder(VaultFolder subfolder) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FolderDetailScreen(folderId: subfolder.id),
      ),
    );
  }

  void _openFile(VaultedFile file) {
    if (file.isImage || file.isVideo) {
      final filesAsync = ref.read(filesInFolderProvider(widget.folderId));
      final files = filesAsync.value ?? [];
      final viewerFiles =
          files.where((f) => f.isImage || f.isVideo).toList();
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
    } else {
      _showOtherFileOptions(file);
    }
  }

  void _showOtherFileOptions(VaultedFile file) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
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
                      file.originalName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                        fontFamily: 'ProductSans',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 20),
                    ListTile(
                      leading: Icon(Icons.download, color: context.accentColor),
                      title: const Text('Export to Downloads'),
                      onTap: () {
                        Navigator.pop(context);
                        _exportFile(file);
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.open_in_new, color: context.accentColor),
                      title: const Text('Open with...'),
                      onTap: () {
                        Navigator.pop(context);
                        _openFileExternally(file);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportFile(VaultedFile file) async {
    try {
      final exportDir = await getApplicationDocumentsDirectory();
      final exportPath = '${exportDir.path}/${file.originalName}';
      await VaultService.instance.exportFile(file.id, exportPath);
      if (mounted) {
        ToastUtils.showSuccess('File exported to Downloads');
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.showError('Failed to export file: $e');
      }
    }
  }

  Future<void> _openFileExternally(VaultedFile file) async {
    try {
      await OpenFilex.open(file.vaultPath);
    } catch (e) {
      if (mounted) {
        ToastUtils.showError('Failed to open file: $e');
      }
    }
  }

  void _enterSelectionMode(String fileId) {
    setState(() {
      _isSelectionMode = true;
      _selectedFiles.clear();
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
    final files = ref.read(filesInFolderProvider(widget.folderId)).value ?? [];
    setState(() {
      if (_selectedFiles.length == files.length) {
        _selectedFiles.clear();
        _isSelectionMode = false;
      } else {
        _selectedFiles.clear();
        _selectedFiles.addAll(files.map((f) => f.id));
      }
    });
  }

  Future<void> _removeSelectedFromFolder() async {
    if (_selectedFiles.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          'Remove from Folder',
          style: TextStyle(fontFamily: 'ProductSans', color: context.textPrimary),
        ),
        content: Text(
          'Remove ${_selectedFiles.length} file${_selectedFiles.length == 1 ? '' : 's'} from this folder? The files will not be deleted from the vault.',
          style: TextStyle(fontFamily: 'ProductSans', color: context.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(fontFamily: 'ProductSans', color: context.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            child: const Text('Remove', style: TextStyle(fontFamily: 'ProductSans')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    for (final fileId in _selectedFiles.toList()) {
      await ref.read(foldersNotifierProvider.notifier).removeFileFromFolder(
            fileId,
            widget.folderId,
          );
    }

    _exitSelectionMode();
    ref.invalidate(filesInFolderProvider(widget.folderId));
    ref.invalidate(folderProvider(widget.folderId));
    ToastUtils.showSuccess('Files removed from folder');
  }

  Future<void> _deleteSelectedFiles() async {
    if (_selectedFiles.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          'Delete Files',
          style: TextStyle(fontFamily: 'ProductSans', color: context.textPrimary),
        ),
        content: Text(
          'Permanently delete ${_selectedFiles.length} file${_selectedFiles.length == 1 ? '' : 's'}? This cannot be undone.',
          style: TextStyle(fontFamily: 'ProductSans', color: context.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(fontFamily: 'ProductSans', color: context.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            child: const Text('Delete', style: TextStyle(fontFamily: 'ProductSans')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await ref.read(vaultNotifierProvider.notifier).deleteFiles(_selectedFiles.toList());

    _exitSelectionMode();
    ref.invalidate(filesInFolderProvider(widget.folderId));
    ref.invalidate(folderProvider(widget.folderId));
    ref.invalidate(foldersNotifierProvider);
    ToastUtils.showSuccess('Files deleted');
  }

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
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
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            option.displayName,
                            style: TextStyle(fontFamily: 'ProductSans', color: context.textPrimary),
                          ),
                          onTap: () {
                            ref.read(sortOptionProvider.notifier).state = option;
                            ref.invalidate(filesInFolderProvider(widget.folderId));
                            Navigator.pop(context);
                          },
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateSubfolderDialog() {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          'Create Subfolder',
          style: TextStyle(fontFamily: 'ProductSans', color: context.textPrimary),
        ),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: 'Folder Name',
            labelStyle: TextStyle(fontFamily: 'ProductSans', color: context.textSecondary),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.accentColor),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(fontFamily: 'ProductSans', color: context.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                ToastUtils.showError('Please enter folder name');
                return;
              }

              final folder = await ref.read(foldersNotifierProvider.notifier).createFolder(
                    name: name,
                    parentId: widget.folderId,
                  );

              if (!context.mounted) return;
              Navigator.pop(context);
              if (folder != null) {
                ref.invalidate(subfoldersProvider(widget.folderId));
                ref.invalidate(folderProvider(widget.folderId));
                ToastUtils.showSuccess('Subfolder created');
              } else {
                ToastUtils.showError('Failed to create subfolder');
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: context.accentColor, foregroundColor: Colors.white),
            child: const Text('Create', style: TextStyle(fontFamily: 'ProductSans')),
          ),
        ],
      ),
    );
  }

  void _showSubfolderOptions(VaultFolder subfolder) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.4,
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
                      subfolder.name,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                        fontFamily: 'ProductSans',
                      ),
                    ),
                    const SizedBox(height: 20),
                    ListTile(
                      leading: Icon(Icons.edit_outlined, color: AppColors.lightTextPrimary),
                      title: Text('Rename', style: TextStyle(fontFamily: 'ProductSans', color: AppColors.lightTextPrimary)),
                      contentPadding: EdgeInsets.zero,
                      onTap: () {
                        Navigator.pop(context);
                        _showRenameSubfolderDialog(subfolder);
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.delete_outline, color: AppColors.error),
                      title: Text('Delete', style: TextStyle(fontFamily: 'ProductSans', color: AppColors.error)),
                      contentPadding: EdgeInsets.zero,
                      onTap: () {
                        Navigator.pop(context);
                        _showDeleteSubfolderDialog(subfolder);
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

  void _showRenameSubfolderDialog(VaultFolder subfolder) {
    final nameController = TextEditingController(text: subfolder.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text('Rename Subfolder', style: TextStyle(fontFamily: 'ProductSans', color: context.textPrimary)),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: 'Folder Name',
            labelStyle: TextStyle(fontFamily: 'ProductSans', color: context.textSecondary),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.accentColor),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(fontFamily: 'ProductSans', color: context.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                ToastUtils.showError('Please enter folder name');
                return;
              }

              final updated = await ref.read(foldersNotifierProvider.notifier).updateFolder(
                    subfolder.copyWith(name: name),
                  );

              if (!context.mounted) return;
              Navigator.pop(context);
              if (updated != null) {
                ref.invalidate(subfoldersProvider(widget.folderId));
                ToastUtils.showSuccess('Subfolder renamed');
              } else {
                ToastUtils.showError('Failed to rename subfolder');
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: context.accentColor, foregroundColor: Colors.white),
            child: const Text('Rename', style: TextStyle(fontFamily: 'ProductSans')),
          ),
        ],
      ),
    );
  }

  void _showDeleteSubfolderDialog(VaultFolder subfolder) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text('Delete Subfolder', style: TextStyle(fontFamily: 'ProductSans', color: context.textPrimary)),
        content: Text(
          'Are you sure you want to delete "${subfolder.name}"? Files in this subfolder will not be deleted from the vault.',
          style: TextStyle(fontFamily: 'ProductSans', color: context.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(fontFamily: 'ProductSans', color: context.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final deleted = await ref.read(foldersNotifierProvider.notifier).deleteFolder(subfolder.id);

              if (!context.mounted) return;
              Navigator.pop(context);
              if (deleted) {
                ref.invalidate(subfoldersProvider(widget.folderId));
                ref.invalidate(folderProvider(widget.folderId));
                ToastUtils.showSuccess('Subfolder deleted');
              } else {
                ToastUtils.showError('Failed to delete subfolder');
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            child: const Text('Delete', style: TextStyle(fontFamily: 'ProductSans')),
          ),
        ],
      ),
    );
  }

  void _showAddFilesSheet() {
    final allFilesAsync = ref.read(vaultNotifierProvider);
    final folderFilesAsync = ref.read(filesInFolderProvider(widget.folderId));

    final allFiles = allFilesAsync.value ?? [];
    final folderFileIds = (folderFilesAsync.value ?? []).map((f) => f.id).toSet();
    final availableFiles = allFiles.where((f) => !folderFileIds.contains(f.id)).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _AddFilesToFolderSheet(
        availableFiles: availableFiles,
        folderId: widget.folderId,
        onFilesAdded: () {
          ref.invalidate(filesInFolderProvider(widget.folderId));
          ref.invalidate(folderProvider(widget.folderId));
          ref.invalidate(foldersNotifierProvider);
        },
      ),
    );
  }

  Future<void> _importFolderFromDevice() async {
    final selectedPath = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => _FolderImportPickerScreen(),
      ),
    );

    if (selectedPath == null || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ImportProgressDialog(
        folderPath: selectedPath,
        parentFolderId: widget.folderId,
      ),
    );
  }

  void get _showAddOptions {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
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
                      'Add to Folder',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                        fontFamily: 'ProductSans',
                      ),
                    ),
                    const SizedBox(height: 20),
                    ListTile(
                      leading: Icon(Icons.add_photo_alternate, color: context.accentColor),
                      title: Text('Add Files from Vault', style: TextStyle(fontFamily: 'ProductSans', color: context.textPrimary)),
                      contentPadding: EdgeInsets.zero,
                      onTap: () {
                        Navigator.pop(context);
                        _showAddFilesSheet();
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.create_new_folder_outlined, color: context.accentColor),
                      title: Text('Create Subfolder', style: TextStyle(fontFamily: 'ProductSans', color: context.textPrimary)),
                      contentPadding: EdgeInsets.zero,
                      onTap: () {
                        Navigator.pop(context);
                        _showCreateSubfolderDialog();
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.drive_folder_upload_outlined, color: context.accentColor),
                      title: Text('Import from Device', style: TextStyle(fontFamily: 'ProductSans', color: context.textPrimary)),
                      contentPadding: EdgeInsets.zero,
                      onTap: () {
                        Navigator.pop(context);
                        _importFolderFromDevice();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddFilesToFolderSheet extends ConsumerStatefulWidget {
  final List<VaultedFile> availableFiles;
  final String folderId;
  final VoidCallback onFilesAdded;

  const _AddFilesToFolderSheet({
    required this.availableFiles,
    required this.folderId,
    required this.onFilesAdded,
  });

  @override
  ConsumerState<_AddFilesToFolderSheet> createState() => _AddFilesToFolderSheetState();
}

class _AddFilesToFolderSheetState extends ConsumerState<_AddFilesToFolderSheet> {
  final Set<String> _selectedFileIds = {};
  bool _isAdding = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: context.backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
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
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Add Files to Folder',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimary,
                      fontFamily: 'ProductSans',
                    ),
                  ),
                ),
                if (_selectedFileIds.isNotEmpty)
                  ElevatedButton(
                    onPressed: _isAdding ? null : _addFiles,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.accentColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: _isAdding
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            'Add (${_selectedFileIds.length})',
                            style: const TextStyle(fontFamily: 'ProductSans'),
                          ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: widget.availableFiles.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox, size: 64, color: context.textTertiary),
                        const SizedBox(height: 16),
                        Text(
                          'No files available',
                          style: TextStyle(fontFamily: 'ProductSans', color: context.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'All vault files are already in this folder',
                          style: TextStyle(
                            fontFamily: 'ProductSans',
                            fontSize: 12,
                            color: context.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
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
                    itemCount: widget.availableFiles.length,
                    itemBuilder: (context, index) {
                      final file = widget.availableFiles[index];
                      final isSelected = _selectedFileIds.contains(file.id);
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedFileIds.remove(file.id);
                            } else {
                              _selectedFileIds.add(file.id);
                            }
                          });
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
                            if (isSelected)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: context.accentColor,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: const Icon(Icons.check, size: 16, color: Colors.white),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
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
    return _buildPlaceholder(file);
  }

  Widget _buildPlaceholder(VaultedFile file) {
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
      color: context.accentColor.withValues(alpha: 0.1),
      child: Center(child: Icon(icon, size: 32, color: context.accentColor)),
    );
  }

  Future<void> _addFiles() async {
    setState(() => _isAdding = true);

    for (final fileId in _selectedFileIds) {
      await ref.read(foldersNotifierProvider.notifier).addFileToFolder(fileId, widget.folderId);
    }

    widget.onFilesAdded();

    if (mounted) {
      Navigator.pop(context);
      ToastUtils.showSuccess('Files added to folder');
    }
  }
}

class _FolderImportPickerScreen extends StatefulWidget {
  const _FolderImportPickerScreen();

  @override
  State<_FolderImportPickerScreen> createState() => _FolderImportPickerScreenState();
}

class _FolderImportPickerScreenState extends State<_FolderImportPickerScreen> {
  String? _currentPath;
  List<String> _pathStack = [];
  List<FileSystemEntity> _subdirs = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRoots();
  }

  Future<void> _loadRoots() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final roots = await _getRoots();
      if (roots.isEmpty) {
        setState(() {
          _isLoading = false;
          _error = 'No accessible storage found';
        });
        return;
      }
      _navigateInto(roots.first);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<List<String>> _getRoots() async {
    final roots = <String>[];
    if (Platform.isAndroid) {
      roots.add('/storage/emulated/0');
    }
    final appDir = await getApplicationDocumentsDirectory();
    if (!roots.contains(appDir.path)) {
      roots.add(appDir.path);
    }
    return roots;
  }

  Future<void> _navigateInto(String path) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        setState(() {
          _isLoading = false;
          _error = 'Directory does not exist';
        });
        return;
      }

      final entities = await dir.list().toList();
      final subdirs = entities
          .whereType<Directory>()
          .where((d) => !d.path.split('/').last.startsWith('.'))
          .where((d) => d.path.split('/').last != 'Android')
          .toList()
        ..sort((a, b) => a.path.split('/').last.toLowerCase().compareTo(b.path.split('/').last.toLowerCase()));

      setState(() {
        if (_currentPath != null) {
          _pathStack.add(_currentPath!);
        }
        _currentPath = path;
        _subdirs = subdirs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
_isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _selectCurrentFolder() async {
    if (_currentPath != null) {
      Navigator.pop(context, _currentPath);
    }
  }

  void _goBack() {
    if (_pathStack.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final previousPath = _pathStack.removeLast();
    _currentPath = null;
    _navigateInto(previousPath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: _pathStack.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _goBack,
                color: context.textPrimary,
              )
            : null,
        title: const Text(
          'Select Folder to Import',
          style: TextStyle(fontFamily: 'ProductSans', fontWeight: FontWeight.w600),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: context.textPrimary,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: AppColors.error),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(fontFamily: 'ProductSans', color: context.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    if (_pathStack.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: InkWell(
                          onTap: _goBack,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Row(
                              children: [
                                const Icon(Icons.arrow_back, size: 14, color: AppColors.accent),
                                const SizedBox(width: 8),
                                Icon(Icons.folder, size: 16, color: context.accentColor),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _currentPath ?? '',
                                    style: TextStyle(
                                      fontFamily: 'ProductSans',
                                      fontSize: 12,
                                      color: context.textTertiary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: _subdirs.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.folder_off_outlined, size: 48, color: context.textTertiary),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No subfolders',
                                    style: TextStyle(fontFamily: 'ProductSans', color: context.textSecondary),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(8),
                              itemCount: _subdirs.length,
                              itemBuilder: (context, index) {
                                final dir = _subdirs[index];
                                final name = dir.path.split('/').last;
                                return ListTile(
                                  leading: Icon(Icons.folder, color: context.accentColor),
                                  title: Text(name, style: TextStyle(fontFamily: 'ProductSans', color: context.textPrimary)),
                                  trailing: Icon(Icons.chevron_right, color: context.textTertiary),
                                  onTap: () => _navigateInto(dir.path),
                                );
                              },
                            ),
                    ),
                  ],
                ),
      bottomNavigationBar: _currentPath != null
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  onPressed: _selectCurrentFolder,
                  icon: const Icon(Icons.check),
                  label: const Text(
                    'Import This Folder',
                    style: TextStyle(fontFamily: 'ProductSans', fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.accentColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

class _ImportProgressDialog extends ConsumerStatefulWidget {
  final String folderPath;
  final String? parentFolderId;

  const _ImportProgressDialog({
    required this.folderPath,
    this.parentFolderId,
  });

  @override
  ConsumerState<_ImportProgressDialog> createState() => _ImportProgressDialogState();
}

class _ImportProgressDialogState extends ConsumerState<_ImportProgressDialog> {
  bool _isImporting = true;
  String _status = 'Importing folder...';
  String? _error;

  @override
  void initState() {
    super.initState();
    _importFolder();
  }

  Future<void> _importFolder() async {
    try {
      final importService = FileImportService.instance;
      final result = await importService.importFolder(
        folderPath: widget.folderPath,
        parentFolderId: widget.parentFolderId,
        recursive: true,
        deleteOriginals: false,
      );

      if (!mounted) return;

      setState(() {
        _isImporting = false;
        if (result.success) {
          _status = result.message ??
              'Imported ${result.filesImported} file(s) into ${result.foldersCreated} folder(s)';
        } else {
          _error = result.error ?? 'Import failed';
          _status = _error!;
        }
      });

      ref.invalidate(foldersNotifierProvider);
      ref.invalidate(vaultNotifierProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isImporting = false;
        _error = e.toString();
        _status = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      title: Text(
        _isImporting ? 'Importing Folder' : (_error != null ? 'Import Failed' : 'Import Complete'),
        style: TextStyle(fontFamily: 'ProductSans', color: context.textPrimary),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isImporting) ...[
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
          ] else if (_error == null) ...[
            Icon(Icons.check_circle, size: 48, color: AppColors.success),
            const SizedBox(height: 16),
          ] else ...[
            Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
          ],
          Text(
            _status,
            style: TextStyle(fontFamily: 'ProductSans', color: context.textSecondary, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        if (!_isImporting)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              _error != null ? 'OK' : 'Done',
              style: TextStyle(fontFamily: 'ProductSans', color: context.accentColor),
            ),
          ),
      ],
    );
  }
}