import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vault_category.dart';
import '../models/vault_file_filter.dart';
import '../models/vaulted_file.dart';
import '../models/album.dart';
import '../providers/vault_providers.dart';
import '../providers/smart_collection_providers.dart';
import '../providers/operation_provider.dart';
import '../services/auto_kill_service.dart';
import '../services/pb/pocketbase_runtime.dart';
import '../services/gallery_file_query.dart';
import '../services/gallery_import_coordinator.dart';
import '../services/whats_new_service.dart';
import '../themes/app_colors.dart';
import '../utils/toast_utils.dart';
import '../utils/responsive_utils.dart';
import '../utils/path_utils.dart';
import '../widgets/gallery/gallery_file_thumbnail.dart';
import '../widgets/gallery/gallery_vault_drawer.dart';
import '../widgets/floating_capsule_bottom_bar.dart';
import '../widgets/file_info_sheet.dart';
import '../widgets/add_tags_sheet.dart';
import '../services/file_open_service.dart';
import '../widgets/permission_warning_banner.dart';
import 'vault_settings_screen.dart';
import 'albums_screen.dart';
import 'smart_collections_screen.dart';
import 'note_editor_screen.dart';
import 'password_editor_screen.dart';
import '../providers/note_providers.dart';
import '../providers/password_providers.dart';
import '../widgets/media_hold_action_sheet.dart';
import '../widgets/media_multi_select_action_sheet.dart';
import '../widgets/vault_filter_sheet.dart';
import '../widgets/whats_new_bottom_sheet.dart';

/// Gallery vault screen - main screen after authentication
class GalleryVaultScreen extends ConsumerStatefulWidget {
  const GalleryVaultScreen({super.key});

  @override
  ConsumerState<GalleryVaultScreen> createState() => _GalleryVaultScreenState();
}

class _GalleryVaultScreenState extends ConsumerState<GalleryVaultScreen> {
  VaultCategory _selectedCategory = VaultCategory.all;
  List<VaultCategory> _enabledCategories = VaultCategory.values;
  FeatureSide _importSide = FeatureSide.right;
  late final PageController _pageController;
  final Map<String, GlobalKey> _selectionTileKeys = {};

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  bool _isSlidingSelection = false;
  bool? _slidingSelectionValue;
  String? _slidingTabKey;
  final Set<String> _slidingTouchedTileKeys = {};

  // Hold-action UX state
  bool _didDragDuringHold = false;
  String? _holdActionFileId;
  String? _pressedFileId;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadEnabledCategories();
    _initializeVault();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeVault() async {
    try {
      await ref.read(vaultServiceProvider).initialize();
    } catch (e) {
      if (mounted) debugPrint('[Vault] initialization failed: $e');
      return;
    }
    if (!mounted) return;
    ref.read(isDecoyModeProvider.notifier).state =
        ref.read(decoyServiceProvider).isDecoyModeActive;
    ref.read(vaultNotifierProvider.notifier).loadFiles();
    if (!ref.read(isDecoyModeProvider)) unawaited(_startPocketBase());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WhatsNewService.instance.startRemoteRefresh();
      _maybeShowWhatsNew();
    });
  }

  Future<void> _startPocketBase() async {
    try {
      final vault = ref.read(vaultServiceProvider);
      final settings = await vault.getSettings();
      if (!settings.pbEnabled || !mounted) return;
      await PocketBaseRuntime.instance.start();
      if (!mounted) return;
      await vault.activatePocketBase();
      if (!mounted) return;
      await ref.read(vaultNotifierProvider.notifier).loadFiles();
    } catch (e) {
      debugPrint('[PB] activation failed, staying on legacy store: $e');
    }
  }

  Future<void> _maybeShowWhatsNew() async {
    // Decoy persona stays quiet to avoid leaking that a real vault exists.
    if (ref.read(isDecoyModeProvider)) return;

    final service = WhatsNewService.instance;
    if (!await service.shouldShow()) return;

    final version = await service.currentVersion();
    final sections = await service.highlightsFor(version);
    if (sections.isEmpty || !mounted) return;

    await WhatsNewBottomSheet.show(
      context,
      version: version,
      sections: sections,
    );
    await service.markSeen();
  }

  @override
  Widget build(BuildContext context) {
    final filesAsync = ref.watch(vaultNotifierProvider);
    final isSelectionMode = ref.watch(isSelectionModeProvider);
    final selectedFiles = ref.watch(selectedFilesProvider);
    final activeFilter = ref.watch(fileFilterProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      extendBody: true,
      appBar: _buildAppBar(isSelectionMode, selectedFiles, activeFilter),
      body: Column(
        children: [
          // Permission warning banner for All Files Access
          const PermissionWarningBanner(),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 300),
            crossFadeState: _isSearching
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: _buildSearchBar(),
            secondChild: const SizedBox(height: 0, width: double.infinity),
            sizeCurve: Curves.easeInOut,
          ),
          if (activeFilter.hasActiveFilters)
            _buildActiveFilterBar(activeFilter),
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) =>
                  setState(() => _selectedCategory = _enabledCategories[index]),
              children: _enabledCategories
                  .map((c) => _buildFileGrid(c.filterType, filesAsync))
                  .toList(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(isSelectionMode),
      drawer: _buildDrawer(),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isSelectionMode,
      Set<String> selectedFiles, VaultFileFilter activeFilter) {
    if (isSelectionMode) {
      final visibleFiles = _getVisibleFiles();
      final allSelected = visibleFiles.isNotEmpty &&
          visibleFiles.every((f) => selectedFiles.contains(f.id));

      return AppBar(
        backgroundColor: context.accentColor,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          tooltip: 'Exit selection',
          onPressed: _exitSelectionMode,
        ),
        title: Text(
          '${selectedFiles.length} selected',
          style: const TextStyle(
            fontFamily: 'GoogleSansFlex',
            color: Colors.white,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _toggleSelectAll,
            child: Text(
              allSelected ? 'Deselect All' : 'Select All',
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'GoogleSansFlex',
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () => _showMultiSelectActionSheet(selectedFiles),
            tooltip: 'Actions',
          ),
        ],
      );
    }

    return AppBar(
      title: Text(
        'Gallery Vault',
        style: TextStyle(
          fontFamily: 'GoogleSansFlex',
          color: context.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      elevation: 0,
      actions: [
        IconButton(
          tooltip: 'Filter',
          onPressed: _openFilterSheet,
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(Icons.tune, color: context.textPrimary),
              if (activeFilter.activeFilterCount > 0)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    constraints: const BoxConstraints(minWidth: 16),
                    decoration: BoxDecoration(
                      color: context.accentColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${activeFilter.activeFilterCount}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontFamily: 'GoogleSansFlex',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'More options',
          icon: Icon(Icons.more_vert, color: context.textPrimary),
          onSelected: (value) {
            switch (value) {
              case 'search':
                setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) {
                    _searchController.clear();
                    ref.read(searchQueryProvider.notifier).state = '';
                  }
                });
                break;
              case 'sort':
                _showSortOptions();
                break;
              case 'albums':
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AlbumsScreen()),
                );
                break;
              case 'settings':
                _openSettingsScreen();
                break;
              case 'customize_bar':
                _showCustomizeBarSheet();
                break;
              case 'refresh':
                ref.read(vaultNotifierProvider.notifier).refresh();
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'search',
              child: Row(
                children: [
                  Icon(_isSearching ? Icons.close : Icons.search, size: 20),
                  const SizedBox(width: 12),
                  Text(_isSearching ? 'Close search' : 'Search'),
                ],
              ),
            ),
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
              value: 'customize_bar',
              child: Row(
                children: [
                  Icon(Icons.tune, size: 20),
                  SizedBox(width: 12),
                  Text('Customize Bar'),
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
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search files...',
          hintStyle: TextStyle(
            fontFamily: 'GoogleSansFlex',
            color: context.textTertiary,
          ),
          prefixIcon: Icon(Icons.search, color: context.textTertiary, size: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: context.backgroundSecondary,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        style: TextStyle(
          fontFamily: 'GoogleSansFlex',
          color: context.textPrimary,
        ),
        onChanged: (value) {
          ref.read(searchQueryProvider.notifier).state = value;
        },
      ),
    );
  }

  Future<void> _openFilterSheet() async {
    final result = await VaultFilterSheet.show(
      context,
      initialFilter: ref.read(fileFilterProvider),
      allowSaveSearch: true,
    );
    if (result == null || !mounted) return;
    ref.read(fileFilterProvider.notifier).state = result.filter;
    if (result.action == VaultFilterAction.saveSearch) {
      await _saveFilterAsCollection(result.filter);
    }
  }

  Future<void> _saveFilterAsCollection(VaultFileFilter filter) async {
    final name = await showSmartCollectionNameDialog(context);
    if (name == null || !mounted) return;
    final created = await ref.read(smartCollectionsProvider.notifier).create(
          name: name,
          filter: filter,
        );
    if (!mounted) return;
    if (created != null) {
      ToastUtils.showSuccess('Saved "${created.name}"');
    } else {
      ToastUtils.showError('Could not save collection');
    }
  }

  void _clearFilters() {
    ref.read(fileFilterProvider.notifier).state = const VaultFileFilter();
  }

  Widget _buildActiveFilterBar(VaultFileFilter filter) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
      child: Row(
        children: [
          Icon(Icons.filter_alt, size: 16, color: context.accentColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              filter.activeFilterCount == 1
                  ? '1 filter active'
                  : '${filter.activeFilterCount} filters active',
              style: TextStyle(
                fontSize: 13,
                color: context.textSecondary,
                fontFamily: 'GoogleSansFlex',
              ),
            ),
          ),
          TextButton(
            onPressed: _clearFilters,
            child: Text(
              'Clear',
              style: TextStyle(
                color: context.accentColor,
                fontFamily: 'GoogleSansFlex',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(bool isSelectionMode) {
    final tabs = _enabledCategories
        .map((c) => NavTab(
              icon: c.icon,
              label: c.label,
              selected: c == _selectedCategory,
              onTap: () {
                final index = _enabledCategories.indexOf(c);
                _pageController.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                );
              },
            ))
        .toList();

    return FloatingCapsuleBottomBar(
      tabs: tabs,
      feature: NavTab(
        icon: Icons.add,
        label: 'Import',
        selected: false,
        onTap: _showImportDialog,
      ),
      featureSide: _importSide,
      showFeature: !isSelectionMode,
    );
  }

  static const _enabledCategoriesKey = 'gallery_bottom_bar_categories';
  static const _importSideKey = 'gallery_bottom_bar_import_side';

  Future<void> _loadEnabledCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final sideRaw = prefs.getString(_importSideKey);
    if (sideRaw == 'left' || sideRaw == 'right') {
      _importSide = sideRaw == 'left' ? FeatureSide.left : FeatureSide.right;
    }
    final raw = prefs.getStringList(_enabledCategoriesKey);
    if (raw == null || raw.isEmpty) return;
    final parsed = <VaultCategory>[];
    for (final name in raw) {
      final match = VaultCategory.values.firstWhere(
        (e) => e.name == name,
        orElse: () => VaultCategory.all,
      );
      if (!parsed.contains(match)) parsed.add(match);
    }
    if (parsed.isEmpty || !mounted) return;
    setState(() {
      _enabledCategories = parsed;
      if (!_enabledCategories.contains(_selectedCategory)) {
        _selectedCategory = _enabledCategories.first;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = _enabledCategories.indexOf(_selectedCategory);
      if (index != -1 && _pageController.hasClients) {
        _pageController.jumpToPage(index);
      }
    });
  }

  Future<void> _persistEnabledCategories() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _enabledCategoriesKey,
      _enabledCategories.map((c) => c.name).toList(),
    );
  }

  Future<void> _persistImportSide() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _importSideKey,
      _importSide == FeatureSide.left ? 'left' : 'right',
    );
  }

  void _showCustomizeBarSheet() {
    var order = <VaultCategory>[
      ..._enabledCategories,
      ...VaultCategory.values.where((c) => !_enabledCategories.contains(c)),
    ];
    var enabled = Set<VaultCategory>.from(_enabledCategories);

    void apply(StateSetter setSheetState, void Function() mutate) {
      setSheetState(mutate);
      final newEnabled = order.where((c) => enabled.contains(c)).toList();
      setState(() {
        _enabledCategories = newEnabled;
        if (!_enabledCategories.contains(_selectedCategory)) {
          _selectedCategory = _enabledCategories.contains(VaultCategory.all)
              ? VaultCategory.all
              : _enabledCategories.first;
        }
      });
      _persistEnabledCategories();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final index = _enabledCategories.indexOf(_selectedCategory);
        if (index != -1 && _pageController.hasClients) {
          _pageController.jumpToPage(index);
        }
      });
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
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
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Customize Bottom Bar',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                        fontFamily: 'GoogleSansFlex',
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Drag to reorder. Toggle to show or hide.',
                      style: TextStyle(
                        fontFamily: 'GoogleSansFlex',
                        fontSize: 13,
                        color: context.textSecondary,
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: order.length,
                    onReorderItem: (oldIndex, newIndex) {
                      apply(setSheetState, () {
                        final item = order.removeAt(oldIndex);
                        order.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (context, i) {
                      final cat = order[i];
                      final isEnabled = enabled.contains(cat);
                      return SwitchListTile(
                        key: ValueKey(cat),
                        value: isEnabled,
                        onChanged: (v) {
                          apply(setSheetState, () {
                            if (v) {
                              enabled.add(cat);
                            } else if (enabled.length > 1) {
                              enabled.remove(cat);
                            }
                          });
                        },
                        activeThumbColor: context.accentColor,
                        secondary: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ReorderableDragStartListener(
                              index: i,
                              child: Icon(Icons.drag_indicator,
                                  color: context.textTertiary),
                            ),
                            Icon(cat.icon, color: context.accentColor),
                          ],
                        ),
                        title: Text(
                          cat.label,
                          style: const TextStyle(fontFamily: 'GoogleSansFlex'),
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 20),
                      );
                    },
                  ),
                ),
                SwitchListTile(
                  value: _importSide == FeatureSide.left,
                  onChanged: (onLeft) {
                    setState(() => _importSide =
                        onLeft ? FeatureSide.left : FeatureSide.right);
                    _persistImportSide();
                  },
                  activeThumbColor: context.accentColor,
                  secondary: Icon(
                    Icons.add_circle_outline,
                    color: context.accentColor,
                  ),
                  title: const Text(
                    'Import button on left',
                    style: TextStyle(fontFamily: 'GoogleSansFlex'),
                  ),
                  subtitle: Text(
                    'Only applies when the bar has an even total (not centered)',
                    style: TextStyle(
                      fontFamily: 'GoogleSansFlex',
                      fontSize: 12,
                      color: context.textTertiary,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.accentColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Done',
                        style: TextStyle(
                          fontFamily: 'GoogleSansFlex',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
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
                fontFamily: 'GoogleSansFlex',
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
        var files = queryGalleryFiles(allFiles,
            category: VaultCategory.values
                .firstWhere((category) => category.filterType == filterType),
            search: ref.watch(searchQueryProvider),
            filter: ref.watch(fileFilterProvider));

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
            padding: EdgeInsets.fromLTRB(
              8,
              8,
              8,
              MediaQuery.of(context).padding.bottom +
                  FloatingCapsuleBottomBar.bottomFootprintFor(context) +
                  24,
            ),
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
    final tileKey = _selectionTileKey(tabKey, file.id);

    return Consumer(
      builder: (context, ref, child) {
        final selectedFiles = ref.watch(selectedFilesProvider);
        final isSelectionMode = ref.watch(isSelectionModeProvider);
        final isSelected = selectedFiles.contains(file.id);
        final tapOpensMedia =
            ref.watch(vaultSettingsProvider).value?.tapOpensMedia ?? true;

        final isPressed = _pressedFileId == file.id;

        return AnimatedScale(
          scale: isPressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: GestureDetector(
            onTap: () {
              if (isSelectionMode) {
                _toggleSelection(file.id);
              } else if (tapOpensMedia) {
                _openFile(file);
              } else {
                _showMediaHoldActionSheet(file);
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
                    child: child!,
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
                          color: isSelected
                              ? context.accentColor
                              : context.borderColor,
                          width: 2,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check,
                              size: 16, color: Colors.white)
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
                // Filename overlay for all file types
                Positioned(
                  bottom: 8,
                  left: 8,
                  right: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (file.isVideo) ...[
                          const Icon(Icons.play_arrow,
                              size: 14, color: Colors.white),
                          const SizedBox(width: 2),
                        ],
                        Expanded(
                          child: Text(
                            file.originalName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontFamily: 'GoogleSansFlex',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (file.isVideo) ...[
                          const SizedBox(width: 4),
                          Text(
                            file.formattedSize,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontFamily: 'GoogleSansFlex',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // Tags pill centered under the icon, above the filename bar
                // so it never sits behind the filename (notes always carry a
                // 'note' tag, passwords a 'password' tag).
                if (file.hasTags && !isSelectionMode)
                  Positioned(
                    bottom: 38,
                    left: 8,
                    right: 8,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.label,
                                size: 12, color: Colors.white),
                            const SizedBox(width: 2),
                            Text(
                              '${file.tagCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontFamily: 'GoogleSansFlex',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
      child: _buildFileThumbnail(file),
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
      _didDragDuringHold = false;
      _holdActionFileId = fileId;
      _pressedFileId = fileId;
    });

    HapticFeedback.mediumImpact();
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
      _didDragDuringHold = true;
    });

    _setSelection(fileId, _slidingSelectionValue!, keepSelectionMode: true);
  }

  void _stopSlidingSelection() {
    if (!_isSlidingSelection) return;

    final holdFileId = _holdActionFileId;
    final didDrag = _didDragDuringHold;

    setState(() {
      _isSlidingSelection = false;
      _slidingSelectionValue = null;
      _slidingTabKey = null;
      _slidingTouchedTileKeys.clear();
      _didDragDuringHold = false;
      _holdActionFileId = null;
      _pressedFileId = null;
    });

    final selectedFiles = ref.read(selectedFilesProvider);
    if (selectedFiles.isEmpty) {
      ref.read(isSelectionModeProvider.notifier).state = false;
    } else if (!didDrag && holdFileId != null) {
      // User held without dragging: show contextual action sheet
      if (selectedFiles.length == 1 && selectedFiles.contains(holdFileId)) {
        _exitSelectionMode();
        final file = _findFileById(holdFileId);
        if (file != null && mounted) {
          _showMediaHoldActionSheet(file);
        }
      }
    }
  }

  VaultedFile? _findFileById(String id) {
    final allFiles = ref.read(vaultNotifierProvider).value ?? [];
    try {
      return allFiles.firstWhere((f) => f.id == id);
    } catch (_) {
      return null;
    }
  }

  void _showMediaHoldActionSheet(VaultedFile file) {
    MediaHoldActionSheet.show(
      context,
      file: file,
      onFavorite: () => _toggleFavoriteSelected({file.id}),
      onDelete: () => _deleteSelectedFiles({file.id}),
      onInfo: () => _showFileInfo(file),
      onSelect: () {
        setState(() {
          _pressedFileId = null;
        });
        _setSelection(file.id, true);
      },
      onOpen: () => _openFile(file),
      onTags: () => _showAddTagsSheet({file.id}),
      onAddToAlbum: () => _showAddToAlbumSheet({file.id}),
      onExport: () => _exportFileToDownloads(file),
    );
  }

  void _showMultiSelectActionSheet(Set<String> selectedFiles) {
    if (!ref.read(operationControllerProvider).checkAvailable()) return;
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
    final files = ref.read(vaultNotifierProvider).value ?? [];
    final selected = files.where((f) => selectedFiles.contains(f.id)).toList();
    for (final file in selected) {
      await _exportFileToDownloads(file);
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

  Widget _buildFileThumbnail(VaultedFile file) =>
      GalleryFileThumbnail(file: file);

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
    // Clean up selection tile keys to prevent memory leak
    _selectionTileKeys.clear();
  }

  List<VaultedFile> _getVisibleFiles() {
    final files = queryGalleryFiles(ref.read(vaultNotifierProvider).value ?? [],
        category: _selectedCategory,
        search: ref.read(searchQueryProvider),
        filter: ref.read(fileFilterProvider));
    final sortOption = ref.read(sortOptionProvider);
    return ref.read(vaultServiceProvider).sortFiles(files, sortOption);
  }

  void _toggleSelectAll() {
    final visible = _getVisibleFiles();
    final selected = ref.read(selectedFilesProvider);
    final allSelected =
        visible.isNotEmpty && visible.every((f) => selected.contains(f.id));

    if (allSelected) {
      final newSelection = Set<String>.from(selected)
        ..removeAll(visible.map((f) => f.id));
      ref.read(selectedFilesProvider.notifier).state = newSelection;
      if (newSelection.isEmpty) {
        ref.read(isSelectionModeProvider.notifier).state = false;
      }
    } else {
      final newSelection = Set<String>.from(selected)
        ..addAll(visible.map((f) => f.id));
      ref.read(selectedFilesProvider.notifier).state = newSelection;
      ref.read(isSelectionModeProvider.notifier).state = true;
    }
  }

  void _openFile(VaultedFile file) {
    final filesAsync = ref.read(vaultNotifierProvider);
    FileOpenService.open(
      context,
      ref,
      file,
      currentFiles: filesAsync.value ?? [],
      onUnsupported: () => _showFileOptionsSheet(file),
      onOpenNote: (noteId) => _openNoteFromVault(noteId),
      onOpenPassword: (passwordId) => _openPasswordFromVault(passwordId),
    );
  }

  Future<void> _openNoteFromVault(String noteId) async {
    var notesAsync = ref.read(notesNotifierProvider);
    // reload only when cold (isLoading); hot path stays one cached read.
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
                                fontFamily: 'GoogleSansFlex',
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
                                fontFamily: 'GoogleSansFlex',
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
                      fontFamily: 'GoogleSansFlex',
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
                        fontFamily: 'GoogleSansFlex',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      'Save decrypted file to Downloads folder',
                      style: TextStyle(
                        fontFamily: 'GoogleSansFlex',
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
                        fontFamily: 'GoogleSansFlex',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      'Open file with an external app',
                      style: TextStyle(
                        fontFamily: 'GoogleSansFlex',
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
                        fontFamily: 'GoogleSansFlex',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      'View file details',
                      style: TextStyle(
                        fontFamily: 'GoogleSansFlex',
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
                  style: const TextStyle(fontFamily: 'GoogleSansFlex'),
                ),
              ),
            ],
          ),
        ),
      );

      // Get the Downloads directory
      final downloadsDir = await PathUtils.getDownloadsDirectory();

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
      ToastUtils.showError('Failed to export file');
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
                  style: const TextStyle(fontFamily: 'GoogleSansFlex'),
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
            () => OpenFilex.open(decryptedFile.path),
            waitForResume: true);
        if (result.type != ResultType.done) {
          ToastUtils.showError('No app found to open this file type');
        }
      } else {
        ToastUtils.showError('Failed to prepare file');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint('Error opening file: $e');
      ToastUtils.showError('Failed to open file');
    }
  }

  /// Show file info dialog
  void _showFileInfo(VaultedFile file) {
    FileInfoSheet.show(context, file, title: 'File Info');
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
                fontFamily: 'GoogleSansFlex',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 15,
                color: context.textSecondary,
                fontFamily: 'GoogleSansFlex',
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
                    fontFamily: 'GoogleSansFlex',
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

  Widget _buildDrawer() => GalleryVaultDrawer(
      onSettings: _openSettingsScreen, onDecoyMode: _showDecoyModeSheet);

  void _showImportDialog() => GalleryImportCoordinator(context, ref).show();

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
                        fontFamily: 'GoogleSansFlex',
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
                              fontFamily: 'GoogleSansFlex',
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
                            fontFamily: 'GoogleSansFlex',
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
                                          fontFamily: 'GoogleSansFlex',
                                        ),
                                      ),
                                      subtitle: Text(
                                        '${album.fileCount} items',
                                        style: TextStyle(
                                          fontFamily: 'GoogleSansFlex',
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
    AddTagsSheet.show(
      context,
      fileIds: selectedFiles,
      onTagsAdded: (_) => _exitSelectionMode(),
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
    if (!ref.read(operationControllerProvider).checkAvailable()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          'Unhide Files',
          style: TextStyle(
            fontFamily: 'GoogleSansFlex',
            color: context.textPrimary,
          ),
        ),
        content: Text(
          'Are you sure you want to unhide ${selectedFiles.length} file(s)? This will restore them to your device gallery (DCIM/Restored folder) and remove them from the vault.',
          style: TextStyle(
            fontFamily: 'GoogleSansFlex',
            color: context.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'GoogleSansFlex',
                color: context.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Unhide',
              style: TextStyle(
                fontFamily: 'GoogleSansFlex',
                color: context.accentColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    if (ref.read(vaultOperationRunnerProvider).unhide(selectedFiles)) {
      _exitSelectionMode();
    }
  }

  Future<void> _deleteSelectedFiles(Set<String> selectedFiles) async {
    if (!ref.read(operationControllerProvider).checkAvailable()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          'Delete Files',
          style: TextStyle(
            fontFamily: 'GoogleSansFlex',
            color: context.textPrimary,
          ),
        ),
        content: Text(
          'Delete ${selectedFiles.length} file(s)? Recover them in Recently Deleted when retention is enabled. If retention is set to Immediate deletion, this cannot be undone.',
          style: TextStyle(
            fontFamily: 'GoogleSansFlex',
            color: context.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'GoogleSansFlex',
                color: context.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: TextStyle(
                fontFamily: 'GoogleSansFlex',
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    if (ref.read(vaultOperationRunnerProvider).delete(selectedFiles)) {
      _exitSelectionMode();
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
                              fontFamily: 'GoogleSansFlex',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Set up a fake vault that shows when using a different PIN/password. Perfect for situations where you might be forced to open the app.',
                        style: TextStyle(
                          fontFamily: 'GoogleSansFlex',
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
                                style: TextStyle(fontFamily: 'GoogleSansFlex'),
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
                                  style: TextStyle(fontFamily: 'GoogleSansFlex'),
                                ),
                                subtitle: Text(
                                  settings.hasPinSet
                                      ? 'Decoy PIN is set'
                                      : 'Not configured',
                                  style: TextStyle(
                                    fontFamily: 'GoogleSansFlex',
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
            fontFamily: 'GoogleSansFlex',
            color: context.textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This PIN will show your decoy vault instead of your real files.',
              style: TextStyle(
                fontFamily: 'GoogleSansFlex',
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
                  fontFamily: 'GoogleSansFlex',
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
                fontFamily: 'GoogleSansFlex',
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
              style: TextStyle(fontFamily: 'GoogleSansFlex'),
            ),
          ),
        ],
      ),
    ).whenComplete(pinController.dispose);
  }
}
