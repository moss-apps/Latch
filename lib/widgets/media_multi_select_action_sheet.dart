import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../themes/app_colors.dart';
import 'sheet_action_row.dart';

/// Contextual bottom sheet for bulk actions on selected files. Mirrors the
/// single-file sheet: flat action list, delete isolated at the bottom, cancel
/// as a quiet footer action.
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
    final rows = <Widget>[
      if (onFavorite != null)
        SheetActionRow(
          icon: Icons.favorite_outline,
          label: 'Favorite',
          onTap: onFavorite,
        ),
      if (onShare != null)
        SheetActionRow(
          icon: Icons.download_outlined,
          label: 'Export',
          onTap: onShare,
        ),
      if (onUnhide != null)
        SheetActionRow(
          icon: Icons.visibility_outlined,
          label: 'Unhide',
          onTap: onUnhide,
        ),
      if (onTags != null)
        SheetActionRow(
          icon: Icons.label_outline,
          label: 'Tags',
          onTap: onTags,
        ),
      if (onAddToAlbum != null)
        SheetActionRow(
          icon: Icons.folder_outlined,
          label: 'Add to album',
          onTap: onAddToAlbum,
        ),
    ];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              '$fileCount file${fileCount == 1 ? '' : 's'} selected',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
                fontFamily: 'ProductSans',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 10),
          ...rows,
          if (onDelete != null) ...[
            if (rows.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
                child: Divider(height: 1, color: context.dividerColor),
              ),
            SheetActionRow(
              icon: Icons.delete_outline,
              label: 'Delete',
              onTap: onDelete,
              isDestructive: true,
            ),
          ],
          if (onCancelSelection != null)
            Center(
              child: TextButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  Navigator.pop(context);
                  onCancelSelection!();
                },
                child: Text(
                  'Cancel selection',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: context.textSecondary,
                    fontFamily: 'ProductSans',
                  ),
                ),
              ),
            ),
          SizedBox(height: 8 + MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}
