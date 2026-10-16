import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/vaulted_file.dart';
import '../../providers/vault_providers.dart';
import '../../themes/app_colors.dart';
import '../encrypted_thumbnail.dart';

/// Isolates preview privacy, loading and file-type fallbacks from selection UI.
class GalleryFileThumbnail extends ConsumerWidget {
  const GalleryFileThumbnail({super.key, required this.file});
  final VaultedFile file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!file.isEncrypted &&
        (ref.watch(vaultSettingsProvider).value?.hideUnencryptedThumbnails ??
            false)) {
      return _placeholder(context);
    }
    if (file.isImage) {
      if (file.isEncrypted) return EncryptedThumbnail(file: file);
      return Image.file(File(file.vaultPath),
          fit: BoxFit.cover,
          cacheWidth: 300,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, synchronous) =>
              synchronous || frame != null
                  ? child
                  : const _LoadingPlaceholder(),
          errorBuilder: (context, error, stack) => _placeholder(context));
    }
    if (file.isVideo) {
      return Stack(fit: StackFit.expand, children: [
        if (file.isEncrypted) EncryptedThumbnail(file: file),
        Container(
            color: file.isEncrypted ? Colors.black26 : Colors.black87,
            child: const Center(
                child: Icon(Icons.play_circle_outline,
                    size: 48, color: Colors.white70))),
      ]);
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) {
    final (icon, color) = switch (file.type) {
      VaultedFileType.image => (Icons.image, context.accentColor),
      VaultedFileType.video => (Icons.videocam, Colors.red),
      VaultedFileType.song => (Icons.music_note, Colors.purple),
      VaultedFileType.document => file.metadata?['noteId'] != null
          ? (Icons.sticky_note_2, Colors.amber)
          : _document(context),
      VaultedFileType.other => (Icons.insert_drive_file, Colors.grey),
    };
    return Container(
        color: color.withValues(alpha: 0.1),
        child: Padding(
            padding: EdgeInsets.only(bottom: file.hasTags ? 52 : 28),
            child: Center(child: Icon(icon, size: 36, color: color))));
  }

  (IconData, Color) _document(BuildContext context) =>
      switch (file.extension.toLowerCase()) {
        'pdf' => (Icons.picture_as_pdf, Colors.red),
        'doc' || 'docx' => (Icons.description, context.accentColor),
        'xls' || 'xlsx' => (Icons.table_chart, Colors.green),
        'ppt' || 'pptx' => (Icons.slideshow, Colors.orange),
        'txt' => (Icons.text_snippet, Colors.grey),
        _ => (Icons.insert_drive_file, context.accentColor),
      };
}

class _LoadingPlaceholder extends StatelessWidget {
  const _LoadingPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
      color: Colors.grey.shade200,
      child: const Center(
          child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))));
}
