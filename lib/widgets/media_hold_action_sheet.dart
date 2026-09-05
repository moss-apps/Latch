import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/vaulted_file.dart';
import '../themes/app_colors.dart';
import 'encrypted_thumbnail.dart';
import 'sheet_action_row.dart';

/// Contextual bottom sheet for a single vaulted file. Preview header with
/// inline favorite/info toggles, then a flat action list ordered by frequency.
/// Delete is destructive and isolated at the bottom.
class MediaHoldActionSheet extends StatelessWidget {
  final VaultedFile file;
  final VoidCallback? onFavorite;
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
    final rows = <Widget>[
      if (onOpen != null)
        SheetActionRow(
          icon: Icons.open_in_new,
          label: 'Open',
          onTap: onOpen,
        ),
      if (onExport != null)
        SheetActionRow(
          icon: Icons.download_outlined,
          label: 'Export',
          onTap: onExport,
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
      if (onSelect != null)
        SheetActionRow(
          icon: Icons.check_circle_outline,
          label: 'Select',
          onTap: onSelect,
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
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
            child: Row(
              children: [
                _buildPreview(context),
                const SizedBox(width: 14),
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
                      const SizedBox(height: 3),
                      Text(
                        '${file.type.displayName} \u2022 ${file.formattedSize} \u2022 ${file.formattedDateAdded}',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.textSecondary,
                          fontFamily: 'ProductSans',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (onInfo != null)
                  _HeaderIconButton(
                    icon: Icons.info_outline,
                    tooltip: 'File info',
                    onTap: onInfo,
                  ),
                if (onFavorite != null)
                  _HeaderIconButton(
                    icon:
                        file.isFavorite ? Icons.favorite : Icons.favorite_outline,
                    tooltip: file.isFavorite ? 'Unfavorite' : 'Favorite',
                    color: file.isFavorite ? Colors.red : null,
                    onTap: onFavorite,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
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
          SizedBox(height: 12 + MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    const size = 56.0;
    if (file.isImage) {
      if (file.isEncrypted) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: size,
            height: size,
            child: EncryptedThumbnail(file: file),
          ),
        );
      }
      if (File(file.vaultPath).existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            File(file.vaultPath),
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildFallbackPreview(context),
          ),
        );
      }
    }
    return _buildFallbackPreview(context);
  }

  Widget _buildFallbackPreview(BuildContext context) {
    final color = FileTypeColors.colorForType(file.type,
        accent: context.accentColor);
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(FileTypeColors.iconForType(file.type),
          size: 24, color: color),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback? onTap;

  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap != null ? 1 : 0.4,
      child: IconButton(
        onPressed: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                Navigator.pop(context);
                onTap!();
              },
        icon: Icon(icon, size: 22),
        color: color ?? context.textSecondary,
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        padding: EdgeInsets.zero,
      ),
    );
  }
}
