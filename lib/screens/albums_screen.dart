import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/album.dart';
import '../models/vaulted_file.dart';
import '../providers/vault_providers.dart';
import '../themes/app_colors.dart';
import '../utils/toast_utils.dart';
import '../utils/responsive_utils.dart';
import 'album_detail_screen.dart';

/// Screen for managing albums/folders
class AlbumsScreen extends ConsumerStatefulWidget {
  const AlbumsScreen({super.key});

  @override
  ConsumerState<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends ConsumerState<AlbumsScreen> {
  @override
  Widget build(BuildContext context) {
    final albumsAsync = ref.watch(albumsNotifierProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Albums',
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: context.textPrimary,
        elevation: 0,
      ),
      body: albumsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline,
                  size: 64, color: AppColors.lightTextTertiary),
              const SizedBox(height: 16),
              Text(
                'Failed to load albums',
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  color: context.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () =>
                    ref.read(albumsNotifierProvider.notifier).loadAlbums(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (albums) => _buildAlbumsList(albums),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateAlbumDialog,
        backgroundColor: context.accentColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'New Album',
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildAlbumsList(List<Album> albums) {
    if (albums.isEmpty) {
      return _buildEmptyState();
    }

    // Separate default and custom albums
    final defaultAlbums = albums.where((a) => a.isDefault).toList();
    final customAlbums = albums.where((a) => !a.isDefault).toList();

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(albumsNotifierProvider.notifier).loadAlbums();
      },
      color: context.accentColor,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (defaultAlbums.isNotEmpty) ...[
            _buildSectionHeader('Default Albums'),
            const SizedBox(height: 12),
            _buildAlbumsGrid(defaultAlbums),
            const SizedBox(height: 24),
          ],
          if (customAlbums.isNotEmpty) ...[
            _buildSectionHeader('My Albums'),
            const SizedBox(height: 12),
            _buildAlbumsGrid(customAlbums),
          ],
          if (customAlbums.isEmpty && defaultAlbums.isNotEmpty) ...[
            _buildSectionHeader('My Albums'),
            const SizedBox(height: 12),
            _buildCreateAlbumCard(),
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

  Widget _buildAlbumsGrid(List<Album> albums) {
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
      itemCount: albums.length,
      itemBuilder: (context, index) => _buildAlbumCard(albums[index]),
    );
  }

  Widget _buildAlbumCard(Album album) {
    return GestureDetector(
      onTap: () => _openAlbum(album),
      onLongPress: album.isDefault ? null : () => _showAlbumOptions(album),
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
            // Cover image or placeholder
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: _buildAlbumCover(album),
              ),
            ),
            // Album info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _getAlbumIcon(album.type),
                        size: 16,
                        color: context.accentColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          album.name,
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
                    '${album.fileCount} items',
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

  Widget _buildAlbumCover(Album album) {
    if (album.coverImageId != null) {
      // Try to load cover image
      return FutureBuilder<VaultedFile?>(
        future: ref.read(vaultServiceProvider).getFileById(album.coverImageId!),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            final file = snapshot.data!;
            if (file.isImage) {
              final imageFile = File(file.vaultPath);
              return Image.file(
                imageFile,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                cacheWidth: 400,
                filterQuality: FilterQuality.low,
                errorBuilder: (_, __, ___) => _buildPlaceholderCover(album),
              );
            }
          }
          return _buildPlaceholderCover(album);
        },
      );
    }

    // Try to get first image from album
    if (album.fileIds.isNotEmpty) {
      return FutureBuilder<List<VaultedFile>>(
        future: ref.read(vaultServiceProvider).getFilesInAlbum(album.id),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data!.isNotEmpty) {
            final imageFiles = snapshot.data!.where((f) => f.isImage).toList();
            if (imageFiles.isNotEmpty) {
              final imageFile = File(imageFiles.first.vaultPath);
              return Image.file(
                imageFile,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                cacheWidth: 400,
                filterQuality: FilterQuality.low,
                errorBuilder: (_, __, ___) => _buildPlaceholderCover(album),
              );
            }
          }
          return _buildPlaceholderCover(album);
        },
      );
    }

    return _buildPlaceholderCover(album);
  }

  Widget _buildPlaceholderCover(Album album) {
    final color = _getAlbumColor(album.type);
    return Container(
      color: color.withValues(alpha: 0.1),
      child: Center(
        child: Icon(
          _getAlbumIcon(album.type),
          size: 48,
          color: color,
        ),
      ),
    );
  }

  IconData _getAlbumIcon(AlbumType type) {
    switch (type) {
      case AlbumType.custom:
        return Icons.folder_outlined;
      case AlbumType.favorites:
        return Icons.favorite_outline;
      case AlbumType.recent:
        return Icons.access_time;
      case AlbumType.screenshots:
        return Icons.screenshot_outlined;
      case AlbumType.camera:
        return Icons.camera_alt_outlined;
      case AlbumType.downloads:
        return Icons.download_outlined;
      case AlbumType.shared:
        return Icons.share_outlined;
    }
  }

  Color _getAlbumColor(AlbumType type) {
    switch (type) {
      case AlbumType.custom:
        return context.accentColor;
      case AlbumType.favorites:
        return Colors.red;
      case AlbumType.recent:
        return Colors.orange;
      case AlbumType.screenshots:
        return Colors.purple;
      case AlbumType.camera:
        return Colors.teal;
      case AlbumType.downloads:
        return Colors.green;
      case AlbumType.shared:
        return context.accentColor;
    }
  }

  Widget _buildCreateAlbumCard() {
    return GestureDetector(
      onTap: _showCreateAlbumDialog,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: context.backgroundSecondary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: context.accentColor.withValues(alpha: 0.3),
            width: 2,
            style: BorderStyle.solid,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_circle_outline,
                size: 40,
                color: context.accentColor,
              ),
              const SizedBox(height: 8),
              Text(
                'Create Album',
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  color: context.accentColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
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
            'No albums yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
              fontFamily: 'ProductSans',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create albums to organize your files',
            style: TextStyle(
              fontSize: 14,
              color: context.textSecondary,
              fontFamily: 'ProductSans',
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showCreateAlbumDialog,
            icon: const Icon(Icons.add),
            label: const Text('Create Album'),
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

  void _openAlbum(Album album) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AlbumDetailScreen(albumId: album.id),
      ),
    );
  }

  void _showAlbumOptions(Album album) {
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
                      album.name,
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
                      label: 'Rename Album',
                      onTap: () {
                        Navigator.pop(context);
                        _showRenameAlbumDialog(album);
                      },
                    ),
                    _buildOptionTile(
                      icon: Icons.image_outlined,
                      label: 'Change Cover',
                      onTap: () {
                        Navigator.pop(context);
                        _showChangeCoverSheet(album);
                      },
                    ),
                    _buildOptionTile(
                      icon: Icons.delete_outline,
                      label: 'Delete Album',
                      color: AppColors.error,
                      onTap: () {
                        Navigator.pop(context);
                        _showDeleteAlbumDialog(album);
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
    required VoidCallback onTap,
    Color? color,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? AppColors.lightTextPrimary),
      title: Text(
        label,
        style: TextStyle(
          fontFamily: 'ProductSans',
          color: color ?? AppColors.lightTextPrimary,
        ),
      ),
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
    );
  }

  void _showCreateAlbumDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          'Create Album',
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
                labelText: 'Album Name',
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
                ToastUtils.showError('Please enter album name');
                return;
              }

              final album =
                  await ref.read(albumsNotifierProvider.notifier).createAlbum(
                        name: name,
                        description: descController.text.trim().isEmpty
                            ? null
                            : descController.text.trim(),
                      );

              if (!context.mounted) return;
              if (album != null) {
                Navigator.pop(context);
                ToastUtils.showSuccess('Album created');
              } else {
                ToastUtils.showError('Failed to create album');
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
    ).whenComplete(() {
      nameController.dispose();
      descController.dispose();
    });
  }

  void _showRenameAlbumDialog(Album album) {
    final nameController = TextEditingController(text: album.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          'Rename Album',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textPrimary,
          ),
        ),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: 'Album Name',
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
                ToastUtils.showError('Please enter album name');
                return;
              }

              final updated = await ref
                  .read(albumsNotifierProvider.notifier)
                  .updateAlbum(album.copyWith(name: name));

              if (!context.mounted) return;
              if (updated != null) {
                Navigator.pop(context);
                ToastUtils.showSuccess('Album renamed');
              } else {
                ToastUtils.showError('Failed to rename album');
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
    ).whenComplete(nameController.dispose);
  }

  void _showDeleteAlbumDialog(Album album) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          'Delete Album',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textPrimary,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${album.name}"? Files in this album will not be deleted.',
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
                  .read(albumsNotifierProvider.notifier)
                  .deleteAlbum(album.id);

              if (!context.mounted) return;
              Navigator.pop(context);
              if (deleted) {
                ToastUtils.showSuccess('Album deleted');
              } else {
                ToastUtils.showError('Failed to delete album');
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

  void _showChangeCoverSheet(Album album) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _ChangeCoverSheet(
        album: album,
        onCoverChanged: () {
          ref.invalidate(albumsNotifierProvider);
        },
      ),
    );
  }
}

/// Bottom sheet for changing album cover
class _ChangeCoverSheet extends ConsumerStatefulWidget {
  final Album album;
  final VoidCallback onCoverChanged;

  const _ChangeCoverSheet({
    required this.album,
    required this.onCoverChanged,
  });

  @override
  ConsumerState<_ChangeCoverSheet> createState() => _ChangeCoverSheetState();
}

class _ChangeCoverSheetState extends ConsumerState<_ChangeCoverSheet> {
  bool _isLoading = false;
  String? _selectedFileId;

  @override
  void initState() {
    super.initState();
    _selectedFileId = widget.album.coverImageId;
  }

  @override
  Widget build(BuildContext context) {
    final vaultFilesAsync = ref.watch(vaultNotifierProvider);
    final albumFilesAsync = ref.watch(filesInAlbumProvider(widget.album.id));

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
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
                  child: Text(
                    'Choose Album Cover',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimary,
                      fontFamily: 'ProductSans',
                    ),
                  ),
                ),
                if (_selectedFileId != null &&
                    _selectedFileId != widget.album.coverImageId)
                  ElevatedButton(
                    onPressed: _isLoading ? null : _saveCover,
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
                        : const Text(
                            'Save',
                            style: TextStyle(fontFamily: 'ProductSans'),
                          ),
                  ),
              ],
            ),
          ),
          // Image grid - show images from album first, then all images from vault
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
                // Get all image files
                final allImages =
                    allFiles.where((f) => f.isImage || f.isVideo).toList();

                // Get album files first
                final albumFiles = albumFilesAsync.value ?? [];
                final albumImages =
                    albumFiles.where((f) => f.isImage || f.isVideo).toList();

                // Combine with album images first
                final Set<String> albumImageIds =
                    albumImages.map((f) => f.id).toSet();
                final otherImages = allImages
                    .where((f) => !albumImageIds.contains(f.id))
                    .toList();

                final combinedImages = [...albumImages, ...otherImages];

                if (combinedImages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.image_not_supported_outlined,
                          size: 64,
                          color: context.textTertiary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No images available',
                          style: TextStyle(
                            fontFamily: 'ProductSans',
                            color: context.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add some images to your vault first',
                          style: TextStyle(
                            fontFamily: 'ProductSans',
                            fontSize: 12,
                            color: context.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (albumImages.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'From this album',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.textTertiary,
                            fontFamily: 'ProductSans',
                          ),
                        ),
                      ),
                    Expanded(
                      child: GridView.builder(
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
                        itemCount: combinedImages.length,
                        itemBuilder: (context, index) {
                          final file = combinedImages[index];
                          final isFromAlbum = index < albumImages.length;

                          // Add separator for "Other images" section
                          if (index == albumImages.length &&
                              albumImages.isNotEmpty) {
                            // This won't work in GridView, so we handle it differently
                          }

                          return _buildImageItem(file, isFromAlbum);
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageItem(VaultedFile file, bool isFromAlbum) {
    final isSelected = _selectedFileId == file.id;

    return GestureDetector(
      onTap: () => setState(() => _selectedFileId = file.id),
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
              child: file.isImage
                    ? Image.file(
                        File(file.vaultPath),
                        fit: BoxFit.cover,
                        cacheWidth: 200,
                        filterQuality: FilterQuality.low,
                        errorBuilder: (_, __, ___) => _buildPlaceholder(),
                      )
                  : _buildVideoPlaceholder(),
            ),
          ),
          // Selection indicator
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
          // Current cover indicator
          if (file.id == widget.album.coverImageId)
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Current',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontFamily: 'ProductSans',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey.withValues(alpha: 0.2),
      child: const Center(
        child: Icon(Icons.broken_image, color: Colors.grey),
      ),
    );
  }

  Widget _buildVideoPlaceholder() {
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

  Future<void> _saveCover() async {
    if (_selectedFileId == null) return;

    setState(() => _isLoading = true);

    final updated = await ref
        .read(albumsNotifierProvider.notifier)
        .updateAlbum(widget.album.copyWith(coverImageId: _selectedFileId));

    setState(() => _isLoading = false);

    if (updated != null) {
      widget.onCoverChanged();
      if (mounted) {
        Navigator.pop(context);
        ToastUtils.showSuccess('Album cover updated');
      }
    } else {
      ToastUtils.showError('Failed to update cover');
    }
  }
}
