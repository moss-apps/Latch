import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';
import '../services/auto_kill_service.dart';
import '../themes/app_colors.dart';
import '../utils/responsive_utils.dart';

/// A custom media picker that uses PhotoManager to directly access gallery assets.
/// This allows proper deletion of original files from the gallery.
class MediaPickerScreen extends StatefulWidget {
  /// The type of media to show (image, video, or all)
  final RequestType requestType;

  /// Maximum number of items that can be selected (0 = unlimited)
  final int maxSelection;

  /// Title for the app bar
  final String title;

  const MediaPickerScreen({
    super.key,
    this.requestType = RequestType.common,
    this.maxSelection = 0,
    this.title = 'Select Media',
  });

  @override
  State<MediaPickerScreen> createState() => _MediaPickerScreenState();
}

class _MediaPickerScreenState extends State<MediaPickerScreen> {
  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _currentAlbum;
  List<AssetEntity> _assets = [];
  final Set<AssetEntity> _selectedAssets = {};
  final Map<String, GlobalKey> _tileKeys = {};
  bool _isLoading = true;
  int _currentPage = 0;
  static const int _pageSize = 80;
  bool _hasMoreToLoad = true;
  final ScrollController _scrollController = ScrollController();
  bool _isSlidingSelection = false;
  bool? _slidingSelectionValue;
  final Set<String> _slidingTouchedAssetIds = {};
  OverlayEntry? _previewEntry;
  final ValueNotifier<Offset> _previewPosition = ValueNotifier(Offset.zero);
  final ValueNotifier<AssetEntity?> _previewAsset = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    _loadAlbums();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _hidePreview();
    _previewPosition.dispose();
    _previewAsset.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreAssets();
    }
  }

  Future<void> _loadAlbums() async {
    final permission = await AutoKillService.runSafe(
        () => PhotoManager.requestPermissionExtend());
    if (!permission.hasAccess) {
      if (mounted) {
        Navigator.pop(context, null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permission denied')),
        );
      }
      return;
    }

    // Configure filter to sort by creation date (most recent first)
    final filterOption = FilterOptionGroup(
      imageOption: const FilterOption(
        sizeConstraint: SizeConstraint(ignoreSize: true),
      ),
      videoOption: const FilterOption(
        sizeConstraint: SizeConstraint(ignoreSize: true),
      ),
      orders: [
        const OrderOption(type: OrderOptionType.createDate, asc: false),
      ],
    );

    final albums = await PhotoManager.getAssetPathList(
      type: widget.requestType,
      hasAll: true,
      filterOption: filterOption,
    );

    if (albums.isNotEmpty) {
      setState(() {
        _albums = albums;
        _currentAlbum = albums.first;
      });
      await _loadAssets();
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAssets() async {
    if (_currentAlbum == null) return;

    setState(() {
      _isLoading = true;
      _currentPage = 0;
      _assets = [];
      _hasMoreToLoad = true;
    });

    final assets = await _currentAlbum!.getAssetListPaged(
      page: 0,
      size: _pageSize,
    );

    setState(() {
      _assets = assets;
      _isLoading = false;
      _hasMoreToLoad = assets.length >= _pageSize;
    });
  }

  Future<void> _loadMoreAssets() async {
    if (_currentAlbum == null || _isLoading || !_hasMoreToLoad) return;

    setState(() => _isLoading = true);

    final nextPage = _currentPage + 1;
    final assets = await _currentAlbum!.getAssetListPaged(
      page: nextPage,
      size: _pageSize,
    );

    setState(() {
      _currentPage = nextPage;
      _assets.addAll(assets);
      _isLoading = false;
      _hasMoreToLoad = assets.length >= _pageSize;
    });
  }

  void _toggleSelection(AssetEntity asset) {
    setState(() {
      _setSelected(asset, !_selectedAssets.contains(asset));
    });
  }

  bool _setSelected(AssetEntity asset, bool isSelected,
      {bool showLimitError = true}) {
    if (isSelected) {
      if (_selectedAssets.contains(asset)) return true;

      if (widget.maxSelection > 0 &&
          _selectedAssets.length >= widget.maxSelection) {
        if (showLimitError) {
          _showMaxSelectionMessage();
        }
        return false;
      }

      _selectedAssets.add(asset);
      return true;
    }

    _selectedAssets.remove(asset);
    return true;
  }

  void _showMaxSelectionMessage() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Maximum ${widget.maxSelection} items can be selected'),
          duration: const Duration(seconds: 1),
        ),
      );
  }

  GlobalKey _tileKeyFor(String assetId) {
    return _tileKeys.putIfAbsent(assetId, GlobalKey.new);
  }

  void _startSlidingSelection(AssetEntity asset) {
    final shouldSelect = !_selectedAssets.contains(asset);
    if (!_setSelected(asset, shouldSelect)) return;

    setState(() {
      _isSlidingSelection = true;
      _slidingSelectionValue = shouldSelect;
      _slidingTouchedAssetIds
        ..clear()
        ..add(asset.id);
    });
  }

  void _updateSlidingSelection(Offset globalPosition) {
    if (!_isSlidingSelection || _slidingSelectionValue == null) return;

    final assetId = _assetIdAt(globalPosition);
    if (assetId == null || _slidingTouchedAssetIds.contains(assetId)) return;

    final asset = _assetById(assetId);
    if (asset == null) return;

    final applied =
        _setSelected(asset, _slidingSelectionValue!, showLimitError: false);
    if (!applied) {
      _showMaxSelectionMessage();
      _stopSlidingSelection();
      return;
    }

    setState(() {
      _slidingTouchedAssetIds.add(assetId);
    });
  }

  void _stopSlidingSelection() {
    if (!_isSlidingSelection) return;

    setState(() {
      _isSlidingSelection = false;
      _slidingSelectionValue = null;
      _slidingTouchedAssetIds.clear();
    });
  }

  void _showPreview(AssetEntity asset, Offset globalPosition) {
    _hidePreview();
    _previewEntry = OverlayEntry(
      builder: (_) => _HoldPreviewCard(
        asset: _previewAsset,
        position: _previewPosition,
      ),
    );
    Overlay.of(context).insert(_previewEntry!);
    _previewAsset.value = asset;
    _previewPosition.value = globalPosition;
  }

  void _updatePreview(Offset globalPosition) {
    if (_previewEntry == null) return;
    _previewPosition.value = globalPosition;

    final assetId = _assetIdAt(globalPosition);
    if (assetId == null) return;
    final asset = _assetById(assetId);
    if (asset != null && _previewAsset.value?.id != asset.id) {
      _previewAsset.value = asset;
    }
  }

  void _hidePreview() {
    _previewEntry?.remove();
    _previewEntry = null;
    _previewAsset.value = null;
  }

  AssetEntity? _assetById(String assetId) {
    for (final asset in _assets) {
      if (asset.id == assetId) return asset;
    }
    return null;
  }

  String? _assetIdAt(Offset globalPosition) {
    for (final entry in _tileKeys.entries) {
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

  void _selectAll() {
    setState(() {
      if (widget.maxSelection > 0) {
        // Select up to max
        for (final asset in _assets) {
          if (_selectedAssets.length >= widget.maxSelection) break;
          _selectedAssets.add(asset);
        }
      } else {
        _selectedAssets.addAll(_assets);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedAssets.clear();
    });
  }

  void _confirmSelection() {
    Navigator.pop(context, _selectedAssets.toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: context.textPrimary),
          onPressed: () => Navigator.pop(context, null),
        ),
        title: _buildAlbumDropdown(),
        actions: [
          if (_selectedAssets.isNotEmpty)
            TextButton(
              onPressed: _clearSelection,
              child: const Text('Clear'),
            ),
          if (_assets.isNotEmpty)
            TextButton(
              onPressed: _selectAll,
              child: const Text('Select All'),
            ),
        ],
      ),
      body: _isLoading && _assets.isEmpty
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(context.accentColor),
              ),
            )
          : _assets.isEmpty
              ? _buildEmptyState()
              : _buildMediaGrid(),
      bottomNavigationBar:
          _selectedAssets.isNotEmpty ? _buildBottomBar() : null,
    );
  }

  Widget _buildAlbumDropdown() {
    if (_albums.isEmpty) {
      return Text(
        widget.title,
        style: TextStyle(
          fontFamily: 'ProductSans',
          color: context.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return PopupMenuButton<AssetPathEntity>(
      initialValue: _currentAlbum,
      onSelected: (album) {
        setState(() {
          _currentAlbum = album;
        });
        _loadAssets();
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              _currentAlbum?.name ?? widget.title,
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: context.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(Icons.arrow_drop_down, color: context.textPrimary),
        ],
      ),
      itemBuilder: (context) => _albums.map((album) {
        return PopupMenuItem(
          value: album,
          child: FutureBuilder<int>(
            future: album.assetCountAsync,
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return Text(
                '${album.name} ($count)',
                style: const TextStyle(fontFamily: 'ProductSans'),
              );
            },
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 64,
            color: context.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            'No media found',
            style: TextStyle(
              fontFamily: 'ProductSans',
              fontSize: 18,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaGrid() {
    _tileKeys.removeWhere(
      (assetId, _) => !_assets.any((asset) => asset.id == assetId),
    );

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(2),
      gridDelegate: ResponsiveGridDelegate.responsive(
        context,
        compact: 4,
        medium: 5,
        expanded: 6,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _assets.length + (_hasMoreToLoad ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _assets.length) {
          return Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(context.accentColor),
            ),
          );
        }
        return _buildAssetTile(_assets[index]);
      },
    );
  }

  Widget _buildAssetTile(AssetEntity asset) {
    final isSelected = _selectedAssets.contains(asset);
    final selectionIndex = _selectedAssets.toList().indexOf(asset);

    return GestureDetector(
      onLongPressStart: (details) {
        _startSlidingSelection(asset);
        _showPreview(asset, details.globalPosition);
      },
      onLongPressMoveUpdate: (details) {
        _updateSlidingSelection(details.globalPosition);
        _updatePreview(details.globalPosition);
      },
      onLongPressEnd: (_) {
        _stopSlidingSelection();
        _hidePreview();
      },
      onLongPressCancel: () {
        _stopSlidingSelection();
        _hidePreview();
      },
      onTap: () => _toggleSelection(asset),
      child: Stack(
        key: _tileKeyFor(asset.id),
        fit: StackFit.expand,
        children: [
          // Thumbnail
          FutureBuilder<Uint8List?>(
            future: asset.thumbnailDataWithSize(
              const ThumbnailSize(200, 200),
              quality: 80,
            ),
            builder: (context, snapshot) {
              // Handle errors gracefully
              if (snapshot.hasError) {
                return Container(
                  color: context.backgroundSecondary,
                  child: Icon(
                    asset.type == AssetType.video
                        ? Icons.videocam
                        : Icons.image,
                    color: context.textTertiary,
                  ),
                );
              }

              if (snapshot.hasData &&
                  snapshot.data != null &&
                  snapshot.data!.isNotEmpty) {
                try {
                  return Image.memory(
                    snapshot.data!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true, // Prevent flickering
                    errorBuilder: (context, error, stackTrace) {
                      // Handle image decode errors
                      return Container(
                        color: context.backgroundSecondary,
                        child: Icon(
                          asset.type == AssetType.video
                              ? Icons.videocam
                              : Icons.image,
                          color: context.textTertiary,
                        ),
                      );
                    },
                  );
                } catch (e) {
                  // Fallback for any other errors
                  return Container(
                    color: context.backgroundSecondary,
                    child: Icon(
                      asset.type == AssetType.video
                          ? Icons.videocam
                          : Icons.image,
                      color: context.textTertiary,
                    ),
                  );
                }
              }

              // Loading state
              return Container(
                color: context.backgroundSecondary,
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(
                          context.accentColor.withValues(alpha: 0.5)),
                    ),
                  ),
                ),
              );
            },
          ),

          // Video indicator
          if (asset.type == AssetType.video)
            Positioned(
              bottom: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_arrow, size: 12, color: Colors.white),
                    const SizedBox(width: 2),
                    Text(
                      _formatDuration(asset.videoDuration),
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

          // Selection overlay
          if (isSelected)
            Container(
              color: context.accentColor.withValues(alpha: 0.3),
            ),

          // Selection indicator
          Positioned(
            top: 4,
            right: 4,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? context.accentColor
                    : Colors.white.withValues(alpha: 0.7),
                border: Border.all(
                  color: isSelected ? context.accentColor : Colors.grey,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Text(
                        '${selectionIndex + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'ProductSans',
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: context.backgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_selectedAssets.length} selected',
              style: TextStyle(
                fontFamily: 'ProductSans',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: _confirmSelection,
            icon: const Icon(Icons.check, size: 20),
            label: const Text('Hide Selected'),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.accentColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Result from the media picker containing the selected assets
class MediaPickerResult {
  final List<AssetEntity> selectedAssets;

  const MediaPickerResult({required this.selectedAssets});

  bool get isEmpty => selectedAssets.isEmpty;
  bool get isNotEmpty => selectedAssets.isNotEmpty;
  int get count => selectedAssets.length;
}

/// Computes a clamped on-screen rect for the hold-to-preview card so it stays
/// fully visible, preferring a spot above the finger.
Rect holdPreviewRect(Offset finger, Size screen, Size card) {
  const margin = 12.0;

  final left = (finger.dx - card.width / 2).clamp(
    margin,
    math.max(margin, screen.width - card.width - margin),
  ).toDouble();
  var top = finger.dy - card.height - 56;
  if (top < margin) top = finger.dy + 56;
  top = top.clamp(
    margin,
    math.max(margin, screen.height - card.height - margin),
  );

  return Rect.fromLTWH(left, top, card.width, card.height);
}

class _HoldPreviewCard extends StatelessWidget {
  final ValueListenable<AssetEntity?> asset;
  final ValueListenable<Offset> position;

  const _HoldPreviewCard({required this.asset, required this.position});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Offset>(
      valueListenable: position,
      builder: (context, finger, _) {
        final screen = MediaQuery.of(context).size;
        final side =
            (screen.shortestSide * 0.65).clamp(200.0, 340.0).toDouble();
        final rect = holdPreviewRect(finger, screen, Size(side, side));

        return Positioned.fromRect(
          rect: rect,
          child: IgnorePointer(
            child: ValueListenableBuilder<AssetEntity?>(
              valueListenable: asset,
              builder: (context, asset, _) {
                if (asset == null) return const SizedBox.shrink();
                return DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    // Keyed so a new hold starts fresh (no stale video frame).
                    child: KeyedSubtree(
                      key: ValueKey(asset.id),
                      child: Container(
                        color: Colors.black,
                        child: _AssetPreviewContent(asset: asset),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _AssetPreviewContent extends StatelessWidget {
  final AssetEntity asset;

  const _AssetPreviewContent({required this.asset});

  @override
  Widget build(BuildContext context) {
    if (asset.type == AssetType.video) return _VideoPreview(asset: asset);
    return _ImagePreview(asset: asset);
  }
}

class _ImagePreview extends StatefulWidget {
  final AssetEntity asset;

  const _ImagePreview({required this.asset});

  @override
  State<_ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<_ImagePreview> {
  late final Future<Uint8List?> _future = widget.asset.thumbnailDataWithSize(
    const ThumbnailSize(1200, 1200),
    quality: 90,
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null && bytes.isNotEmpty) {
          return Image.memory(bytes, fit: BoxFit.contain);
        }
        if (snapshot.hasError) {
          return const Center(
            child: Icon(Icons.broken_image, color: Colors.white54),
          );
        }
        return const Center(
          child: CircularProgressIndicator(color: Colors.white70),
        );
      },
    );
  }
}

class _VideoPreview extends StatefulWidget {
  final AssetEntity asset;

  const _VideoPreview({required this.asset});

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  VideoPlayerController? _controller;
  bool _failed = false;
  late final Future<Uint8List?> _thumb = widget.asset.thumbnailDataWithSize(
    const ThumbnailSize(1200, 1200),
    quality: 90,
  );

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final file = await widget.asset.file;
      if (file == null || !mounted) return;
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return FutureBuilder<Uint8List?>(
        future: _thumb,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes != null && bytes.isNotEmpty && !_failed) {
            return Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(bytes, fit: BoxFit.contain),
                const Center(
                  child: Icon(Icons.play_arrow,
                      size: 48, color: Colors.white70),
                ),
              ],
            );
          }
          return const SizedBox.expand();
        },
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio:
            controller.value.aspectRatio == 0
                ? 1
                : controller.value.aspectRatio,
        child: VideoPlayer(controller),
      ),
    );
  }
}
