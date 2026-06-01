import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../themes/app_colors.dart';

/// A contextual bottom sheet shown when performing bulk actions on selected files.
/// Consolidates multi-select operations into a clean quick-action grid.
class MediaMultiSelectActionSheet extends StatelessWidget {
  final int fileCount;
  final VoidCallback? onShare;
  final VoidCallback? onDelete;
  final VoidCallback? onFavorite;
  final VoidCallback? onTags;
  final VoidCallback? onAddToAlbum;
  final VoidCallback? onUnhide;
  final VoidCallback? onCancelSelection;

  const MediaMultiSelectActionSheet({
    super.key,
    required this.fileCount,
    this.onShare,
    this.onDelete,
    this.onFavorite,
    this.onTags,
    this.onAddToAlbum,
    this.onUnhide,
    this.onCancelSelection,
  });

  static Future<void> show(
    BuildContext context, {
    required int fileCount,
    VoidCallback? onShare,
    VoidCallback? onDelete,
    VoidCallback? onFavorite,
    VoidCallback? onTags,
    VoidCallback? onAddToAlbum,
    VoidCallback? onUnhide,
    VoidCallback? onCancelSelection,
  }) {
    HapticFeedback.mediumImpact();
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => MediaMultiSelectActionSheet(
        fileCount: fileCount,
        onShare: onShare,
        onDelete: onDelete,
        onFavorite: onFavorite,
        onTags: onTags,
        onAddToAlbum: onAddToAlbum,
        onUnhide: onUnhide,
        onCancelSelection: onCancelSelection,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          const SizedBox(height: 20),
          // Header icon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: context.accentColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.folder_copy_outlined,
              size: 28,
              color: context.accentColor,
            ),
          ),
          const SizedBox(height: 12),
          // Title
          Text(
            '$fileCount file${fileCount == 1 ? '' : 's'} selected',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
              fontFamily: 'ProductSans',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose an action',
            style: TextStyle(
              fontSize: 13,
              color: context.textSecondary,
              fontFamily: 'ProductSans',
            ),
          ),
          const SizedBox(height: 24),
          // Primary action row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (onFavorite != null)
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.favorite_outline,
                      label: 'Favorite',
                      color: context.accentColor,
                      onTap: onFavorite,
                    ),
                  ),
                if (onShare != null)
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.share,
                      label: 'Share',
                      color: context.accentColor,
                      onTap: onShare,
                    ),
                  ),
                if (onDelete != null)
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.delete_outline,
                      label: 'Delete',
                      color: AppColors.error,
                      onTap: onDelete,
                    ),
                  ),
                if (onUnhide != null)
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.visibility_outlined,
                      label: 'Unhide',
                      color: context.accentColor,
                      onTap: onUnhide,
                    ),
                  ),
              ],
            ),
          ),
          // Secondary action row
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (onTags != null)
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.label_outline,
                      label: 'Tags',
                      color: context.accentColor,
                      onTap: onTags,
                    ),
                  ),
                if (onAddToAlbum != null)
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.folder_outlined,
                      label: 'Album',
                      color: context.accentColor,
                      onTap: onAddToAlbum,
                    ),
                  ),
                if (onCancelSelection != null)
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.close,
                      label: 'Cancel',
                      color: context.textSecondary,
                      onTap: onCancelSelection,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: 16 + MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
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
