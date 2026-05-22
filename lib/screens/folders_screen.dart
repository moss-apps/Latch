import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../models/vault_folder.dart';
import '../models/vaulted_file.dart';
import '../providers/vault_providers.dart';
import '../services/file_import_service.dart';
import '../themes/app_colors.dart';
import '../utils/toast_utils.dart';
import '../utils/responsive_utils.dart';
import 'folder_detail_screen.dart';

class FoldersScreen extends ConsumerStatefulWidget {
  const FoldersScreen({super.key});

  @override
  ConsumerState<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends ConsumerState<FoldersScreen> {
  @override
  Widget build(BuildContext context) {
    final foldersAsync = ref.watch(foldersNotifierProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Folders',
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: context.textPrimary,
        elevation: 0,
      ),
      body: foldersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: AppColors.lightTextTertiary),
              const SizedBox(height: 16),
              Text(
                'Failed to load folders',
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  color: context.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () =>
                    ref.read(foldersNotifierProvider.notifier).loadFolders(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (folders) {
          final rootFolders =
              folders.where((f) => f.isRoot).toList();
          return _buildFoldersList(rootFolders);
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateOptions,
        backgroundColor: context.accentColor,
        icon: const Icon(Icons.create_new_folder, color: Colors.white),
        label: const Text(
          'New Folder',
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildFoldersList(List<VaultFolder> rootFolders) {
    if (rootFolders.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(foldersNotifierProvider.notifier).loadFolders();
      },
      color: context.accentColor,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader('Root Folders'),
          const SizedBox(height: 12),
          _buildFoldersGrid(rootFolders),
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

  Widget _buildFoldersGrid(List<VaultFolder> folders) {
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
      itemCount: folders.length,
      itemBuilder: (context, index) => _buildFolderCard(folders[index]),
    );
  }

  Widget _buildFolderCard(VaultFolder folder) {
    return GestureDetector(
      onTap: () => _openFolder(folder),
      onLongPress: () => _showFolderOptions(folder),
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
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: _buildFolderCover(folder),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        folder.hasSubfolders
                            ? Icons.folder
                            : Icons.folder_outlined,
                        size: 16,
                        color: context.accentColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          folder.name,
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
                    _getFolderItemCount(folder),
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

  Widget _buildFolderCover(VaultFolder folder) {
    if (folder.coverImageId != null) {
      return FutureBuilder<VaultedFile?>(
        future: ref.read(vaultServiceProvider).getFileById(folder.coverImageId!),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            final file = snapshot.data!;
            if (file.isImage) {
              final imageFile = File(file.vaultPath);
              return FutureBuilder<bool>(
                future: imageFile.exists(),
                builder: (context, existsSnapshot) {
                  if (existsSnapshot.data != true) {
                    return _buildPlaceholderCover();
                  }
                  return Image.file(
                    imageFile,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    cacheWidth: 400,
                    filterQuality: FilterQuality.low,
                    errorBuilder: (_, __, ___) => _buildPlaceholderCover(),
                  );
                },
              );
            }
          }
          return _buildPlaceholderCover();
        },
      );
    }

    return _buildPlaceholderCover();
  }

  Widget _buildPlaceholderCover() {
    return Container(
      color: context.accentColor.withValues(alpha: 0.1),
      child: Center(
        child: Icon(
          Icons.folder_outlined,
          size: 48,
          color: context.accentColor,
        ),
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
              Icons.folder_outlined,
              size: 64,
              color: context.textTertiary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No folders yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
              fontFamily: 'ProductSans',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create folders to organize your files',
            style: TextStyle(
              fontSize: 14,
              color: context.textSecondary,
              fontFamily: 'ProductSans',
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showCreateOptions,
            icon: const Icon(Icons.create_new_folder),
            label: const Text('Create Folder'),
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

  void _openFolder(VaultFolder folder) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FolderDetailScreen(folderId: folder.id),
      ),
    );
  }

  void _showCreateOptions() {
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
                      'Create Folder',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                        fontFamily: 'ProductSans',
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildOptionTile(
                      icon: Icons.create_new_folder_outlined,
                      label: 'Empty Folder',
                      subtitle: 'Create a new empty folder',
                      onTap: () {
                        Navigator.pop(context);
                        _showCreateFolderDialog();
                      },
                    ),
                    _buildOptionTile(
                      icon: Icons.drive_folder_upload_outlined,
                      label: 'Import from Device',
                      subtitle: 'Import a folder from your device',
                      onTap: () {
                        Navigator.pop(context);
                        _importFolderFromDevice();
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

  Widget _buildOptionTile({
    required IconData icon,
    required String label,
    String? subtitle,
    required VoidCallback onTap,
    Color? color,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? context.textPrimary),
      title: Text(
        label,
        style: TextStyle(
          fontFamily: 'ProductSans',
          color: color ?? context.textPrimary,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: context.textTertiary,
                fontSize: 12,
              ),
            )
          : null,
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
    );
  }

  void _showFolderOptions(VaultFolder folder) {
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
                      folder.name,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                        fontFamily: 'ProductSans',
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildOptionTile(
                      icon: Icons.edit_outlined,
                      label: 'Rename Folder',
                      onTap: () {
                        Navigator.pop(context);
                        _showRenameFolderDialog(folder);
                      },
                    ),
                    _buildOptionTile(
                      icon: Icons.create_new_folder,
                      label: 'Add Subfolder',
                      onTap: () {
                        Navigator.pop(context);
                        _showCreateSubfolderDialog(folder);
                      },
                    ),
                    _buildOptionTile(
                      icon: Icons.drive_folder_upload_outlined,
                      label: 'Import into Folder',
                      subtitle: 'Import a device folder as a subfolder',
                      onTap: () {
                        Navigator.pop(context);
                        _importFolderFromDevice(parentFolderId: folder.id);
                      },
                    ),
                    _buildOptionTile(
                      icon: Icons.delete_outline,
                      label: 'Delete Folder',
                      color: AppColors.error,
                      onTap: () {
                        Navigator.pop(context);
                        _showDeleteFolderDialog(folder);
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

  void _showCreateFolderDialog({String? parentFolderId}) {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          parentFolderId != null ? 'Create Subfolder' : 'Create Folder',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Folder Name',
                labelStyle: TextStyle(
                  fontFamily: 'ProductSans',
                  color: context.textSecondary,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.accentColor),
                ),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                labelStyle: TextStyle(
                  fontFamily: 'ProductSans',
                  color: context.textSecondary,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.accentColor),
                ),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: context.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                ToastUtils.showError('Please enter folder name');
                return;
              }

              final folder = await ref
                  .read(foldersNotifierProvider.notifier)
                  .createFolder(
                    name: name,
                    parentId: parentFolderId,
                    description: descController.text.trim().isEmpty
                        ? null
                        : descController.text.trim(),
                  );

              if (!context.mounted) return;
              Navigator.pop(context);
              if (folder != null) {
                ToastUtils.showSuccess('Folder created');
              } else {
                ToastUtils.showError('Failed to create folder');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: context.accentColor,
              foregroundColor: Colors.white,
            ),
            child: const Text(
              'Create',
              style: TextStyle(fontFamily: 'ProductSans'),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateSubfolderDialog(VaultFolder parentFolder) {
    _showCreateFolderDialog(parentFolderId: parentFolder.id);
  }

  void _showRenameFolderDialog(VaultFolder folder) {
    final nameController = TextEditingController(text: folder.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          'Rename Folder',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textPrimary,
          ),
        ),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: 'Folder Name',
            labelStyle: TextStyle(
              fontFamily: 'ProductSans',
              color: context.textSecondary,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
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
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: context.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                ToastUtils.showError('Please enter folder name');
                return;
              }

              final updated = await ref
                  .read(foldersNotifierProvider.notifier)
                  .updateFolder(folder.copyWith(name: name));

              if (!context.mounted) return;
              Navigator.pop(context);
              if (updated != null) {
                ToastUtils.showSuccess('Folder renamed');
              } else {
                ToastUtils.showError('Failed to rename folder');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: context.accentColor,
              foregroundColor: Colors.white,
            ),
            child: const Text(
              'Rename',
              style: TextStyle(fontFamily: 'ProductSans'),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteFolderDialog(VaultFolder folder) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          'Delete Folder',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textPrimary,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${folder.name}"? Files in this folder will not be deleted from the vault.',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: context.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final deleted = await ref
                  .read(foldersNotifierProvider.notifier)
                  .deleteFolder(folder.id);

              if (!context.mounted) return;
              Navigator.pop(context);
              if (deleted) {
                ToastUtils.showSuccess('Folder deleted');
              } else {
                ToastUtils.showError('Failed to delete folder');
              }
            },
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
  }

  Future<void> _importFolderFromDevice({String? parentFolderId}) async {
    final selectedPath = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => const _FolderImportPickerScreen(),
      ),
    );

    if (selectedPath == null || !mounted) return;

    _showImportProgressDialog(selectedPath, parentFolderId: parentFolderId);
  }

  void _showImportProgressDialog(String folderPath, {String? parentFolderId}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ImportProgressDialog(
        folderPath: folderPath,
        parentFolderId: parentFolderId,
      ),
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
  ConsumerState<_ImportProgressDialog> createState() =>
      _ImportProgressDialogState();
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
        style: TextStyle(
          fontFamily: 'ProductSans',
          color: context.textPrimary,
        ),
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
            style: TextStyle(
              fontFamily: 'ProductSans',
              color: context.textSecondary,
              fontSize: 14,
            ),
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
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: context.accentColor,
              ),
            ),
          ),
      ],
    );
  }
}

class _FolderImportPickerScreen extends StatefulWidget {
  const _FolderImportPickerScreen();

  @override
  State<_FolderImportPickerScreen> createState() =>
      _FolderImportPickerScreenState();
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
                        style: TextStyle(
                          fontFamily: 'ProductSans',
                          color: context.textSecondary,
                        ),
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
                                    style: TextStyle(
                                      fontFamily: 'ProductSans',
                                      color: context.textSecondary,
                                    ),
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
                                  title: Text(
                                    name,
                                    style: TextStyle(fontFamily: 'ProductSans', color: context.textPrimary),
                                  ),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}