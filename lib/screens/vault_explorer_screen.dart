import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/vault_folder.dart';
import '../providers/vault_providers.dart';
import '../providers/explorer_providers.dart';
import '../themes/app_colors.dart';
import '../utils/toast_utils.dart';
import '../widgets/folder_tree_widget.dart';
import '../widgets/folder_breadcrumb_widget.dart';
import '../widgets/explorer_file_grid.dart';
import '../widgets/explorer_toolbar.dart';

class VaultExplorerScreen extends ConsumerStatefulWidget {
  const VaultExplorerScreen({super.key});

  @override
  ConsumerState<VaultExplorerScreen> createState() =>
      _VaultExplorerScreenState();
}

class _VaultExplorerScreenState extends ConsumerState<VaultExplorerScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSelectionMode = ref.watch(isSelectionModeProvider);
    final selectedFiles = ref.watch(selectedFilesProvider);
    final viewMode = ref.watch(explorerViewModeProvider);
    final currentFolderAsync = ref.watch(explorerCurrentFolderProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(currentFolderAsync, isSelectionMode, selectedFiles),
      body: _buildBody(viewMode),
      floatingActionButton: isSelectionMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showCreateFolderDialog(),
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

  PreferredSizeWidget _buildAppBar(
    AsyncValue<VaultFolder?> folderAsync,
    bool isSelectionMode,
    Set<String> selectedFiles,
  ) {
    if (isSelectionMode) {
      return _buildSelectionAppBar(selectedFiles);
    }

    final title = folderAsync.when(
      loading: () => 'File Explorer',
      error: (_, __) => 'File Explorer',
      data: (folder) => folder?.name ?? 'File Explorer',
    );

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      title: Text(
        title,
        style: TextStyle(
          fontFamily: 'ProductSans',
          fontWeight: FontWeight.bold,
          fontSize: 18,
          color: context.textPrimary,
        ),
      ),
    );
  }

  PreferredSizeWidget _buildSelectionAppBar(Set<String> selectedFiles) {
    final filesAsync = ref.watch(explorerFilesProvider);
    final files = filesAsync.value ?? [];
    final allSelected = files.isNotEmpty && files.every((f) => selectedFiles.contains(f.id));

    return AppBar(
      backgroundColor: context.accentColor,
      leading: IconButton(
        icon: const Icon(Icons.close, color: Colors.white),
        onPressed: () {
          ref.read(selectedFilesProvider.notifier).state = {};
          ref.read(isSelectionModeProvider.notifier).state = false;
        },
      ),
      title: Text(
        '${selectedFiles.length} selected',
        style: const TextStyle(fontFamily: 'ProductSans', color: Colors.white),
      ),
      actions: [
        if (files.isNotEmpty)
          TextButton(
            onPressed: () {
              if (allSelected) {
                ref.read(selectedFilesProvider.notifier).state = {};
                ref.read(isSelectionModeProvider.notifier).state = false;
              } else {
                ref.read(selectedFilesProvider.notifier).state = files.map((f) => f.id).toSet();
              }
            },
            child: Text(
              allSelected ? 'Deselect All' : 'Select All',
              style: const TextStyle(color: Colors.white, fontFamily: 'ProductSans'),
            ),
          ),
      ],
    );
  }

  Widget _buildBody(ExplorerViewMode viewMode) {
    if (viewMode == ExplorerViewMode.sidebar) {
      return Row(
        children: [
          SizedBox(
            width: 240,
            child: FolderTreeWidget(
              onFolderLongPress: (folder) => _showFolderOptions(folder),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: Column(
              children: [
                const ExplorerToolbar(),
                Expanded(
                  child: ExplorerFileGrid(
                    onFolderLongPress: (folder) => _showFolderOptions(folder),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Navigation mode
    return Column(
      children: [
        const FolderBreadcrumbWidget(),
        const ExplorerToolbar(),
        Expanded(
          child: ExplorerFileGrid(
            onFolderLongPress: (folder) => _showFolderOptions(folder),
          ),
        ),
      ],
    );
  }

  // ───── Folder Operations (Create, Rename, Delete) ─────

  void _showCreateFolderDialog() {
    _nameController.clear();
    _descController.clear();
    final currentFolderId = ref.read(explorerCurrentFolderIdProvider);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          currentFolderId != null ? 'Create Subfolder' : 'Create Folder',
          style: TextStyle(fontFamily: 'ProductSans', color: context.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Folder Name',
                labelStyle:
                    TextStyle(fontFamily: 'ProductSans', color: this.context.textSecondary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: this.context.accentColor),
                ),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                labelStyle:
                    TextStyle(fontFamily: 'ProductSans', color: this.context.textSecondary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: this.context.accentColor),
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
              style: TextStyle(fontFamily: 'ProductSans', color: this.context.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = _nameController.text.trim();
              if (name.isEmpty) {
                ToastUtils.showError('Please enter folder name');
                return;
              }

              final folder = await ref.read(foldersNotifierProvider.notifier).createFolder(
                    name: name,
                    parentId: currentFolderId,
                    description:
                        _descController.text.trim().isEmpty ? null : _descController.text.trim(),
                  );

              if (!context.mounted) return;
              Navigator.pop(context);
              if (folder != null) {
                ToastUtils.showSuccess('Folder created');
                ref.invalidate(explorerSubfoldersProvider);
              } else {
                ToastUtils.showError('Failed to create folder');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: this.context.accentColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Create', style: TextStyle(fontFamily: 'ProductSans')),
          ),
        ],
      ),
    );
  }

  void _showFolderOptions(VaultFolder folder) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
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
                  color: this.context.borderColor,
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
                        color: this.context.textPrimary,
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
                        ref.read(explorerCurrentFolderIdProvider.notifier).state = folder.id;
                        _showCreateFolderDialog();
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

  void _showRenameFolderDialog(VaultFolder folder) {
    final controller = TextEditingController(text: folder.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text('Rename Folder',
            style: TextStyle(fontFamily: 'ProductSans', color: this.context.textPrimary)),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Folder Name',
            labelStyle:
                TextStyle(fontFamily: 'ProductSans', color: this.context.textSecondary),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: this.context.accentColor),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(fontFamily: 'ProductSans', color: this.context.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) {
                ToastUtils.showError('Please enter folder name');
                return;
              }
              final updated = folder.copyWith(name: name);
              final result =
                  await ref.read(foldersNotifierProvider.notifier).updateFolder(updated);
              if (!context.mounted) return;
              Navigator.pop(context);
              if (result != null) {
                ToastUtils.showSuccess('Folder renamed');
                ref.invalidate(explorerSubfoldersProvider);
                ref.invalidate(explorerCurrentFolderProvider);
              } else {
                ToastUtils.showError('Failed to rename folder');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: this.context.accentColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Rename', style: TextStyle(fontFamily: 'ProductSans')),
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
        title: Text('Delete Folder',
            style: TextStyle(fontFamily: 'ProductSans', color: this.context.textPrimary)),
        content: Text(
          'Are you sure you want to delete "${folder.name}"? Files in this folder will not be deleted from the vault.',
          style: TextStyle(fontFamily: 'ProductSans', color: this.context.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(fontFamily: 'ProductSans', color: this.context.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final deleted =
                  await ref.read(foldersNotifierProvider.notifier).deleteFolder(folder.id);
              if (!context.mounted) return;
              Navigator.pop(context);
              if (deleted) {
                ToastUtils.showSuccess('Folder deleted');
                final currentId = ref.read(explorerCurrentFolderIdProvider);
                if (currentId == folder.id) {
                  ref.read(explorerCurrentFolderIdProvider.notifier).state = folder.parentId;
                }
                ref.invalidate(explorerSubfoldersProvider);
                ref.invalidate(explorerCurrentFolderProvider);
              } else {
                ToastUtils.showError('Failed to delete folder');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete', style: TextStyle(fontFamily: 'ProductSans')),
          ),
        ],
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
      leading: Icon(icon, color: color ?? context.textPrimary, size: 22),
      title: Text(
        label,
        style: TextStyle(fontFamily: 'ProductSans', color: color ?? context.textPrimary, fontSize: 14),
      ),
      subtitle: subtitle != null
          ? Text(subtitle,
              style:
                  TextStyle(fontFamily: 'ProductSans', color: context.textTertiary, fontSize: 12))
          : null,
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
    );
  }
}
