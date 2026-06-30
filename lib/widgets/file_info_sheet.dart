import 'package:flutter/material.dart';
import '../models/vaulted_file.dart';
import '../themes/app_colors.dart';

/// Shared file-info bottom sheet. Renders the common rows every viewer shows
/// (Name, Type, Size, Added, Last Viewed) plus an Encryption section with the
/// algorithm / salt / iterations / IV when the file is encrypted. Callers pass
/// [extraRows] for screen-specific data (Pages, Tags, Views).
class FileInfoSheet {
  static Future<void> show(
    BuildContext context,
    VaultedFile file, {
    String? title,
    String? typeLabel,
    List<(String, String)>? extraRows,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.75,
        ),
        decoration: BoxDecoration(
          color: ctx.backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: ctx.dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  title ?? 'File Information',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: ctx.textPrimary,
                    fontFamily: 'ProductSans',
                  ),
                ),
                const SizedBox(height: 16),
                _row(ctx, 'Name', file.originalName),
                _row(ctx, 'Type', typeLabel ?? file.extension.toUpperCase()),
                _row(ctx, 'Size', file.formattedSize),
                _row(ctx, 'Added', file.formattedDateAdded),
                if (file.lastViewed != null)
                  _row(ctx, 'Last Viewed', _formatDateTime(file.lastViewed!)),
                const _SectionDivider(label: 'Encryption'),
                _row(
                  ctx,
                  'Status',
                  file.isEncrypted ? 'Encrypted' : 'Not encrypted',
                ),
                if (file.isEncrypted) ...[
                  _row(
                    ctx,
                    'Algorithm',
                    (file.encryptionAlgorithm?.displayName) ?? 'AES-256',
                  ),
                  if (file.kdfIterations != null)
                    _row(ctx, 'Iterations', '${file.kdfIterations}'),
                  if (file.keyDerivationSalt != null)
                    _row(ctx, 'Key Salt', file.keyDerivationSalt!),
                  if (file.encryptionIv != null)
                    _row(ctx, 'IV', file.encryptionIv!),
                ],
                if (extraRows != null)
                  for (final r in extraRows) _row(ctx, r.$1, r.$2),
                SizedBox(height: MediaQuery.of(ctx).padding.bottom + 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: context.textTertiary,
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDateTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.day}/${d.month}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }
}

class _SectionDivider extends StatelessWidget {
  final String label;
  const _SectionDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'ProductSans',
          fontWeight: FontWeight.w600,
          color: context.textSecondary,
          fontSize: 13,
        ),
      ),
    );
  }
}
