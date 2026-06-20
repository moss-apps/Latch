import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vaulted_file.dart';
import '../providers/vault_providers.dart';
import '../screens/document_viewer_screen.dart';
import '../screens/media_viewer_screen.dart';
import '../screens/song_player_screen.dart';
import '../themes/app_colors.dart';
import '../utils/toast_utils.dart';

/// Centralized, atomic file opener.
///
/// Shows a single loading indicator while the file is being prepared (e.g.
/// decrypted) and then pushes the correct viewer screen. Only one file can be
/// opened at a time so repeated taps don't stack routes.
class FileOpenService {
  static bool _isOpening = false;

  /// Open a [file] from the vault.
  ///
  /// [currentFiles] is the list of files currently visible to the user; it is
  /// used to build the swipeable gallery context for images and videos.
  /// [onUnsupported] is called when the file has no built-in viewer.
  /// [onOpenNote] is called when the vault entry represents a note.
  /// [onOpenPassword] is called when the vault entry represents a password.
  static Future<void> open(
    BuildContext context,
    WidgetRef ref,
    VaultedFile file, {
    required List<VaultedFile> currentFiles,
    VoidCallback? onUnsupported,
    ValueChanged<String>? onOpenNote,
    ValueChanged<String>? onOpenPassword,
  }) async {
    if (_isOpening) return;
    if (!context.mounted) return;

    _isOpening = true;

    BuildContext? overlayContext;
    Timer? overlayTimer;
    var overlayShown = false;

    void showOverlay() {
      if (overlayShown || !context.mounted) return;
      overlayShown = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (ctx) {
          overlayContext = ctx;
          return PopScope(
            canPop: false,
            child: AlertDialog(
              backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
              content: Row(
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(ctx.accentColor),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Text(
                      'Opening ${file.originalName}...',
                      style: const TextStyle(fontFamily: 'ProductSans'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    void hideOverlay() {
      overlayTimer?.cancel();
      if (overlayShown && overlayContext?.mounted == true) {
        Navigator.pop(overlayContext!);
        overlayShown = false;
        overlayContext = null;
      }
    }

    try {
      final noteId = file.metadata?['noteId'] as String?;
      if (noteId != null) {
        hideOverlay();
        if (onOpenNote != null) {
          onOpenNote(noteId);
        } else {
          onUnsupported?.call();
        }
        return;
      }

      final passwordId = file.metadata?['passwordId'] as String?;
      if (passwordId != null) {
        hideOverlay();
        if (onOpenPassword != null) {
          onOpenPassword(passwordId);
        } else {
          onUnsupported?.call();
        }
        return;
      }

      final vaultService = ref.read(vaultServiceProvider);
      final needsDecryption = file.isEncrypted && file.encryptionIv != null;

      // Encrypted files are likely to take a noticeable amount of time, so
      // show the indicator immediately. Plain files may open almost instantly,
      // so defer the overlay slightly to avoid a flash.
      if (needsDecryption) {
        showOverlay();
      } else {
        overlayTimer = Timer(const Duration(milliseconds: 150), showOverlay);
      }

      File? decryptedFile;
      if (needsDecryption) {
        decryptedFile = await vaultService.getVaultedFile(file.id);
        if (decryptedFile == null || !await decryptedFile.exists()) {
          throw Exception('Failed to decrypt ${file.originalName}');
        }
      }

      if (!context.mounted) {
        hideOverlay();
        return;
      }

      hideOverlay();

      await _pushViewer(
        context,
        file,
        currentFiles: currentFiles,
        decryptedFile: decryptedFile,
        onUnsupported: onUnsupported,
      );

      unawaited(vaultService.updateFile(file.markViewed()));
    } catch (e, st) {
      debugPrint('Error opening file: $e\n$st');
      hideOverlay();
      ToastUtils.showError('Failed to open ${file.originalName}');
    } finally {
      _isOpening = false;
    }
  }

  static Future<void> _pushViewer(
    BuildContext context,
    VaultedFile file, {
    required List<VaultedFile> currentFiles,
    File? decryptedFile,
    VoidCallback? onUnsupported,
  }) async {
    if (file.isImage || file.isVideo) {
      final viewerFiles =
          currentFiles.where((f) => f.isImage || f.isVideo).toList();
      final startIndex = viewerFiles.indexWhere((f) => f.id == file.id);

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MediaViewerScreen(
            initialFile: file,
            files: viewerFiles.isNotEmpty ? viewerFiles : [file],
            initialIndex: startIndex >= 0 ? startIndex : 0,
            initialDecryptedFile: decryptedFile,
          ),
        ),
      );
    } else if (file.isSong) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SongPlayerScreen(
            file: file,
            decryptedFile: decryptedFile,
          ),
        ),
      );
    } else if (file.isDocument) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DocumentViewerScreen(
            file: file,
            decryptedFile: decryptedFile,
          ),
        ),
      );
    } else {
      onUnsupported?.call();
    }
  }
}
