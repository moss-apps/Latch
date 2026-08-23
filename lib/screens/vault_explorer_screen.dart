import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/path_utils.dart';
import '../models/album.dart';
import '../models/vault_folder.dart';
import '../models/vaulted_file.dart';
import '../providers/vault_providers.dart';
import '../providers/explorer_providers.dart';
import '../services/file_import_service.dart';
import '../themes/app_colors.dart';
import '../utils/toast_utils.dart';
import '../widgets/folder_breadcrumb_widget.dart';
import '../widgets/explorer_file_grid.dart';
import '../widgets/explorer_toolbar.dart';
import '../widgets/operation_progress_sheet.dart';
import '../widgets/media_multi_select_action_sheet.dart';
import 'note_list_screen.dart';
import 'password_list_screen.dart';

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
    final currentFolderAsync = ref.watch(explorerCurrentFolderProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(currentFolderAsync, isSelectionMode, selectedFiles),
      body: _buildBody(),
      floatingActionButton: isSelectionMode
          ? null
          : FloatingActionButton.extended(
              elevation: 0,
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
      actions: [
        IconButton(
          icon: Icon(Icons.note_outlined, color: context.textSecondary),
          tooltip: 'Notes',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NoteListScreen()),
            );
          },
        ),
        IconButton(
          icon: Icon(Icons.password, color: context.textSecondary),
          tooltip: 'Passwords',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PasswordListScreen()),
            );
          },
        ),
      ],
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
        onPressed: _exitSelectionMode,
      ),
      title: Text(
        '${selectedFiles.length} selected',
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
        if (selectedFiles.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () => _showMultiSelectActionSheet(selectedFiles),
            tooltip: 'Actions',
          ),
      ],
    );
  }

  Widget _buildBody() {
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

  // ───── Selection Actions ─────

  void _exitSelectionMode() {
    ref.read(selectedFilesProvider.notifier).state = {};
    ref.read(isSelectionModeProvider.notifier).state = false;
  }

  void _toggleSelectAll() {
    final files = ref.read(explorerFilesProvider).value ?? <VaultedFile>[];
    final selected = ref.read(selectedFilesProvider);
    final allSelected = files.isNotEmpty && files.every((f) => selected.contains(f.id));

    if (allSelected) {
      final newSelection = Set<String>.from(selected)
        ..removeAll(files.map((f) => f.id));
      ref.read(selectedFilesProvider.notifier).state = newSelection;
      if (newSelection.isEmpty) {
        _exitSelectionMode();
      }
    } else {
      final newSelection = Set<String>.from(selected)
        ..addAll(files.map((f) => f.id));
      ref.read(selectedFilesProvider.notifier).state = newSelection;
    }
  }

  void _invalidateExplorerProviders() {
    ref.invalidate(explorerFilesProvider);
    ref.invalidate(explorerSubfoldersProvider);
    ref.invalidate(unfiledFilesProvider);
  }

  void _showMultiSelectActionSheet(Set<String> selectedFiles) {
    MediaMultiSelectActionSheet.show(
      context,
      fileCount: selectedFiles.length,
      onFavorite: () => _toggleFavoriteSelected(selectedFiles),
      onShare: () => _bulkExportToDownloads(selectedFiles),
      onDelete: () => _deleteSelectedFiles(selectedFiles),
      onTags: () => _showAddTagsSheet(selectedFiles),
      onAddToAlbum: () => _showAddToAlbumSheet(selectedFiles),
      onUnhide: () => _unhideSelectedFiles(selectedFiles),
      onCancelSelection: _exitSelectionMode,
    );
  }

  Future<void> _bulkExportToDownloads(Set<String> selectedFiles) async {
    final files = ref.read(explorerFilesProvider).value ?? [];
    final selected = files.where((f) => selectedFiles.contains(f.id)).toList();
    for (final file in selected) {
      await _exportFileToDownloads(file);
    }
  }

  Future<void> _exportFileToDownloads(VaultedFile file) async {
    try {
      final downloadsDir = await PathUtils.getDownloadsDirectory();

      if (downloadsDir == null) {
        ToastUtils.showError('Could not access Downloads folder');
        return;
      }

      final destinationPath = '${downloadsDir.path}/${file.originalName}';
      final vaultService = ref.read(vaultServiceProvider);
      final exportedFile = await vaultService.exportFile(file.id, destinationPath);

      if (exportedFile != null) {
        ToastUtils.showSuccess('Exported ${file.originalName}');
      } else {
        ToastUtils.showError('Failed to export ${file.originalName}');
      }
    } catch (e) {
      debugPrint('Error exporting file: $e');
      ToastUtils.showError('Failed to export file');
    }
  }

  Future<void> _deleteSelectedFiles(Set<String> selectedFiles) async {
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
          'Are you sure you want to delete ${selectedFiles.length} file(s)? This action cannot be undone.',
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

    if (confirmed != true || !mounted) return;

    final progressState = ValueNotifier<OperationProgressState>(
      OperationProgressState(
        totalFiles: selectedFiles.length,
        currentFile: 0,
        currentFileName: 'Preparing...',
        totalSizeBytes: 0,
        processedSizeBytes: 0,
        statusMessage: 'Starting...',
        isProcessing: true,
      ),
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => ValueListenableBuilder<OperationProgressState>(
        valueListenable: progressState,
        builder: (ctx, state, _) => OperationProgressSheet(
          operationType: OperationType.delete,
          totalFiles: state.totalFiles,
          currentFile: state.currentFile,
          currentFileName: state.currentFileName,
          totalSizeBytes: state.totalSizeBytes,
          processedSizeBytes: state.processedSizeBytes,
          statusMessage: state.statusMessage,
          isProcessing: state.isProcessing,
          isComplete: state.isComplete,
          isEncrypting: state.isEncrypting,
        ),
      ),
    );

    final success = await ref.read(vaultNotifierProvider.notifier).deleteFiles(
          selectedFiles.toList(),
          onProgress: (current, total, {int? currentSize, int? totalSize}) {
            progressState.value = progressState.value.copyWith(
              totalFiles: total,
              currentFile: current,
              totalSizeBytes: totalSize ?? 0,
              processedSizeBytes: currentSize ?? 0,
              statusMessage: 'Processing file $current of $total...',
            );
          },
        );

    if (!mounted) return;

    _exitSelectionMode();

    if (success) {
      ToastUtils.showSuccess('Files deleted');
    } else {
      ToastUtils.showError('Failed to delete some files');
    }

    Navigator.pop(context); // Close progress sheet
    _invalidateExplorerProviders();
  }

  void _showAddToAlbumSheet(Set<String> selectedFiles) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final albumsAsync = ref.watch(albumsNotifierProvider);

          return Container(
            decoration: BoxDecoration(
              color: ctx.backgroundColor,
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
                      color: ctx.borderColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add to Album',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: ctx.textPrimary,
                            fontFamily: 'ProductSans',
                          ),
                        ),
                        const SizedBox(height: 16),
                        albumsAsync.when(
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (_, __) => const Text('Failed to load albums'),
                          data: (albums) => Column(
                            children: albums
                                .where((a) => !a.isDefault || a.type == AlbumType.favorites)
                                .map((album) => ListTile(
                                      leading: Icon(
                                        Icons.folder_outlined,
                                        color: ctx.accentColor,
                                      ),
                                      title: Text(
                                        album.name,
                                        style: const TextStyle(fontFamily: 'ProductSans'),
                                      ),
                                      subtitle: Text(
                                        '${album.fileCount} items',
                                        style: TextStyle(
                                          fontFamily: 'ProductSans',
                                          fontSize: 12,
                                          color: ctx.textTertiary,
                                        ),
                                      ),
                                      onTap: () async {
                                        Navigator.pop(ctx);
                                        final success = await ref
                                            .read(vaultNotifierProvider.notifier)
                                            .addToAlbum(
                                              selectedFiles.toList(),
                                              album.id,
                                            );
                                        if (success) {
                                          ToastUtils.showSuccess('Added to ${album.name}');
                                          _exitSelectionMode();
                                          _invalidateExplorerProviders();
                                        } else {
                                          ToastUtils.showError('Failed to add to album');
                                        }
                                      },
                                      contentPadding: EdgeInsets.zero,
                                    ))
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: MediaQuery.of(ctx).padding.bottom),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _toggleFavoriteSelected(Set<String> selectedFiles) async {
    for (final fileId in selectedFiles) {
      await ref.read(vaultNotifierProvider.notifier).toggleFavorite(fileId);
    }
    ToastUtils.showSuccess('Favorites updated');
    _exitSelectionMode();
    _invalidateExplorerProviders();
  }

  void _showAddTagsSheet(Set<String> selectedFiles) {
    final tagController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final tagsAsync = ref.watch(tagsProvider);

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.7,
              ),
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
                        Text(
                          'Add Tags',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: ctx.textPrimary,
                            fontFamily: 'ProductSans',
                          ),
                        ),
                        Text(
                          '${selectedFiles.length} file(s) selected',
                          style: TextStyle(
                            fontSize: 13,
                            color: ctx.textSecondary,
                            fontFamily: 'ProductSans',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: tagController,
                          decoration: InputDecoration(
                            hintText: 'Create new tag',
                            hintStyle: TextStyle(
                              fontFamily: 'ProductSans',
                              color: ctx.textTertiary,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: ctx.accentColor),
                            ),
                            prefixIcon: Icon(Icons.label_outline, color: ctx.textSecondary),
                            suffixIcon: IconButton(
                              icon: Icon(Icons.add, color: ctx.accentColor),
                              onPressed: () async {
                                final tag = tagController.text.trim();
                                if (tag.isEmpty) return;

                                final vaultService = ref.read(vaultServiceProvider);
                                await vaultService.createTag(tag);

                                for (final fileId in selectedFiles) {
                                  await ref.read(vaultNotifierProvider.notifier).addTag(fileId, tag);
                                }

                                if (!ctx.mounted) return;
                                Navigator.pop(ctx);
                                ref.invalidate(tagsProvider);
                                ToastUtils.showSuccess('Tag added');
                                _exitSelectionMode();
                                _invalidateExplorerProviders();
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Existing Tags',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: ctx.textTertiary,
                            fontFamily: 'ProductSans',
                          ),
                        ),
                        const SizedBox(height: 8),
                        tagsAsync.when(
                          loading: () => const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ),
                          error: (_, __) => Text(
                            'Failed to load tags',
                            style: TextStyle(
                              fontFamily: 'ProductSans',
                              color: ctx.textSecondary,
                            ),
                          ),
                          data: (tags) {
                            if (tags.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: Text(
                                    'No tags yet. Create one above!',
                                    style: TextStyle(
                                      fontFamily: 'ProductSans',
                                      color: ctx.textTertiary,
                                    ),
                                  ),
                                ),
                              );
                            }
                            return Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: tags
                                  .map((tag) => ActionChip(
                                        avatar: Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            color: Color(tag.colorValue),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        label: Text(
                                          tag.name,
                                          style: const TextStyle(
                                            fontFamily: 'ProductSans',
                                            fontSize: 12,
                                          ),
                                        ),
                                        onPressed: () async {
                                          for (final fileId in selectedFiles) {
                                            await ref.read(vaultNotifierProvider.notifier).addTag(fileId, tag.name);
                                          }

                                          if (!ctx.mounted) return;
                                          Navigator.pop(ctx);
                                          ref.invalidate(tagsProvider);
                                          ToastUtils.showSuccess('Tag added');
                                          _exitSelectionMode();
                                          _invalidateExplorerProviders();
                                        },
                                      ))
                                  .toList(),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Quick Tags',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: ctx.textTertiary,
                            fontFamily: 'ProductSans',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: predefinedTags
                              .map((tag) => ActionChip(
                                    label: Text(
                                      tag,
                                      style: const TextStyle(
                                        fontFamily: 'ProductSans',
                                        fontSize: 12,
                                      ),
                                    ),
                                    onPressed: () async {
                                      final vaultService = ref.read(vaultServiceProvider);
                                      await vaultService.createTag(tag);

                                      for (final fileId in selectedFiles) {
                                        await ref.read(vaultNotifierProvider.notifier).addTag(fileId, tag);
                                      }

                                      if (!ctx.mounted) return;
                                      Navigator.pop(ctx);
                                      ref.invalidate(tagsProvider);
                                      ToastUtils.showSuccess('Tag added');
                                      _exitSelectionMode();
                                      _invalidateExplorerProviders();
                                    },
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: MediaQuery.of(ctx).padding.bottom),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _unhideSelectedFiles(Set<String> selectedFiles) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
        title: Text(
          'Unhide Files',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: ctx.textPrimary,
          ),
        ),
        content: Text(
          'Are you sure you want to unhide ${selectedFiles.length} file(s)? This will restore them to your device gallery (DCIM/Restored folder) and remove them from the vault.',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: ctx.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: ctx.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Unhide',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: ctx.accentColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final progressState = ValueNotifier<OperationProgressState>(
      OperationProgressState(
        totalFiles: selectedFiles.length,
        currentFile: 0,
        currentFileName: 'Preparing...',
        totalSizeBytes: 0,
        processedSizeBytes: 0,
        statusMessage: 'Starting...',
        isProcessing: true,
      ),
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => ValueListenableBuilder<OperationProgressState>(
        valueListenable: progressState,
        builder: (ctx, state, _) => OperationProgressSheet(
          operationType: OperationType.unhide,
          totalFiles: state.totalFiles,
          currentFile: state.currentFile,
          currentFileName: state.currentFileName,
          totalSizeBytes: state.totalSizeBytes,
          processedSizeBytes: state.processedSizeBytes,
          statusMessage: state.statusMessage,
          isProcessing: state.isProcessing,
          isComplete: state.isComplete,
          isEncrypting: state.isEncrypting,
        ),
      ),
    );

    final result = await FileImportService.instance.unhideFiles(
      fileIds: selectedFiles.toList(),
      removeFromVault: true,
      onProgress: (current, total, {int? currentSize, int? totalSize}) {
        progressState.value = progressState.value.copyWith(
          totalFiles: total,
          currentFile: current,
          totalSizeBytes: totalSize ?? 0,
          processedSizeBytes: currentSize ?? 0,
          statusMessage: current == 0
              ? 'Preparing files...'
              : 'Processing file $current of $total...',
        );
      },
    );

    if (!mounted) return;

    _exitSelectionMode();

    if (result.success && result.unhiddenCount > 0) {
      ToastUtils.showSuccess(result.message ?? 'Files restored to gallery');
      ref.read(vaultNotifierProvider.notifier).loadFiles();
    } else if (!result.success) {
      ToastUtils.showError(result.error ?? 'Failed to unhide files');
    }

    Navigator.pop(context); // Close progress sheet
    _invalidateExplorerProviders();
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
