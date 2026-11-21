import 'package:flutter/material.dart';
import '../models/note.dart';
import '../themes/app_colors.dart';
import '../utils/note_text.dart';

class NoteCard extends StatelessWidget {
  final Note note;
  final String? preview;
  final bool isGrid;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onTogglePin;
  final VoidCallback? onDelete;
  final bool isSelected;
  final bool isSelectionMode;

  const NoteCard({
    super.key,
    required this.note,
    this.preview,
    this.isGrid = true,
    this.onTap,
    this.onLongPress,
    this.onTogglePin,
    this.onDelete,
    this.isSelected = false,
    this.isSelectionMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final body = note.isEncrypted ? '' : preview ?? '';
    final content = notePreviewText(body, isMarkdown: note.isMarkdown);
    final title =
        deriveNoteTitle(note.title, body, isMarkdown: note.isMarkdown);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: isSelected
                ? context.accentColor.withValues(alpha: 0.12)
                : context.surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? context.accentColor
                  : context.dividerColor.withValues(alpha: 0.8),
              // Keep the border width constant so selecting a note does not
              // nudge the card contents by a fraction of a pixel.
              width: 1.5,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 10, 0),
              child: isGrid
                  ? _buildGridCard(context, title, content)
                  : _buildListCard(context, title, content),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridCard(BuildContext context, String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTitleRow(context, title),
        if (content.isNotEmpty) ...[
          const SizedBox(height: 7),
          Expanded(
            child: Text(
              content,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'GoogleSansFlex',
                fontSize: 13.5,
                height: 1.4,
                color: context.textSecondary,
              ),
            ),
          ),
        ] else
          const Spacer(),
        const SizedBox(height: 6),
        _buildFooter(context),
      ],
    );
  }

  Widget _buildListCard(BuildContext context, String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTitleRow(context, title),
        if (content.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'GoogleSansFlex',
              fontSize: 13.5,
              height: 1.4,
              color: context.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: 8),
        _buildFooter(context),
      ],
    );
  }

  Widget _buildTitleRow(BuildContext context, String title) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            title.isEmpty ? 'Untitled note' : title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'GoogleSansFlex',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.25,
              color: context.textPrimary,
            ),
          ),
        ),
        if (isSelectionMode) ...[
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              size: 20,
              color: isSelected ? context.accentColor : context.textTertiary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    // Reserve the menu row height in selection mode too so the card (and the
    // metadata inside it) does not shift when a note is long-pressed.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      child: Row(
        children: [
          Flexible(
            child: Text(
              formatNoteDate(note.updatedAt),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'GoogleSansFlex',
                fontSize: 11.5,
                color: context.textTertiary,
              ),
            ),
          ),
          if (note.isPinned)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(Icons.push_pin, size: 13, color: context.accentColor),
            ),
          if (note.isEncrypted)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(
                Icons.lock_outline,
                size: 13,
                color: context.textTertiary,
              ),
            ),
          if (note.isMarkdown)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(
                Icons.text_snippet_outlined,
                size: 13,
                color: context.textTertiary,
              ),
            ),
          if (!isSelectionMode && (onTogglePin != null || onDelete != null))
            _buildMenu(context),
        ],
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        iconSize: 18,
        tooltip: 'Note actions',
        color: context.surfaceColor,
        surfaceTintColor: Colors.transparent,
        icon: Icon(Icons.more_horiz, color: context.textTertiary),
        onSelected: (value) {
          if (value == 'pin') onTogglePin?.call();
          if (value == 'delete') onDelete?.call();
        },
        itemBuilder: (context) => [
          if (onTogglePin != null)
            PopupMenuItem(
              value: 'pin',
              child: Row(
                children: [
                  Icon(
                    note.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                    size: 18,
                    color: context.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      note.isPinned ? 'Unpin note' : 'Pin note',
                      style: TextStyle(
                        fontFamily: 'GoogleSansFlex',
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (onDelete != null)
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Delete note',
                      style: TextStyle(
                        fontFamily: 'GoogleSansFlex',
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
