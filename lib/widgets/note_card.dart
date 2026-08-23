import 'package:flutter/material.dart';
import '../models/note.dart';
import '../themes/app_colors.dart';

class NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isSelected;
  final bool isSelectionMode;

  const NoteCard({
    super.key,
    required this.note,
    this.onTap,
    this.onLongPress,
    this.isSelected = false,
    this.isSelectionMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      selected: isSelected,
      selectedTileColor: context.accentColor.withValues(alpha: 0.10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Row(
        children: [
          if (note.isPinned)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                Icons.push_pin,
                size: 14,
                color: context.accentColor,
              ),
            ),
          Expanded(
            child: Text(
              note.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'ProductSans',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        _formatDate(note.updatedAt),
        style: TextStyle(
          fontFamily: 'ProductSans',
          fontSize: 12,
          color: context.textTertiary,
        ),
      ),
      trailing: isSelectionMode
          ? Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              size: 20,
              color: isSelected ? context.accentColor : context.textTertiary,
            )
          : note.isEncrypted
              ? Icon(Icons.lock_outline,
                  size: 15, color: context.textTertiary)
              : note.isMarkdown
                  ? Icon(Icons.text_snippet,
                      size: 15, color: context.textTertiary)
                  : null,
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}
