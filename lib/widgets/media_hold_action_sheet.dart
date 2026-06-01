import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/vaulted_file.dart';
import '../themes/app_colors.dart';

/// A contextual bottom sheet shown when long-pressing a media file.
/// Provides quick one-tap actions without entering selection mode.
class MediaHoldActionSheet extends StatelessWidget {
  final VaultedFile file;
  final VoidCallback? onFavorite;
  final VoidCallback? onShare;
  final VoidCallback? onDelete;
  final VoidCallback? onInfo;
  final VoidCallback? onSelect;
  final VoidCallback? onOpen;
  final VoidCallback? onTags;
  final VoidCallback? onExport;
  final VoidCallback? onAddToAlbum;

  const MediaHoldActionSheet({
    super.key,
    required this.file,
    this.onFavorite,
    this.onShare,
    this.onDelete,
    this.onInfo,
    this.onSelect,
    this.onOpen,
    this.onTags,
    this.onExport,
    this.onAddToAlbum,
  });

  static Future<void> show(
    BuildContext context, {
    required VaultedFile file,
    VoidCallback? onFavorite,
    VoidCallback? onShare,
    VoidCallback? onDelete,
    VoidCallback? onInfo,
    VoidCallback? onSelect,
    VoidCallback? onOpen,
    VoidCallback? onTags,
    VoidCallback? onExport,
    VoidCallback? onAddToAlbum,
  }) {
    HapticFeedback.mediumImpact();
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => MediaHoldActionSheet(
        file: file,
        onFavorite: onFavorite,
        onShare: onShare,
        onDelete: onDelete,
        onInfo: onInfo,
        onSelect: onSelect,
        onOpen: onOpen,
        onTags: onTags,
        onExport: onExport,
        onAddToAlbum: onAddToAlbum,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryActions = _buildPrimaryActions(context);
    final secondaryActions = _buildSecondaryActions(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.borderColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // Preview / Icon
          _buildPreview(context),
          const SizedBox(height: 8),
          // File name
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              file.originalName,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
                fontFamily: 'ProductSans',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 4),
          // Meta info
          Text(
            '${file.extension.toUpperCase()} • ${file.formattedSize}',
            style: TextStyle(
              fontSize: 13,
              color: context.textSecondary,
              fontFamily: 'ProductSans',
            ),
          ),
          const SizedBox(height: 20),
          // Primary action row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: primaryActions,
            ),
          ),
          // Secondary action row
          if (secondaryActions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: secondaryActions,
              ),
            ),
          ],
          SizedBox(height: 16 + MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    final size = 100.0;
    if (file.isImage && File(file.vaultPath).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.file(
          File(file.vaultPath),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildFallbackPreview(context),
        ),
      );
    }
    return _buildFallbackPreview(context);
  }

  Widget _buildFallbackPreview(BuildContext context) {
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
        color = context.accentColor;
        break;
      case VaultedFileType.other:
        icon = Icons.insert_drive_file;
        color = Colors.grey;
        break;
    }
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, size: 40, color: color),
    );
  }

  List<Widget> _buildPrimaryActions(BuildContext context) {
    return [
      Expanded(child: _ActionButton(
        icon: file.isFavorite ? Icons.favorite : Icons.favorite_outline,
        label: file.isFavorite ? 'Unfavorite' : 'Favorite',
        color: file.isFavorite ? Colors.red : context.accentColor,
        onTap: onFavorite,
      )),
      Expanded(child: _ActionButton(
        icon: Icons.share,
        label: 'Share',
        color: context.accentColor,
        onTap: onShare,
      )),
      Expanded(child: _ActionButton(
        icon: Icons.delete_outline,
        label: 'Delete',
        color: AppColors.error,
        onTap: onDelete,
      )),
      Expanded(child: _ActionButton(
        icon: Icons.info_outline,
        label: 'Info',
        color: context.textSecondary,
        onTap: onInfo,
      )),
      Expanded(child: _ActionButton(
        icon: Icons.check_circle_outline,
        label: 'Select',
        color: context.accentColor,
        onTap: onSelect,
      )),
    ];
  }

  List<Widget> _buildSecondaryActions(BuildContext context) {
    final items = <Widget>[];

    if (onTags != null) {
      items.add(Expanded(child: _ActionButton(
        icon: Icons.label_outline,
        label: 'Tags',
        color: context.accentColor,
        onTap: onTags,
      )));
    }

    if (onAddToAlbum != null) {
      items.add(Expanded(child: _ActionButton(
        icon: Icons.folder_outlined,
        label: 'Album',
        color: context.accentColor,
        onTap: onAddToAlbum,
      )));
    }

    if (onOpen != null) {
      items.add(Expanded(child: _ActionButton(
        icon: Icons.open_in_new,
        label: 'Open',
        color: context.accentColor,
        onTap: onOpen,
      )));
    }

    if (onExport != null) {
      items.add(Expanded(child: _ActionButton(
        icon: Icons.download_outlined,
        label: 'Export',
        color: context.accentColor,
        onTap: onExport,
      )));
    }

    return items;
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        onTap?.call();
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: context.textPrimary,
                fontFamily: 'ProductSans',
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
