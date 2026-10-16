import 'package:flutter/material.dart';
import 'vaulted_file.dart';

enum VaultCategory { all, images, videos, songs, docs }

extension VaultCategoryX on VaultCategory {
  VaultedFileType? get filterType => switch (this) {
        VaultCategory.all => null,
        VaultCategory.images => VaultedFileType.image,
        VaultCategory.videos => VaultedFileType.video,
        VaultCategory.songs => VaultedFileType.song,
        VaultCategory.docs => VaultedFileType.document,
      };

  IconData get icon => switch (this) {
        VaultCategory.all => Icons.grid_view_rounded,
        VaultCategory.images => Icons.image_outlined,
        VaultCategory.videos => Icons.videocam_outlined,
        VaultCategory.songs => Icons.music_note_outlined,
        VaultCategory.docs => Icons.description_outlined,
      };

  String get label => switch (this) {
        VaultCategory.all => 'All',
        VaultCategory.images => 'Images',
        VaultCategory.videos => 'Videos',
        VaultCategory.songs => 'Songs',
        VaultCategory.docs => 'Docs',
      };
}
