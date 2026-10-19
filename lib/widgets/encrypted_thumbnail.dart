import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/vaulted_file.dart';
import '../providers/vault_providers.dart';

class EncryptedThumbnail extends ConsumerStatefulWidget {
  final VaultedFile file;

  const EncryptedThumbnail({super.key, required this.file});

  @override
  ConsumerState<EncryptedThumbnail> createState() => _EncryptedThumbnailState();
}

class _EncryptedThumbnailState extends ConsumerState<EncryptedThumbnail> {
  Future<Uint8List?>? _future;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(vaultSettingsProvider);

    // Wait for the persisted setting before decrypting anything, otherwise a
    // hidden thumbnail would still be decrypted on first build.
    if (settings.isLoading && !settings.hasValue) {
      return const _ThumbLoading();
    }
    if (settings.value?.hideEncryptedThumbnails ?? false) {
      return _ThumbPlaceholder(type: widget.file.type);
    }

    _future ??= ref.read(vaultServiceProvider).getThumbnailBytes(widget.file);

    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _ThumbLoading();
        }
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return _ThumbPlaceholder(type: widget.file.type);
        }
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) return child;
            return const _ThumbLoading();
          },
          errorBuilder: (context, error, stackTrace) {
            debugPrint(
                'EncryptedThumbnail decode error: ${widget.file.originalName} - $error');
            return _ThumbPlaceholder(type: widget.file.type);
          },
        );
      },
    );
  }
}

class _ThumbLoading extends StatelessWidget {
  const _ThumbLoading();
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade200,
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _ThumbPlaceholder extends StatelessWidget {
  final VaultedFileType type;
  const _ThumbPlaceholder({required this.type});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    switch (type) {
      case VaultedFileType.image:
        icon = Icons.image;
        color = Colors.blueGrey;
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
        color = Colors.amber;
        break;
      case VaultedFileType.other:
        icon = Icons.insert_drive_file;
        color = Colors.grey;
        break;
    }
    return Container(
      color: Colors.grey.shade100,
      child: Center(child: Icon(icon, color: color)),
    );
  }
}
