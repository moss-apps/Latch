import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vaulted_file.dart';
import '../providers/vault_providers.dart';
import '../screens/document_viewer_screen.dart';
import '../screens/media_viewer_screen.dart';
import '../screens/song_player_screen.dart';
import '../themes/app_colors.dart';
import '../utils/toast_utils.dart';
import 'crypto_isolate_pool.dart';

/// Centralized, atomic file opener.
///
/// Opening an encrypted file runs in distinct, user-visible phases driven by
/// real signals, not a fake 0–100% bar:
/// - **Preparing key…** — indeterminate; covers the un-killable PBKDF2 key
///   derivation (the historically slow step). Explains why nothing moves yet.
/// - **Decrypting…** — stays indeterminate until the isolate emits byte
///   progress, then flips to a determinate bar. Small files never show a
///   lying 0%; they resolve during indeterminate.
/// - **Opening…** — indeterminate, while the viewer route is pushed.
///
/// Cancel works in every phase via [CancelToken]: it kills the decrypt isolate
/// if running (safe — the worker writes to `.tmp` and only renames on success;
/// orphaned temps are reaped by VaultService.cleanupTemp), and flips a flag
/// checked at stage boundaries so a cancel during key derivation still unblocks
/// the UI instantly. The derivation itself finishes on its background isolate
/// and its result is discarded.
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

    final needsDecryption = file.isEncrypted && file.encryptionIv != null;
    final token = CancelToken();
    final status = ValueNotifier<_OpenStatus>(
      _OpenStatus(needsDecryption ? 'Preparing key…' : 'Opening…'),
    );
    BuildContext? sheetContext;
    Timer? sheetTimer;
    var sheetShown = false;

    void hideSheet() {
      sheetTimer?.cancel();
      if (sheetShown && sheetContext?.mounted == true) {
        Navigator.pop(sheetContext!);
      }
      sheetShown = false;
    }

    void requestCancel() {
      token.cancel();
      hideSheet();
    }

    void showSheet() {
      if (sheetShown || !context.mounted) return;
      sheetShown = true;
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        showDragHandle: true,
        backgroundColor: context.surfaceColor,
        builder: (ctx) {
          sheetContext = ctx;
          return _OpenSheet(
            file: file,
            status: status,
            onCancel: requestCancel,
          );
        },
      );
    }

    try {
      final noteId = file.metadata?['noteId'] as String?;
      if (noteId != null) {
        if (onOpenNote != null) {
          onOpenNote(noteId);
        } else {
          onUnsupported?.call();
        }
        return;
      }

      final passwordId = file.metadata?['passwordId'] as String?;
      if (passwordId != null) {
        if (onOpenPassword != null) {
          onOpenPassword(passwordId);
        } else {
          onUnsupported?.call();
        }
        return;
      }

      final vaultService = ref.read(vaultServiceProvider);

      // Encrypted files take noticeable time, so show the sheet immediately in
      // the prepare phase. Plain files usually open almost instantly, so defer
      // slightly to avoid a flash.
      if (needsDecryption) {
        showSheet();
      } else {
        sheetTimer = Timer(const Duration(milliseconds: 150), showSheet);
      }

      File? decryptedFile;
      if (needsDecryption) {
        decryptedFile = await vaultService.getVaultedFile(
          file.id,
          onProgress: (processed, total) {
            // First byte-progress event flips prepare -> decrypt and turns the
            // bar determinate. Until then it stays honestly indeterminate.
            if (total > 0 && !token.isCancelled) {
              status.value = _OpenStatus(
                'Decrypting…',
                progress: processed / total,
              );
            }
          },
          cancelToken: token,
        );

        if (token.isCancelled) return;

        if (decryptedFile == null || !await decryptedFile.exists()) {
          throw Exception('Failed to decrypt ${file.originalName}');
        }
      }

      if (!context.mounted) {
        hideSheet();
        return;
      }

      status.value = const _OpenStatus('Opening…');

      // Plain files defer the sheet 150ms to avoid a flash, but push awaits
      // until the route is popped — cancel the pending timer or it surfaces
      // the loading sheet on top of the already-opened viewer.
      sheetTimer?.cancel();

      await _pushViewer(
        context,
        file,
        currentFiles: currentFiles,
        decryptedFile: decryptedFile,
        onUnsupported: onUnsupported,
      );

      hideSheet();

      unawaited(vaultService.updateFile(file.markViewed()));
    } catch (e, st) {
      debugPrint('Error opening file: $e\n$st');
      hideSheet();
      if (!token.isCancelled) {
        ToastUtils.showError('Failed to open ${file.originalName}');
      }
    } finally {
      status.dispose();
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

/// Progress snapshot for the open sheet. [progress] is null while the active
/// phase can't report a fraction (honest indeterminate).
class _OpenStatus {
  final String phase;
  final double? progress;

  const _OpenStatus(this.phase, {this.progress});
}

class _OpenSheet extends StatelessWidget {
  final VaultedFile file;
  final ValueListenable<_OpenStatus> status;
  final VoidCallback onCancel;

  const _OpenSheet({
    required this.file,
    required this.status,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.accentColor;
    final typeColor = FileTypeColors.colorForType(file.type, accent: accent);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
        child: ValueListenableBuilder<_OpenStatus>(
          valueListenable: status,
          builder: (_, s, __) {
            final pct = s.progress == null
                ? null
                : (s.progress!.clamp(0.0, 1.0) * 100).round();
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        FileTypeColors.iconForType(file.type),
                        color: typeColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            file.originalName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'ProductSans',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            s.phase,
                            style: TextStyle(
                              fontFamily: 'ProductSans',
                              fontSize: 13,
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: s.progress,
                        minHeight: 6,
                        valueColor: AlwaysStoppedAnimation(accent),
                        backgroundColor: accent.withValues(alpha: 0.12),
                      ),
                    ),
                    if (pct != null) ...[
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '$pct%',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontFamily: 'ProductSans',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: context.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onCancel,
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
