import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../models/vaulted_file.dart';
import '../models/album.dart';
import '../providers/vault_providers.dart';
import '../services/auto_kill_service.dart';
import '../services/file_import_service.dart';
import '../themes/app_colors.dart';
import '../utils/toast_utils.dart';
import '../utils/responsive_utils.dart';
import '../widgets/office_conversion_confirm_dialog.dart';
import 'albums_screen.dart';
import 'favorites_screen.dart';
import 'tags_screen.dart';
import 'media_viewer_screen.dart';
import 'document_viewer_screen.dart';
import 'song_player_screen.dart';
import '../widgets/permission_warning_banner.dart';
import 'media_picker_screen.dart';
import 'document_picker_screen.dart';
import 'package:photo_manager/photo_manager.dart' hide AlbumType;
import 'camera_screen.dart';
import 'vault_settings_screen.dart';
import '../widgets/operation_progress_sheet.dart';

/// Gallery vault screen - main screen after authentication
class GalleryVaultScreen extends ConsumerStatefulWidget {
  const GalleryVaultScreen({super.key});

  @override
  ConsumerState<GalleryVaultScreen> createState() => _GalleryVaultScreenState();
}

class _GalleryVaultScreenState extends ConsumerState<GalleryVaultScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FileImportService _importService = FileImportService.instance;
  final Map<String, GlobalKey> _selectionTileKeys = {};

  bool _isImporting = false;
  int _importProgress = 0;
  int _importTotal = 0;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  bool _isSlidingSelection = false;
  bool? _slidingSelectionValue;
  String? _slidingTabKey;
  final Set<String> _slidingTouchedTileKeys = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _initializeVault();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeVault() async {
    await ref.read(vaultServiceProvider).initialize();
    ref.read(isDecoyModeProvider.notifier).state =
        ref.read(decoyServiceProvider).isDecoyModeActive;
    ref.read(vaultNotifierProvider.notifier).loadFiles();
  }

  @override
  Widget build(BuildContext context) {
    final filesAsync = ref.watch(vaultNotifierProvider);
    final isSelectionMode = ref.watch(isSelectionModeProvider);
    final selectedFiles = ref.watch(selectedFilesProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(isSelectionMode, selectedFiles),
      body: Column(
        children: [
          // Permission warning banner for All Files Access
          const PermissionWarningBanner(),
          if (_isImporting) _buildImportProgress(),
          if (_isSearching) _buildSearchBar(),
          _buildTabBar(filesAsync),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildFileGrid(null, filesAsync),
                _buildFileGrid(VaultedFileType.image, filesAsync),
                _buildFileGrid(VaultedFileType.video, filesAsync),
                _buildFileGrid(VaultedFileType.song, filesAsync),
                _buildFileGrid(VaultedFileType.document, filesAsync),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: isSelectionMode ? null : _buildFAB(),
      drawer: _buildDrawer(),
    );
  }

  PreferredSizeWidget _buildAppBar(
      bool isSelectionMode, Set<String> selectedFiles) {
    if (isSelectionMode) {
      return AppBar(
        backgroundColor: context.accentColor,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: _exitSelectionMode,
        ),
        title: Text(
          '${selectedFiles.length} selected',
          style: const TextStyle(
            fontFamily: 'ProductSans',
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.visibility_outlined, color: Colors.white),
            onPressed: () => _unhideSelectedFiles(selectedFiles),
            tooltip: 'Unhide (restore to gallery)',
          ),
          IconButton(
            icon: const Icon(Icons.folder_outlined, color: Colors.white),
            onPressed: () => _showAddToAlbumSheet(selectedFiles),
            tooltip: 'Add to album',
          ),
          IconButton(
            icon: const Icon(Icons.favorite_outline, color: Colors.white),
            onPressed: () => _toggleFavoriteSelected(selectedFiles),
            tooltip: 'Toggle favorite',
          ),
          IconButton(
            icon: const Icon(Icons.label_outline, color: Colors.white),
            onPressed: () => _showAddTagsSheet(selectedFiles),
            tooltip: 'Add tags',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white),
            onPressed: () => _deleteSelectedFiles(selectedFiles),
          ),
        ],
      );
    }

    return AppBar(
      title: Text(
        'Gallery Vault',
        style: TextStyle(
          fontFamily: 'ProductSans',
          color: context.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      elevation: 0,
      actions: [
        IconButton(
          icon: Icon(
            _isSearching ? Icons.close : Icons.search,
            color: context.textPrimary,
          ),
          onPressed: () {
            setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) {
                _searchController.clear();
                ref.read(searchQueryProvider.notifier).state = '';
              }
            });
          },
        ),
        IconButton(
          icon: Icon(Icons.sort, color: context.textPrimary),
          onPressed: _showSortOptions,
        ),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: context.textPrimary),
          onSelected: (value) {
            switch (value) {
              case 'albums':
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AlbumsScreen()),
                );
                break;
              case 'settings':
                _openSettingsScreen();
                break;
              case 'refresh':
                ref.read(vaultNotifierProvider.notifier).refresh();
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'albums',
              child: Row(
                children: [
                  Icon(Icons.folder_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('Albums'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'settings',
              child: Row(
                children: [
                  Icon(Icons.settings_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('Settings'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'refresh',
              child: Row(
                children: [
                  Icon(Icons.refresh, size: 20),
                  SizedBox(width: 12),
                  Text('Refresh'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: context.backgroundSecondary,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search files...',
          hintStyle: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textTertiary,
          ),
          prefixIcon: Icon(Icons.search, color: context.textTertiary, size: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: AppColors.lightBackground,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        style: TextStyle(
          fontFamily: 'ProductSans',
          color: context.textPrimary,
        ),
        onChanged: (value) {
          ref.read(searchQueryProvider.notifier).state = value;
        },
      ),
    );
  }

  Widget _buildImportProgress() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: context.accentColor.withValues(alpha: 0.1),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(context.accentColor),
              value: _importTotal > 0
                  ? (_importProgress / _importTotal).clamp(0.0, 1.0)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _importTotal > 0
                  ? 'Importing... ${_importProgress.clamp(0, _importTotal)} / $_importTotal'
                  : 'Importing...',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: context.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(AsyncValue<List<VaultedFile>> filesAsync) {
    final files = filesAsync.value ?? [];

    return Container(
      decoration: BoxDecoration(
        color: context.backgroundColor,
        border: Border(
          bottom: BorderSide(color: AppColors.lightDivider, width: 1),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: context.accentColor,
        unselectedLabelColor: AppColors.lightTextTertiary,
        indicatorColor: context.accentColor,
        indicatorWeight: 3,
        isScrollable: true,
        labelStyle: const TextStyle(
          fontFamily: 'ProductSans',
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: 'ProductSans',
          fontWeight: FontWeight.normal,
          fontSize: 14,
        ),
        tabs: [
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.grid_view_rounded, size: 18),
                const SizedBox(width: 6),
                Text('All (${files.length})'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.image_outlined, size: 18),
                const SizedBox(width: 6),
                Text(
                    'Images (${files.where((f) => f.type == VaultedFileType.image).length})'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_outlined, size: 18),
                const SizedBox(width: 6),
                Text(
                    'Videos (${files.where((f) => f.type == VaultedFileType.video).length})'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.music_note_outlined, size: 18),
                const SizedBox(width: 6),
                Text(
                    'Songs (${files.where((f) => f.type == VaultedFileType.song).length})'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.description_outlined, size: 18),
                const SizedBox(width: 6),
                Text(
                    'Docs (${files.where((f) => f.type == VaultedFileType.document || f.type == VaultedFileType.other).length})'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileGrid(
      VaultedFileType? filterType, AsyncValue<List<VaultedFile>> filesAsync) {
    final tabKey = _tabKeyFor(filterType);

    return filesAsync.when(
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
              onPressed: () =>
                  ref.read(vaultNotifierProvider.notifier).loadFiles(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (allFiles) {
        // Filter by type
        List<VaultedFile> files;
        if (filterType == null) {
          files = allFiles;
        } else if (filterType == VaultedFileType.document) {
          files = allFiles
              .where((f) =>
                  f.type == VaultedFileType.document ||
                  f.type == VaultedFileType.other)
              .toList();
        } else {
          files = allFiles.where((f) => f.type == filterType).toList();
        }

        // Apply search filter
        final searchQuery = ref.watch(searchQueryProvider);
        if (searchQuery.isNotEmpty) {
          files = files
              .where((f) => f.originalName
                  .toLowerCase()
                  .contains(searchQuery.toLowerCase()))
              .toList();
        }

        // Apply sorting
        final sortOption = ref.watch(sortOptionProvider);
        files = ref.read(vaultServiceProvider).sortFiles(files, sortOption);

        if (files.isEmpty) {
          return _buildEmptyState(filterType);
        }

        return RefreshIndicator(
          onRefresh: () async {
            await ref.read(vaultNotifierProvider.notifier).refresh();
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
            // Performance optimizations
            addAutomaticKeepAlives:
                false, // Reduces memory overhead for off-screen items
            addRepaintBoundaries:
                true, // Isolates paint operations for each item
            itemCount: files.length,
            itemBuilder: (context, index) => RepaintBoundary(
              key: ValueKey(files[index].id),
              child: _buildFileItem(files[index], tabKey),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFileItem(VaultedFile file, String tabKey) {
    final selectedFiles = ref.watch(selectedFilesProvider);
    final isSelectionMode = ref.watch(isSelectionModeProvider);
    final isSelected = selectedFiles.contains(file.id);
    final tileKey = _selectionTileKey(tabKey, file.id);

    return GestureDetector(
      onTap: () {
        if (isSelectionMode) {
          _toggleSelection(file.id);
        } else {
          _openFile(file);
        }
      },
      onLongPressStart: (_) => _startSlidingSelection(file.id, tabKey),
      onLongPressMoveUpdate: (details) =>
          _updateSlidingSelection(details.globalPosition),
      onLongPressEnd: (_) => _stopSlidingSelection(),
      onLongPressCancel: _stopSlidingSelection,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            key: _tileKeyFor(tileKey),
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
          if (isSelectionMode)
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
                    : const SizedBox.shrink(),
              ),
            ),
          // Favorite indicator
          if (file.isFavorite && !isSelectionMode)
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
          // Encrypted indicator
          if (file.isEncrypted && !isSelectionMode)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(
                  Icons.lock,
                  size: 14,
                  color: Colors.green,
                ),
              ),
            ),
          // Tags indicator
          if (file.hasTags && !isSelectionMode)
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.label, size: 12, color: Colors.white),
                    const SizedBox(width: 2),
                    Text(
                      '${file.tagCount}',
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
          // Video duration indicator
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
          // File type badge for non-visual files
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

  String _tabKeyFor(VaultedFileType? filterType) {
    if (filterType == null) return 'all';

    switch (filterType) {
      case VaultedFileType.image:
        return 'images';
      case VaultedFileType.video:
        return 'videos';
      case VaultedFileType.song:
        return 'songs';
      case VaultedFileType.document:
        return 'documents';
      case VaultedFileType.other:
        return 'other';
    }
  }

  String _selectionTileKey(String tabKey, String fileId) => '$tabKey::$fileId';

  GlobalKey _tileKeyFor(String tileKey) {
    return _selectionTileKeys.putIfAbsent(tileKey, GlobalKey.new);
  }

  void _startSlidingSelection(String fileId, String tabKey) {
    final selectedFiles = ref.read(selectedFilesProvider);
    final shouldSelect = !selectedFiles.contains(fileId);
    final tileKey = _selectionTileKey(tabKey, fileId);

    setState(() {
      _isSlidingSelection = true;
      _slidingSelectionValue = shouldSelect;
      _slidingTabKey = tabKey;
      _slidingTouchedTileKeys
        ..clear()
        ..add(tileKey);
    });

    _setSelection(fileId, shouldSelect, keepSelectionMode: true);
  }

  void _updateSlidingSelection(Offset globalPosition) {
    if (!_isSlidingSelection || _slidingSelectionValue == null) return;

    final tileKey = _tileKeyAt(globalPosition, _slidingTabKey);
    if (tileKey == null || _slidingTouchedTileKeys.contains(tileKey)) return;

    final separatorIndex = tileKey.indexOf('::');
    if (separatorIndex == -1) return;

    final fileId = tileKey.substring(separatorIndex + 2);

    setState(() {
      _slidingTouchedTileKeys.add(tileKey);
    });

    _setSelection(fileId, _slidingSelectionValue!, keepSelectionMode: true);
  }

  void _stopSlidingSelection() {
    if (!_isSlidingSelection) return;

    setState(() {
      _isSlidingSelection = false;
      _slidingSelectionValue = null;
      _slidingTabKey = null;
      _slidingTouchedTileKeys.clear();
    });

    final selectedFiles = ref.read(selectedFilesProvider);
    if (selectedFiles.isEmpty) {
      ref.read(isSelectionModeProvider.notifier).state = false;
    }
  }

  String? _tileKeyAt(Offset globalPosition, String? tabKey) {
    if (tabKey == null) return null;

    for (final entry in _selectionTileKeys.entries) {
      if (!entry.key.startsWith('$tabKey::')) continue;

      final context = entry.value.currentContext;
      if (context == null) continue;

      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) continue;

      final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
      if (rect.contains(globalPosition)) {
        return entry.key;
      }
    }

    return null;
  }

  Widget _buildFileThumbnail(VaultedFile file) {
    // Show image thumbnail
    if (file.isImage) {
      final imageFile = File(file.vaultPath);

      // Use FutureBuilder to check file existence first
      return FutureBuilder<bool>(
        future: imageFile.exists(),
        builder: (context, snapshot) {
          if (snapshot.data != true) {
            return _buildPlaceholder(file);
          }

          // Use Image.file with defensive error handling
          return Image.file(
            imageFile,
            fit: BoxFit.cover,
            cacheWidth: 300, // Limit resolution for performance
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded || frame != null) {
                return child;
              }
              // Show placeholder while loading
              return const _ImageLoadingPlaceholder();
            },
            errorBuilder: (context, error, stackTrace) {
              // Log error for debugging but show placeholder gracefully
              debugPrint('Error loading image: ${file.originalName} - $error');
              return _buildPlaceholder(file);
            },
          );
        },
      );
    }

    // Show video thumbnail (first frame preview)
    if (file.isVideo) {
      // Try to show video thumbnail from the vault path
      // Videos don't have a simple thumbnail, so we use a styled placeholder
      return Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: Colors.black87,
            child: const Center(
              child: Icon(
                Icons.play_circle_outline,
                size: 48,
                color: Colors.white70,
              ),
            ),
          ),
        ],
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
        icon = _getDocumentIcon(file.extension);
        color = _getDocumentColor(file.extension);
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

  IconData _getDocumentIcon(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'txt':
        return Icons.text_snippet;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getDocumentColor(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return Colors.red;
      case 'doc':
      case 'docx':
        return context.accentColor;
      case 'xls':
      case 'xlsx':
        return Colors.green;
      case 'ppt':
      case 'pptx':
        return Colors.orange;
      case 'txt':
        return Colors.grey;
      default:
        return context.accentColor;
    }
  }

  void _toggleSelection(String fileId) {
    final selectedFiles = ref.read(selectedFilesProvider);
    _setSelection(fileId, !selectedFiles.contains(fileId));
  }

  void _setSelection(String fileId, bool isSelected,
      {bool keepSelectionMode = false}) {
    final selectedFiles = Set<String>.from(ref.read(selectedFilesProvider));

    if (isSelected) {
      selectedFiles.add(fileId);
    } else {
      selectedFiles.remove(fileId);
    }

    ref.read(selectedFilesProvider.notifier).state = selectedFiles;
    ref.read(isSelectionModeProvider.notifier).state =
        keepSelectionMode || selectedFiles.isNotEmpty;
  }

  void _exitSelectionMode() {
    ref.read(isSelectionModeProvider.notifier).state = false;
    ref.read(selectedFilesProvider.notifier).state = {};
  }

  void _openFile(VaultedFile file) {
    // Get the current list of files for navigation in viewer
    final filesAsync = ref.read(vaultNotifierProvider);
    final allFiles = filesAsync.value ?? [];

    // Filter files based on type for viewer navigation
    List<VaultedFile> viewerFiles;
    int initialIndex;

    if (file.isImage || file.isVideo) {
      // For media files, include both images and videos
      viewerFiles = allFiles.where((f) => f.isImage || f.isVideo).toList();
      initialIndex = viewerFiles.indexWhere((f) => f.id == file.id);
      if (initialIndex == -1) initialIndex = 0;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MediaViewerScreen(
            initialFile: file,
            files: viewerFiles,
            initialIndex: initialIndex,
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
      // For documents, open document viewer
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DocumentViewerScreen(file: file),
        ),
      );
    } else {
      // For other files, show export options
      _showFileOptionsSheet(file);
    }
  }

  /// Show options for files that don't have a preview
  void _showFileOptionsSheet(VaultedFile file) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: context.backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // File info header
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
                          color: _getFileColor(file.extension),
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
                                color: context.textPrimary,
                                fontFamily: 'ProductSans',
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${file.extension.toUpperCase()} • ${file.formattedSize}',
                              style: TextStyle(
                                fontSize: 13,
                                color: context.textSecondary,
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
                      color: context.textSecondary,
                      fontFamily: 'ProductSans',
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Export to Downloads
                  ListTile(
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: context.accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.download_outlined,
                        color: context.accentColor,
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
                        color: context.textSecondary,
                      ),
                    ),
                    contentPadding: EdgeInsets.zero,
                    onTap: () {
                      Navigator.pop(context);
                      _exportFileToDownloads(file);
                    },
                  ),
                  const Divider(height: 1),
                  // Open with external app
                  ListTile(
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: context.accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.open_in_new,
                        color: context.accentColor,
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
                        color: context.textSecondary,
                      ),
                    ),
                    contentPadding: EdgeInsets.zero,
                    onTap: () {
                      Navigator.pop(context);
                      _openWithExternalApp(file);
                    },
                  ),
                  const Divider(height: 1),
                  // File info
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
                        color: context.textSecondary,
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
                        color: context.textSecondary,
                      ),
                    ),
                    contentPadding: EdgeInsets.zero,
                    onTap: () {
                      Navigator.pop(context);
                      _showFileInfo(file);
                    },
                  ),
                ],
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  /// Export a file to Downloads folder
  Future<void> _exportFileToDownloads(VaultedFile file) async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          content: Row(
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(context.accentColor),
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

      // Get the Downloads directory
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

      // Export the file using vault service
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

  /// Open file with an external application
  Future<void> _openWithExternalApp(VaultedFile file) async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          content: Row(
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(context.accentColor),
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

      // Get the decrypted file
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

  /// Show file info dialog
  void _showFileInfo(VaultedFile file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          'File Info',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Name', file.originalName),
            const SizedBox(height: 12),
            _buildInfoRow('Type', file.extension.toUpperCase()),
            const SizedBox(height: 12),
            _buildInfoRow('Size', file.formattedSize),
            const SizedBox(height: 12),
            _buildInfoRow('Added', _formatDate(file.dateAdded)),
            const SizedBox(height: 12),
            _buildInfoRow('Encrypted', file.isEncrypted ? 'Yes' : 'No'),
            if (file.lastViewed != null) ...[
              const SizedBox(height: 12),
              _buildInfoRow('Last Viewed', _formatDate(file.lastViewed!)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Close',
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

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'ProductSans',
              color: context.textSecondary,
              fontSize: 14,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontFamily: 'ProductSans',
              color: context.textPrimary,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
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

  Color _getFileColor(String extension) {
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

  Widget _buildEmptyState(VaultedFileType? filterType) {
    String title;
    String subtitle;
    IconData icon;

    if (filterType == null) {
      title = 'No files yet';
      subtitle = 'Your hidden files will appear here';
      icon = Icons.folder_open_outlined;
    } else {
      switch (filterType) {
        case VaultedFileType.image:
          title = 'No images yet';
          subtitle = 'Import images from gallery or camera';
          icon = Icons.image_outlined;
          break;
        case VaultedFileType.video:
          title = 'No videos yet';
          subtitle = 'Import videos from gallery or camera';
          icon = Icons.videocam_outlined;
          break;
        case VaultedFileType.song:
          title = 'No songs yet';
          subtitle = 'Import MP3, WAV, FLAC, and more';
          icon = Icons.music_note_outlined;
          break;
        case VaultedFileType.document:
          title = 'No documents yet';
          subtitle = 'Import PDFs, Word docs, and more';
          icon = Icons.description_outlined;
          break;
        case VaultedFileType.other:
          title = 'No other files yet';
          subtitle = 'Import any files';
          icon = Icons.folder_open_outlined;
          break;
      }
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: context.isDarkMode
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.white.withValues(alpha: 0.15),
                border: Border.all(
                  color: context.isDarkMode
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.white.withValues(alpha: 0.2),
                  width: 1.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Icon(
                    icon,
                    size: 72,
                    color: context.accentColor.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              title,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
                fontFamily: 'ProductSans',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 15,
                color: context.textSecondary,
                fontFamily: 'ProductSans',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [
                    context.accentColor,
                    context.accentColor.withValues(alpha: 0.8),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: context.accentColor.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: _showImportDialog,
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text(
                  'Add Files',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFAB() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            context.accentColor,
            context.accentColor.withValues(alpha: 0.8),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: context.accentColor.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: _showImportDialog,
        backgroundColor: Colors.transparent,
        elevation: 0,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Import',
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontWeight: FontWeight.w600,
            color: Colors.white,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(0),
          bottomRight: Radius.circular(0),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: context.isDarkMode
                  ? Colors.black.withValues(alpha: 0.7)
                  : Colors.white.withValues(alpha: 0.7),
              border: Border(
                right: BorderSide(
                  color: context.isDarkMode
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                _buildDrawerHeader(),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      _buildDrawerItem(
                        icon: Icons.folder_outlined,
                        title: 'Albums',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const AlbumsScreen()),
                          );
                        },
                      ),
                      _buildDrawerItem(
                        icon: Icons.favorite_outline,
                        title: 'Favorites',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const FavoritesScreen()),
                          );
                        },
                      ),
                      _buildDrawerItem(
                        icon: Icons.label_outline,
                        title: 'Tags',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const TagsScreen()),
                          );
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Divider(
                          color: context.isDarkMode
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.black.withValues(alpha: 0.1),
                          thickness: 1,
                        ),
                      ),
                      _buildDrawerItem(
                        icon: Icons.security,
                        title: 'Security Settings',
                        onTap: () {
                          Navigator.pop(context);
                          _openSettingsScreen();
                        },
                      ),
                      _buildDrawerItem(
                        icon: Icons.shield_outlined,
                        title: 'Decoy Mode',
                        subtitle: 'Set up fake vault',
                        onTap: () {
                          Navigator.pop(context);
                          _showDecoyModeSheet();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            context.accentColor,
            context.accentColor.withValues(alpha: 0.8),
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              width: 72,
              height: 72,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: SvgPicture.asset(
                    'assets/locker_logo_nobg.svg',
                    fit: BoxFit.contain,
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Locker',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Consumer(
              builder: (context, ref, _) {
                final storageAsync = ref.watch(formattedStorageProvider);
                final countAsync = ref.watch(fileCountSummaryProvider);

                return Text(
                  '${countAsync.value ?? '...'} • ${storageAsync.value ?? '...'}',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      icon,
                      color: context.accentColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontFamily: 'ProductSans',
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: context.textPrimary,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontFamily: 'ProductSans',
                              fontSize: 12,
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: context.textTertiary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showImportDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _ImportOptionsSheet(
        onImportImages: _importImagesFromGallery,
        onImportVideos: _importVideosFromGallery,
        onImportMedia: _importMediaFromGallery,
        onCapturePhoto: _capturePhoto,
        onRecordVideo: _recordVideo,
        onImportSongs: _importSongs,
        onImportDocuments: _importDocuments,
        onImportAnyFiles: _importAnyFiles,
      ),
    );
  }

  void _showSortOptions() {
    final currentSort = ref.read(sortOptionProvider);

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

  void _showAddToAlbumSheet(Set<String> selectedFiles) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final albumsAsync = ref.watch(albumsNotifierProvider);

          return Container(
            decoration: BoxDecoration(
              color: context.backgroundColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
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
                          'Add to Album',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimary,
                            fontFamily: 'ProductSans',
                          ),
                        ),
                        const SizedBox(height: 16),
                        albumsAsync.when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (_, __) => const Text('Failed to load albums'),
                          data: (albums) => Column(
                            children: albums
                                .where((a) =>
                                    !a.isDefault ||
                                    a.type == AlbumType.favorites)
                                .map((album) => ListTile(
                                      leading: Icon(
                                        Icons.folder_outlined,
                                        color: context.accentColor,
                                      ),
                                      title: Text(
                                        album.name,
                                        style: const TextStyle(
                                          fontFamily: 'ProductSans',
                                        ),
                                      ),
                                      subtitle: Text(
                                        '${album.fileCount} items',
                                        style: TextStyle(
                                          fontFamily: 'ProductSans',
                                          fontSize: 12,
                                          color: context.textTertiary,
                                        ),
                                      ),
                                      onTap: () async {
                                        Navigator.pop(context);
                                        final success = await ref
                                            .read(
                                                vaultNotifierProvider.notifier)
                                            .addToAlbum(
                                              selectedFiles.toList(),
                                              album.id,
                                            );
                                        if (success) {
                                          ToastUtils.showSuccess(
                                              'Added to ${album.name}');
                                          _exitSelectionMode();
                                        } else {
                                          ToastUtils.showError(
                                              'Failed to add to album');
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
                  SizedBox(height: MediaQuery.of(context).padding.bottom),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAddTagsSheet(Set<String> selectedFiles) {
    final tagController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final tagsAsync = ref.watch(tagsProvider);

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              decoration: BoxDecoration(
                color: context.backgroundColor,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
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
                          'Add Tags',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimary,
                            fontFamily: 'ProductSans',
                          ),
                        ),
                        Text(
                          '${selectedFiles.length} file(s) selected',
                          style: TextStyle(
                            fontSize: 13,
                            color: context.textSecondary,
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
                              color: context.textTertiary,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  BorderSide(color: context.accentColor),
                            ),
                            prefixIcon: Icon(Icons.label_outline,
                                color: AppColors.lightTextSecondary),
                            suffixIcon: IconButton(
                              icon: Icon(Icons.add, color: context.accentColor),
                              onPressed: () async {
                                final tag = tagController.text.trim();
                                if (tag.isEmpty) return;

                                // Create tag if it doesn't exist
                                final vaultService =
                                    ref.read(vaultServiceProvider);
                                await vaultService.createTag(tag);

                                for (final fileId in selectedFiles) {
                                  await ref
                                      .read(vaultNotifierProvider.notifier)
                                      .addTag(fileId, tag);
                                }

                                if (!context.mounted) return;
                                Navigator.pop(context);
                                ref.invalidate(tagsProvider);
                                ToastUtils.showSuccess('Tag added');
                                _exitSelectionMode();
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
                            color: context.textTertiary,
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
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ),
                          error: (_, __) => Text(
                            'Failed to load tags',
                            style: TextStyle(
                              fontFamily: 'ProductSans',
                              color: context.textSecondary,
                            ),
                          ),
                          data: (tags) {
                            if (tags.isEmpty) {
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: Text(
                                    'No tags yet. Create one above!',
                                    style: TextStyle(
                                      fontFamily: 'ProductSans',
                                      color: context.textTertiary,
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
                                            await ref
                                                .read(vaultNotifierProvider
                                                    .notifier)
                                                .addTag(fileId, tag.name);
                                          }

                                          if (!context.mounted) return;
                                          Navigator.pop(context);
                                          ref.invalidate(tagsProvider);
                                          ToastUtils.showSuccess('Tag added');
                                          _exitSelectionMode();
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
                            color: context.textTertiary,
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
                                      // Create tag if doesn't exist
                                      final vaultService =
                                          ref.read(vaultServiceProvider);
                                      await vaultService.createTag(tag);

                                      for (final fileId in selectedFiles) {
                                        await ref
                                            .read(
                                                vaultNotifierProvider.notifier)
                                            .addTag(fileId, tag);
                                      }

                                      if (!context.mounted) return;
                                      Navigator.pop(context);
                                      ref.invalidate(tagsProvider);
                                      ToastUtils.showSuccess('Tag added');
                                      _exitSelectionMode();
                                    },
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: MediaQuery.of(context).padding.bottom),
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
  }

  Future<void> _unhideSelectedFiles(Set<String> selectedFiles) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          'Unhide Files',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textPrimary,
          ),
        ),
        content: Text(
          'Are you sure you want to unhide ${selectedFiles.length} file(s)? This will restore them to your device gallery (DCIM/Restored folder) and remove them from the vault.',
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
              'Unhide',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: context.accentColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
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

      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isDismissible: false,
        enableDrag: false,
        builder: (context) => ValueListenableBuilder<OperationProgressState>(
          valueListenable: progressState,
          builder: (context, state, _) => OperationProgressSheet(
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

      final result = await _importService.unhideFiles(
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

      _exitSelectionMode();

      if (!mounted) return;

      if (result.success && result.unhiddenCount > 0) {
        ToastUtils.showSuccess(result.message ?? 'Files restored to gallery');
        ref.read(vaultNotifierProvider.notifier).loadFiles();
      } else if (!result.success) {
        ToastUtils.showError(result.error ?? 'Failed to unhide files');
      }

      Navigator.pop(context); // Close progress sheet
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

    if (confirmed == true) {
      if (!mounted) return;

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
        builder: (context) => ValueListenableBuilder<OperationProgressState>(
          valueListenable: progressState,
          builder: (context, state, _) => OperationProgressSheet(
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
                statusMessage:
                    'Processing file $current of $total...',
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
    }
  }

  void _openSettingsScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const VaultSettingsScreen(),
      ),
    );
  }

  void _showDecoyModeSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final decoySettingsAsync = ref.watch(decoySettingsProvider);

          return Container(
            decoration: BoxDecoration(
              color: context.backgroundColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
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
                          Icon(Icons.shield_outlined,
                              color: context.accentColor),
                          const SizedBox(width: 8),
                          Text(
                            'Decoy Mode',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: context.textPrimary,
                              fontFamily: 'ProductSans',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Set up a fake vault that shows when using a different PIN/password. Perfect for situations where you might be forced to open the app.',
                        style: TextStyle(
                          fontFamily: 'ProductSans',
                          color: context.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 16),
                      decoySettingsAsync.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (_, __) => const Text('Failed to load settings'),
                        data: (settings) => Column(
                          children: [
                            SwitchListTile(
                              title: const Text(
                                'Enable Decoy Mode',
                                style: TextStyle(fontFamily: 'ProductSans'),
                              ),
                              value: settings.isEnabled,
                              onChanged: (value) async {
                                final decoyService =
                                    ref.read(decoyServiceProvider);
                                if (value) {
                                  await decoyService.enableDecoyMode();
                                } else {
                                  await decoyService.disableDecoyMode();
                                }
                                ref.invalidate(decoySettingsProvider);
                              },
                              activeThumbColor: context.accentColor,
                              contentPadding: EdgeInsets.zero,
                            ),
                            if (settings.isEnabled) ...[
                              ListTile(
                                leading: Icon(
                                  settings.hasPinSet
                                      ? Icons.check_circle
                                      : Icons.radio_button_off,
                                  color: settings.hasPinSet
                                      ? Colors.green
                                      : AppColors.lightTextTertiary,
                                ),
                                title: const Text(
                                  'Set Decoy PIN',
                                  style: TextStyle(fontFamily: 'ProductSans'),
                                ),
                                subtitle: Text(
                                  settings.hasPinSet
                                      ? 'Decoy PIN is set'
                                      : 'Not configured',
                                  style: TextStyle(
                                    fontFamily: 'ProductSans',
                                    fontSize: 12,
                                    color: context.textTertiary,
                                  ),
                                ),
                                onTap: () {
                                  Navigator.pop(context);
                                  _showSetDecoyPinDialog();
                                },
                                contentPadding: EdgeInsets.zero,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: MediaQuery.of(context).padding.bottom),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showSetDecoyPinDialog() {
    final pinController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          'Set Decoy PIN',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This PIN will show your decoy vault instead of your real files.',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: context.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Decoy PIN (4-6 digits)',
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
              final pin = pinController.text.trim();
              if (pin.length < 4) {
                ToastUtils.showError('PIN must be at least 4 digits');
                return;
              }

              final success =
                  await ref.read(decoyServiceProvider).setDecoyPin(pin);
              if (!context.mounted) return;
              if (success) {
                Navigator.pop(context);
                ref.invalidate(decoySettingsProvider);
                ToastUtils.showSuccess('Decoy PIN set');
              } else {
                ToastUtils.showError('Failed to set decoy PIN');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: context.accentColor,
              foregroundColor: Colors.white,
            ),
            child: const Text(
              'Set PIN',
              style: TextStyle(fontFamily: 'ProductSans'),
            ),
          ),
        ],
      ),
    );
  }

  // Import methods
  Future<void> _importImagesFromGallery() async {
    Navigator.pop(context);

    // Open custom media picker for images
    final selectedAssets = await Navigator.push<List<AssetEntity>?>(
      context,
      MaterialPageRoute(
        builder: (context) => const MediaPickerScreen(
          requestType: RequestType.image,
          title: 'Select Images to Hide',
        ),
      ),
    );

    if (selectedAssets == null || selectedAssets.isEmpty) {
      ToastUtils.showInfo('No images selected');
      return;
    }

    final progressState = ValueNotifier<OperationProgressState>(
      OperationProgressState(
        totalFiles: selectedAssets.length,
        currentFile: 0,
        currentFileName: 'Preparing...',
        totalSizeBytes: 0,
        processedSizeBytes: 0,
        statusMessage: 'Starting...',
        isProcessing: true,
      ),
    );

    // Show progress sheet
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => ValueListenableBuilder<OperationProgressState>(
        valueListenable: progressState,
        builder: (context, state, _) => OperationProgressSheet(
          operationType: OperationType.hide,
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

    final result = await _importService.importFromAssets(
      assets: selectedAssets,
      deleteOriginals: true, // Hide from gallery
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
      onFileProgress: (fileInfo) {
        progressState.value = progressState.value.copyWith(
          totalFiles: fileInfo.total,
          currentFile: fileInfo.current,
          currentFileName: fileInfo.fileName,
          statusMessage: fileInfo.status,
          isEncrypting: fileInfo.isEncrypting,
          processedSizeBytes:
              fileInfo.isEncrypting ? fileInfo.encryptedBytes : null,
          totalSizeBytes: fileInfo.isEncrypting ? fileInfo.totalBytes : null,
        );
      },
    );

    if (!mounted) return;

    if (result.success && result.importedCount > 0) {
      final msg = result.deletedOriginals
          ? 'Imported and hidden ${result.importedCount} image(s)'
          : 'Imported ${result.importedCount} image(s) (originals may still be visible)';
      ToastUtils.showSuccess(msg);
      ref.read(vaultNotifierProvider.notifier).loadFiles();
    } else if (!result.success) {
      ToastUtils.showError(result.error ?? 'Import failed');
    }

    Navigator.pop(context); // Close progress sheet
  }

  Future<void> _importVideosFromGallery() async {
    Navigator.pop(context);

    // Open custom media picker for videos
    final selectedAssets = await Navigator.push<List<AssetEntity>?>(
      context,
      MaterialPageRoute(
        builder: (context) => const MediaPickerScreen(
          requestType: RequestType.video,
          title: 'Select Videos to Hide',
        ),
      ),
    );

    if (selectedAssets == null || selectedAssets.isEmpty) {
      ToastUtils.showInfo('No videos selected');
      return;
    }

    final progressState = ValueNotifier<OperationProgressState>(
      OperationProgressState(
        totalFiles: selectedAssets.length,
        currentFile: 0,
        currentFileName: 'Preparing...',
        totalSizeBytes: 0,
        processedSizeBytes: 0,
        statusMessage: 'Starting...',
        isProcessing: true,
      ),
    );

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => ValueListenableBuilder<OperationProgressState>(
        valueListenable: progressState,
        builder: (context, state, _) => OperationProgressSheet(
          operationType: OperationType.hide,
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

    final result = await _importService.importFromAssets(
      assets: selectedAssets,
      deleteOriginals: true, // Hide from gallery
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
      onFileProgress: (fileInfo) {
        progressState.value = progressState.value.copyWith(
          totalFiles: fileInfo.total,
          currentFile: fileInfo.current,
          currentFileName: fileInfo.fileName,
          statusMessage: fileInfo.status,
          isEncrypting: fileInfo.isEncrypting,
          processedSizeBytes:
              fileInfo.isEncrypting ? fileInfo.encryptedBytes : null,
          totalSizeBytes: fileInfo.isEncrypting ? fileInfo.totalBytes : null,
        );
      },
    );

    if (!mounted) return;

    if (result.success && result.importedCount > 0) {
      final msg = result.deletedOriginals
          ? 'Imported and hidden ${result.importedCount} video(s)'
          : 'Imported ${result.importedCount} video(s) (originals may still be visible)';
      ToastUtils.showSuccess(msg);
      ref.read(vaultNotifierProvider.notifier).loadFiles();
    } else if (!result.success) {
      ToastUtils.showError(result.error ?? 'Import failed');
    }

    Navigator.pop(context); // Close progress sheet
  }

  Future<void> _importFromDocuments() async {
    Navigator.pop(context);

    // Open document picker directly
    final result = await FileImportService.instance.importFromDocumentFiles(
      filePaths: (<String>[]), // Will be populated by picker
      deleteOriginals: true,
    );

    if (!mounted) return;

    if (result.success && result.importedCount > 0) {
      ToastUtils.showSuccess('Imported ${result.importedCount} document(s)');
      ref.read(vaultNotifierProvider.notifier).loadFiles();
    } else if (!result.success) {
      ToastUtils.showError(result.error ?? 'Import failed');
    }
  }

  Future<void> _importMediaFromGallery() async {
    Navigator.pop(context);

    // Open custom media picker for all media (images and videos)
    final selectedAssets = await Navigator.push<List<AssetEntity>?>(
      context,
      MaterialPageRoute(
        builder: (context) => const MediaPickerScreen(
          requestType: RequestType.common,
          title: 'Select Media to Hide',
        ),
      ),
    );

    if (selectedAssets == null || selectedAssets.isEmpty) {
      ToastUtils.showInfo('No media selected');
      return;
    }

    final progressState = ValueNotifier<OperationProgressState>(
      OperationProgressState(
        totalFiles: selectedAssets.length,
        currentFile: 0,
        currentFileName: 'Preparing...',
        totalSizeBytes: 0,
        processedSizeBytes: 0,
        statusMessage: 'Starting...',
        isProcessing: true,
      ),
    );

    // Show progress sheet
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => ValueListenableBuilder<OperationProgressState>(
        valueListenable: progressState,
        builder: (context, state, _) => OperationProgressSheet(
          operationType: OperationType.hide,
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

    final result = await _importService.importFromAssets(
      assets: selectedAssets,
      deleteOriginals: true, // Hide from gallery
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
      onFileProgress: (fileInfo) {
        progressState.value = progressState.value.copyWith(
          totalFiles: fileInfo.total,
          currentFile: fileInfo.current,
          currentFileName: fileInfo.fileName,
          statusMessage: fileInfo.status,
          isEncrypting: fileInfo.isEncrypting,
          processedSizeBytes:
              fileInfo.isEncrypting ? fileInfo.encryptedBytes : null,
          totalSizeBytes: fileInfo.isEncrypting ? fileInfo.totalBytes : null,
        );
      },
    );

    if (!mounted) return;

    if (result.success && result.importedCount > 0) {
      final msg = result.deletedOriginals
          ? 'Imported and hidden ${result.importedCount} file(s)'
          : 'Imported ${result.importedCount} file(s) (originals may still be visible)';
      ToastUtils.showSuccess(msg);
      ref.read(vaultNotifierProvider.notifier).loadFiles();
    } else if (!result.success) {
      ToastUtils.showError(result.error ?? 'Import failed');
    }

    Navigator.pop(context); // Close progress sheet
  }

  Future<void> _capturePhoto() async {
    Navigator.pop(context);

    // Open custom camera
    final String? imagePath = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CameraScreen(initialMode: CameraMode.photo),
      ),
    );

    if (imagePath == null) return;

    setState(() => _isImporting = true);

    final result = await _importService.importFile(
      filePath: imagePath,
      deleteOriginal: true,
    );

    setState(() => _isImporting = false);

    if (result.success && result.importedCount > 0) {
      ToastUtils.showSuccess('Photo captured and hidden');
      ref.read(vaultNotifierProvider.notifier).loadFiles();
    } else if (!result.success) {
      ToastUtils.showError(result.error ?? 'Capture failed');
    }
  }

  Future<void> _recordVideo() async {
    Navigator.pop(context);

    // Open custom camera
    final String? videoPath = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CameraScreen(initialMode: CameraMode.video),
      ),
    );

    if (videoPath == null) return;

    setState(() => _isImporting = true);

    final result = await _importService.importFile(
      filePath: videoPath,
      deleteOriginal: true,
    );

    setState(() => _isImporting = false);

    if (result.success && result.importedCount > 0) {
      ToastUtils.showSuccess('Video recorded and hidden');
      ref.read(vaultNotifierProvider.notifier).loadFiles();
    } else if (!result.success) {
      ToastUtils.showError(result.error ?? 'Recording failed');
    }
  }

  Future<void> _importDocuments() async {
    Navigator.pop(context);

    // Open custom document picker
    final selectedDocuments = await Navigator.push<List<DocumentFile>?>(
      context,
      MaterialPageRoute(
        builder: (context) => const DocumentPickerScreen(
          title: 'Select Documents to Hide',
        ),
      ),
    );

    if (selectedDocuments == null || selectedDocuments.isEmpty) {
      ToastUtils.showInfo('No documents selected');
      return;
    }

    setState(() {
      _isImporting = true;
      _importProgress = 0;
      _importTotal = selectedDocuments.length;
    });

    // Use the new conversion-aware import method
    final result = await _importService.importFromDocumentFilesWithConversion(
      filePaths: selectedDocuments.map((d) => d.path).toList(),
      deleteOriginals: true, // Hide from file manager
      onConversionConfirmation: (officeFiles) async {
        // Show conversion confirmation dialog
        if (!mounted) return false;
        final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => OfficeConversionConfirmDialog(
            officeFiles: officeFiles,
            onConfirm: () => Navigator.pop(context, true),
            onCancel: () => Navigator.pop(context, false),
          ),
        );
        return confirmed ?? false;
      },
      onProgress: (current, total) {
        setState(() {
          _importProgress = current;
          _importTotal = total;
        });
      },
      onStatusUpdate: (message) {
        // Could be used to show a status message
        debugPrint('[Import] $message');
      },
    );

    setState(() => _isImporting = false);

    if (result.success && result.importedCount > 0) {
      final msgBuilder =
          StringBuffer('Imported ${result.importedCount} document(s)');
      if (result.convertedCount > 0) {
        msgBuilder.write(' (${result.convertedCount} converted to PDF)');
      }
      if (result.deletedOriginals) {
        msgBuilder.write(' and hidden from device');
      }
      ToastUtils.showSuccess(msgBuilder.toString());
      ref.read(vaultNotifierProvider.notifier).loadFiles();
    } else if (!result.success) {
      ToastUtils.showError(result.error ?? 'Import failed');
    } else {
      ToastUtils.showInfo('No documents imported');
    }
  }

  Future<void> _importSongs() async {
    Navigator.pop(context);

    final selectedSongs = await Navigator.push<List<DocumentFile>?>(
      context,
      MaterialPageRoute(
        builder: (context) => const DocumentPickerScreen(
          title: 'Select Songs to Hide',
          allowedExtensions: supportedAudioExtensions,
          itemLabel: 'song',
          itemLabelPlural: 'songs',
          stateIcon: Icons.music_note_outlined,
        ),
      ),
    );

    if (selectedSongs == null || selectedSongs.isEmpty) {
      ToastUtils.showInfo('No songs selected');
      return;
    }

    setState(() {
      _isImporting = true;
      _importProgress = 0;
      _importTotal = selectedSongs.length;
    });

    final result = await _importService.importFromDocumentFiles(
      filePaths: selectedSongs.map((song) => song.path).toList(),
      deleteOriginals: true,
      onProgress: (current, total) {
        setState(() {
          _importProgress = current;
          _importTotal = total;
        });
      },
    );

    setState(() => _isImporting = false);

    if (result.success && result.importedCount > 0) {
      final msg = result.deletedOriginals
          ? 'Imported and hidden ${result.importedCount} song(s)'
          : 'Imported ${result.importedCount} song(s)';
      ToastUtils.showSuccess(msg);
      ref.read(vaultNotifierProvider.notifier).loadFiles();
    } else if (!result.success) {
      ToastUtils.showError(result.error ?? 'Import failed');
    } else {
      ToastUtils.showInfo('No songs imported');
    }
  }

  Future<void> _importAnyFiles() async {
    Navigator.pop(context);
    setState(() {
      _isImporting = true;
      _importProgress = 0;
      _importTotal = 0;
    });

    final result = await _importService.importAnyFiles(
      deleteOriginals: true, // Hide originals
      onProgress: (current, total) {
        setState(() {
          _importProgress = current;
          _importTotal = total;
        });
      },
    );

    setState(() => _isImporting = false);

    if (result.success && result.importedCount > 0) {
      final msg = result.deletedOriginals
          ? 'Imported and hidden ${result.importedCount} file(s)'
          : 'Imported ${result.importedCount} file(s)';
      ToastUtils.showSuccess(msg);
      ref.read(vaultNotifierProvider.notifier).loadFiles();
    } else if (!result.success) {
      ToastUtils.showError(result.error ?? 'Import failed');
    } else {
      ToastUtils.showInfo('No files selected');
    }
  }
}

/// Import options bottom sheet
class _ImportOptionsSheet extends StatelessWidget {
  final VoidCallback onImportImages;
  final VoidCallback onImportVideos;
  final VoidCallback onImportMedia;
  final VoidCallback onCapturePhoto;
  final VoidCallback onRecordVideo;
  final VoidCallback onImportSongs;
  final VoidCallback onImportDocuments;
  final VoidCallback onImportAnyFiles;

  const _ImportOptionsSheet({
    required this.onImportImages,
    required this.onImportVideos,
    required this.onImportMedia,
    required this.onCapturePhoto,
    required this.onRecordVideo,
    required this.onImportSongs,
    required this.onImportDocuments,
    required this.onImportAnyFiles,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.backgroundColor,
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
                  'Import Files',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                    fontFamily: 'ProductSans',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Files will be encrypted and hidden securely',
                  style: TextStyle(
                    fontSize: 14,
                    color: context.textSecondary,
                    fontFamily: 'ProductSans',
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionHeader(context, 'From Gallery'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _ImportOptionTile(
                        icon: Icons.photo_library_outlined,
                        label: 'Images',
                        color: context.accentColor,
                        onTap: onImportImages,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ImportOptionTile(
                        icon: Icons.video_library_outlined,
                        label: 'Videos',
                        color: Colors.red,
                        onTap: onImportVideos,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ImportOptionTile(
                        icon: Icons.perm_media_outlined,
                        label: 'All Media',
                        color: Colors.purple,
                        onTap: onImportMedia,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSectionHeader(context, 'From Camera'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _ImportOptionTile(
                        icon: Icons.camera_alt_outlined,
                        label: 'Take Photo',
                        color: Colors.teal,
                        onTap: onCapturePhoto,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ImportOptionTile(
                        icon: Icons.videocam_outlined,
                        label: 'Record Video',
                        color: Colors.orange,
                        onTap: onRecordVideo,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(child: SizedBox()),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSectionHeader(context, 'From File Manager'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _ImportOptionTile(
                        icon: Icons.music_note_outlined,
                        label: 'Songs',
                        color: Colors.purple,
                        onTap: onImportSongs,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ImportOptionTile(
                        icon: Icons.description_outlined,
                        label: 'Documents',
                        color: Colors.green,
                        onTap: onImportDocuments,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ImportOptionTile(
                        icon: Icons.folder_zip_outlined,
                        label: 'Any Files',
                        color: Colors.blueGrey,
                        onTap: onImportAnyFiles,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
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
}

class _ImportOptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ImportOptionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
                fontFamily: 'ProductSans',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Const-friendly placeholder widget for loading images
/// Extracted as a separate class to enable const constructor usage
class _ImageLoadingPlaceholder extends StatelessWidget {
  const _ImageLoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade200,
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
          ),
        ),
      ),
    );
  }
}
