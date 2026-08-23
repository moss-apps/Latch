import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/note.dart';
import '../providers/note_providers.dart';
import '../themes/app_colors.dart';
import '../utils/toast_utils.dart';

class NoteFoldersScreen extends ConsumerStatefulWidget {
  const NoteFoldersScreen({super.key});

  @override
  ConsumerState<NoteFoldersScreen> createState() => _NoteFoldersScreenState();
}

class _NoteFoldersScreenState extends ConsumerState<NoteFoldersScreen> {
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final foldersAsync = ref.watch(noteFoldersNotifierProvider);
    final notesAsync = ref.watch(notesNotifierProvider);

    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        backgroundColor: context.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Note Folders',
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
        ),
      ),
      body: foldersAsync.when(
        data: (folders) {
          if (folders.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 64,
                    color: context.textTertiary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No folders yet',
                    style: TextStyle(
                      fontFamily: 'ProductSans',
                      fontSize: 16,
                      color: context.textTertiary,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: folders.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: context.dividerColor,
            ),
            itemBuilder: (context, index) {
              final folder = folders[index];
              final noteCount = notesAsync.whenOrNull(
                    data: (notes) =>
                        notes.where((n) => n.folderId == folder.id).length,
                  ) ??
                  0;

              return ListTile(
                leading: Icon(Icons.folder_outlined,
                    color: context.textSecondary),
                title: Text(
                  folder.name,
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
                subtitle: Text(
                  '$noteCount ${noteCount == 1 ? 'note' : 'notes'}',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 12,
                    color: context.textTertiary,
                  ),
                ),
                trailing: PopupMenuButton<String>(
                  icon:
                      Icon(Icons.more_vert, color: context.textSecondary),
                  color: context.surfaceColor,
                  onSelected: (value) {
                    if (value == 'rename') {
                      _showRenameDialog(folder);
                    } else if (value == 'delete') {
                      _showDeleteConfirmation(folder);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined,
                              size: 18, color: context.textSecondary),
                          const SizedBox(width: 12),
                          Text(
                            'Rename',
                            style: TextStyle(
                              fontFamily: 'ProductSans',
                              color: context.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline,
                              size: 18, color: AppColors.error),
                          const SizedBox(width: 12),
                          Text(
                            'Delete',
                            style: TextStyle(
                              fontFamily: 'ProductSans',
                              color: AppColors.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                onTap: () {
                  ref.read(selectedNoteFolderProvider.notifier).state =
                      folder.id;
                  Navigator.pop(context);
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            'Error loading folders',
            style: TextStyle(
              fontFamily: 'ProductSans',
              color: context.textTertiary,
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        backgroundColor: context.accentColor,
        elevation: 0,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Future<void> _showCreateDialog() async {
    _nameController.clear();
    final name = await _showNameDialog('New Folder', '');
    if (name != null && name.isNotEmpty && mounted) {
      try {
        await ref.read(noteFoldersNotifierProvider.notifier).createFolder(name);
        if (mounted) ToastUtils.showSuccess('Folder created');
      } catch (e) {
        if (mounted) ToastUtils.showError('Failed to create folder');
      }
    }
  }

  Future<void> _showRenameDialog(NoteFolder folder) async {
    _nameController.text = folder.name;
    final name = await _showNameDialog('Rename Folder', folder.name);
    if (name != null && name.isNotEmpty && mounted) {
      try {
        await ref
            .read(noteFoldersNotifierProvider.notifier)
            .renameFolder(folder, name);
        if (mounted) ToastUtils.showSuccess('Folder renamed');
      } catch (e) {
        if (mounted) ToastUtils.showError('Failed to rename folder');
      }
    }
  }

  Future<String?> _showNameDialog(String title, String initial) async {
    _nameController.text = initial;
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.surfaceColor,
        title: Text(
          title,
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
        ),
        content: TextField(
          controller: _nameController,
          autofocus: true,
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: 'Folder name',
            hintStyle: TextStyle(
              fontFamily: 'ProductSans',
              color: context.textTertiary,
            ),
            filled: true,
            fillColor: context.backgroundColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: context.borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: context.borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: context.accentColor),
            ),
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
          TextButton(
            onPressed: () => Navigator.pop(context, _nameController.text.trim()),
            child: Text(
              'Save',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: context.accentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteConfirmation(NoteFolder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.surfaceColor,
        title: Text(
          'Delete Folder',
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
        ),
        content: Text(
          'Delete "${folder.name}"? Notes in this folder will not be deleted.',
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
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await ref
            .read(noteFoldersNotifierProvider.notifier)
            .deleteFolder(folder);
        if (mounted) ToastUtils.showSuccess('Folder deleted');
      } catch (e) {
        if (mounted) ToastUtils.showError('Failed to delete folder');
      }
    }
  }
}
