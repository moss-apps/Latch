import 'package:flutter/material.dart';
import '../../themes/app_colors.dart';

/// Presentation only: picking and import jobs are owned by the coordinator.
class GalleryImportSheet extends StatelessWidget {
  const GalleryImportSheet({super.key, required this.actions});

  final Map<GalleryImportAction, VoidCallback> actions;

  @override
  Widget build(BuildContext context) => Container(
        height: MediaQuery.sizeOf(context).height * 0.57,
        decoration: BoxDecoration(
            color: context.backgroundColor,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24))),
        child: SafeArea(
          top: false,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
                child: Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: context.borderColor,
                        borderRadius: BorderRadius.circular(2)))),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text('Import Files',
                                style: TextStyle(
                                    fontFamily: 'ProductSans',
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: context.textPrimary))),
                        IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close)),
                      ]),
                      const SizedBox(height: 8),
                      Text('Hide files, with encryption chosen at import',
                          style: TextStyle(
                              fontFamily: 'ProductSans',
                              fontSize: 14,
                              color: context.textSecondary)),
                      for (final group in GalleryImportAction.groups) ...[
                        const SizedBox(height: 24),
                        Text(group.$1,
                            style: TextStyle(
                                fontFamily: 'ProductSans',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                                color: context.textTertiary)),
                        const SizedBox(height: 12),
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < 3; i++) ...[
                                if (i != 0) const SizedBox(width: 12),
                                Expanded(
                                    child: i < group.$2.length
                                        ? _tile(context, group.$2[i])
                                        : const SizedBox()),
                              ],
                            ]),
                      ],
                      const SizedBox(height: 24),
                    ]),
              ),
            ),
          ]),
        ),
      );

  Widget _tile(BuildContext context, GalleryImportAction action) {
    final (label, icon, tint) = action.presentation;
    final color = tint ?? context.accentColor;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: actions[action],
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.2))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ]),
        ),
      ),
    );
  }
}

enum GalleryImportAction {
  images,
  videos,
  media,
  photo,
  video,
  audio,
  songs,
  documents,
  files,
  folder;

  static const groups = [
    ('From Gallery', [images, videos, media]),
    ('From Camera', [photo, video, audio]),
    ('From File Manager', [songs, documents, files]),
    ('From Device', [folder]),
  ];

  (String, IconData, Color?) get presentation => switch (this) {
        images => ('Images', Icons.photo_library_outlined, null),
        videos => ('Videos', Icons.video_library_outlined, Colors.red),
        media => ('All Media', Icons.perm_media_outlined, Colors.purple),
        photo => ('Take Photo', Icons.camera_alt_outlined, Colors.teal),
        video => ('Record Video', Icons.videocam_outlined, Colors.orange),
        audio => ('Record Audio', Icons.mic_outlined, Colors.deepPurple),
        songs => ('Songs', Icons.music_note_outlined, Colors.purple),
        documents => ('Documents', Icons.description_outlined, Colors.green),
        files => ('Any Files', Icons.folder_zip_outlined, Colors.blueGrey),
        folder => (
            'Import Folder',
            Icons.drive_folder_upload_outlined,
            Colors.indigo
          ),
      };
}
