import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/album.dart';
import '../models/smart_collection.dart';
import '../models/vaulted_file.dart';
import '../providers/note_providers.dart';
import '../providers/password_providers.dart';
import '../providers/smart_collection_providers.dart';
import '../providers/vault_providers.dart';
import '../services/file_open_service.dart';
import '../themes/app_colors.dart';
import '../utils/responsive_utils.dart';
import '../utils/toast_utils.dart';
import '../widgets/encrypted_thumbnail.dart';
import '../widgets/vault_filter_sheet.dart';
import 'note_editor_screen.dart';
import 'password_editor_screen.dart';
import 'smart_collections_screen.dart';

/// Live grid of the files matching one smart collection.
class SmartCollectionScreen extends ConsumerStatefulWidget {
  final String collectionId;

  const SmartCollectionScreen({super.key, required this.collectionId});

  @override
  ConsumerState<SmartCollectionScreen> createState() =>
      _SmartCollectionScreenState();
}

class _SmartCollectionScreenState extends ConsumerState<SmartCollectionScreen>
    with WidgetsBindingObserver {
  bool _isSelectionMode = false;
  final Set<String> _selectedFiles = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Recompute relative date windows against the current day.
      ref.invalidate(smartCollectionResultsProvider(widget.collectionId));
      ref.invalidate(smartCollectionCountsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final collectionsAsync = ref.watch(smartCollectionsProvider);
    final collection = collectionsAsync.value
        ?.where((c) => c.id == widget.collectionId)
        .firstOrNull;
    final resultsAsync =
        ref.watch(smartCollectionResultsProvider(widget.collectionId));

    if (collection == null && !collectionsAsync.isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          foregroundColor: context.textPrimary,
          elevation: 0,
        ),
        body: Center(
          child: Text(
            'Collection not found',
            style: TextStyle(
              fontFamily: 'ProductSans',
              color: context.textSecondary,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(collection, resultsAsync),
      body: resultsAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(context.accentColor),
          ),
        ),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline,
                  size: 64, color: AppColors.lightTextTertiary),
              const SizedBox(height: 16),
              Text(
                'Failed to load files',
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  color: context.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref
                    .invalidate(smartCollectionResultsProvider(widget.collectionId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (files) {
          if (files.isEmpty) return _buildEmptyState(collection);
          return _buildFilesGrid(files);
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    SmartCollection? collection,
    AsyncValue<List<VaultedFile>> resultsAsync,
  ) {
    final fileCount = resultsAsync.value?.length ?? 0;
    final name = collection?.name ?? 'Collection';

    if (_isSelectionMode) {
      final files = resultsAsync.value ?? const [];
      final allSelected =
          files.isNotEmpty && files.every((f) => _selectedFiles.contains(f.id));

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
            icon: const Icon(Icons.favorite_border, color: Colors.white),
            onPressed: _toggleFavoriteSelected,
            tooltip: 'Toggle favorite',
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
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: TextStyle(
              fontFamily: 'ProductSans',
              color: context.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            '$fileCount ${fileCount == 1 ? 'item' : 'items'}',
            style: TextStyle(
              fontFamily: 'ProductSans',
              fontSize: 12,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      elevation: 0,
      iconTheme: IconThemeData(color: context.textPrimary),
      actions: [
        IconButton(
          icon: Icon(Icons.sort, color: context.textPrimary),
          tooltip: 'Sort',
          onPressed: collection == null
              ? null
              : () => _showSortOptions(collection),
        ),
        if (collection != null)
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: context.textPrimary),
            onSelected: (value) => _handleMenuAction(value, collection),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit Filter')),
              if (collection.id == 'preset_large_videos')
                const PopupMenuItem(
                    value: 'threshold', child: Text('Adjust Size Threshold')),
              if (collection.isCustom)
                const PopupMenuItem(value: 'rename', child: Text('Rename')),
              if (collection.isCustom)
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
      ],
    );
  }

  Widget _buildFilesGrid(List<VaultedFile> files) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(smartCollectionResultsProvider(widget.collectionId));
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
          if (!_isSelectionMode && file.isFavorite)
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
          if (file.isDocument || file.isSong)
            Positioned(
              bottom: 8,
              left: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  file.originalName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontFamily: 'ProductSans',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFileThumbnail(VaultedFile file) {
    if (!file.isEncrypted &&
        (ref.watch(vaultSettingsProvider).value?.hideUnencryptedThumbnails ??
            false)) {
      return _buildPlaceholder(file);
    }
    if (file.isImage) {
      if (file.isEncrypted) {
        return EncryptedThumbnail(file: file);
      }
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

    if (file.isVideo) {
      if (file.isEncrypted) {
        return Stack(
          fit: StackFit.expand,
          children: [
            EncryptedThumbnail(file: file),
            Container(
              color: Colors.black26,
              child: const Center(
                child: Icon(Icons.play_circle_outline,
                    size: 48, color: Colors.white70),
              ),
            ),
          ],
        );
      }
      return Container(
        color: Colors.black87,
        child: const Center(
          child: Icon(
            Icons.play_circle_outline,
            size: 48,
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
        color = Colors.orange;
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
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              file.originalName,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: color,
                fontFamily: 'ProductSans',
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(SmartCollection? collection) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: context.accentColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.auto_awesome_outlined,
              size: 64,
              color: context.accentColor,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No matching files',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
              fontFamily: 'ProductSans',
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              'Files show up here as soon as they match "${collection?.name ?? 'this collection'}".',
              style: TextStyle(
                fontSize: 14,
                color: context.textSecondary,
                fontFamily: 'ProductSans',
              ),
              textAlign: TextAlign.center,
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
    final files = ref.read(smartCollectionResultsProvider(widget.collectionId)).value ?? [];
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
    final filesAsync =
        ref.read(smartCollectionResultsProvider(widget.collectionId));
    FileOpenService.open(
      context,
      ref,
      file,
      currentFiles: filesAsync.value ?? [],
      onUnsupported: () {
        ToastUtils.showInfo('No preview available for this file type');
      },
      onOpenNote: (noteId) => _openNoteFromVault(noteId),
      onOpenPassword: (passwordId) => _openPasswordFromVault(passwordId),
    );
  }

  Future<void> _openNoteFromVault(String noteId) async {
    var notesAsync = ref.read(notesNotifierProvider);
    if (notesAsync.isLoading) {
      await ref.read(notesNotifierProvider.notifier).loadNotes();
      notesAsync = ref.read(notesNotifierProvider);
    }
    if (!mounted) return;
    final note = notesAsync.value?.where((n) => n.id == noteId).firstOrNull;
    if (note != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NoteEditorScreen(note: note),
        ),
      );
    }
  }

  Future<void> _openPasswordFromVault(String passwordId) async {
    var passwordsAsync = ref.read(passwordsNotifierProvider);
    if (passwordsAsync.isLoading) {
      await ref.read(passwordsNotifierProvider.notifier).loadPasswords();
      passwordsAsync = ref.read(passwordsNotifierProvider);
    }
    if (!mounted) return;
    final entry =
        passwordsAsync.value?.where((p) => p.id == passwordId).firstOrNull;
    if (entry != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PasswordEditorScreen(entry: entry),
        ),
      );
    }
  }

  Future<void> _toggleFavoriteSelected() async {
    final selectedList = _selectedFiles.toList();
    for (final fileId in selectedList) {
      await ref.read(vaultNotifierProvider.notifier).toggleFavorite(fileId);
    }
    ToastUtils.showSuccess('Updated favorites');
    _exitSelectionMode();
  }

  Future<void> _deleteSelectedFiles() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(dialogContext).scaffoldBackgroundColor,
        title: Text(
          'Delete Files',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: dialogContext.textPrimary,
          ),
        ),
        content: Text(
          'Are you sure you want to delete ${_selectedFiles.length} file(s)? This action cannot be undone.',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: dialogContext.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: dialogContext.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
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

    if (confirmed != true) return;
    final selectedList = _selectedFiles.toList();
    final result =
        await ref.read(vaultNotifierProvider.notifier).deleteFiles(selectedList);
    if (!mounted) return;

    _exitSelectionMode();

    if (result.allSucceeded) {
      ToastUtils.showSuccess('Files deleted');
    } else if (result.anyRemoved) {
      ToastUtils.showError(
          'Deleted ${result.removedCount}; ${result.failedCount} could not be deleted');
    } else {
      ToastUtils.showError('Failed to delete some files');
    }
  }

  Future<void> _showSortOptions(SmartCollection collection) async {
    final currentSort = collection.sortOption;
    final selected = await showModalBottomSheet<SortOption>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Container(
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
                    ...SortOption.values.map(
                      (option) => ListTile(
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
                        onTap: () => Navigator.pop(sheetContext, option),
                        contentPadding: EdgeInsets.zero,
                      ),
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

    if (selected == null || !mounted) return;
    final ok = await ref
        .read(smartCollectionsProvider.notifier)
        .updateCollection(collection.copyWith(sortOption: selected));
    if (!mounted) return;
    if (!ok) ToastUtils.showError('Could not save sort order');
  }

  Future<void> _handleMenuAction(
    String value,
    SmartCollection collection,
  ) async {
    switch (value) {
      case 'edit':
        final result = await VaultFilterSheet.show(
          context,
          initialFilter: collection.filter,
          title: 'Edit "${collection.name}"',
          applyLabel: 'Save Filter',
        );
        if (result == null || !mounted) return;
        final ok = await ref
            .read(smartCollectionsProvider.notifier)
            .updateCollection(collection.copyWith(filter: result.filter));
        if (!mounted) return;
        if (ok) {
          ToastUtils.showSuccess('Filter updated');
        } else {
          ToastUtils.showError('Could not update filter');
        }
      case 'threshold':
        await _editThreshold(collection);
      case 'rename':
        final name = await showSmartCollectionNameDialog(
          context,
          title: 'Rename Collection',
          initialName: collection.name,
          actionLabel: 'Rename',
        );
        if (name == null || !mounted) return;
        final ok = await ref
            .read(smartCollectionsProvider.notifier)
            .updateCollection(collection.copyWith(name: name));
        if (!mounted) return;
        if (ok) {
          ToastUtils.showSuccess('Renamed to "$name"');
        } else {
          ToastUtils.showError('Could not rename collection');
        }
      case 'delete':
        await _confirmDelete(collection);
    }
  }

  Future<void> _editThreshold(SmartCollection collection) async {
    final currentMb =
        (collection.filter.minSizeBytes ?? 100 * 1024 * 1024) ~/ (1024 * 1024);
    final controller = TextEditingController(text: currentMb.toString());
    final mb = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(dialogContext).scaffoldBackgroundColor,
        title: Text(
          'Large Video Threshold',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: dialogContext.textPrimary,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            suffixText: 'MB',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: dialogContext.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              if (value != null && value > 0) {
                Navigator.pop(dialogContext, value);
              }
            },
            child: Text(
              'Save',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: dialogContext.accentColor,
              ),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    if (mb == null || !mounted) return;
    final ok = await ref
        .read(smartCollectionsProvider.notifier)
        .updateCollection(
          collection.copyWith(
            filter: collection.filter.copyWith(minSizeBytes: mb * 1024 * 1024),
          ),
        );
    if (!mounted) return;
    if (ok) {
      ToastUtils.showSuccess('Threshold set to $mb MB');
    } else {
      ToastUtils.showError('Could not update threshold');
    }
  }

  Future<void> _confirmDelete(SmartCollection collection) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(dialogContext).scaffoldBackgroundColor,
        title: Text(
          'Delete Collection',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: dialogContext.textPrimary,
          ),
        ),
        content: Text(
          'Delete "${collection.name}"? Files stay in the vault.',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: dialogContext.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: dialogContext.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
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
    final ok = await ref
        .read(smartCollectionsProvider.notifier)
        .deleteCollection(collection.id);
    if (!mounted) return;
    if (ok) {
      ToastUtils.showSuccess('Collection deleted');
      Navigator.pop(context);
    } else {
      ToastUtils.showError('Could not delete collection');
    }
  }
}
