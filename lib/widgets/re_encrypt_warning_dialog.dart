import 'package:flutter/material.dart';
import '../themes/app_colors.dart';

/// Dialog shown before re-encrypting the vault.
///
/// Warns the user that an interrupted re-encryption can leave encrypted
/// files in a corrupted/unrecoverable state, and surfaces a "More
/// information" entry point that opens a follow-up dialog explaining the
/// risk in detail.
///
/// Returns `true` if the user acknowledges the warning and wants to
/// continue, `false` (or `null` on dismiss) otherwise.
class ReEncryptWarningDialog extends StatelessWidget {
  final VoidCallback onContinue;
  final VoidCallback onCancel;

  const ReEncryptWarningDialog({
    super.key,
    required this.onContinue,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Re-Encryption Warning',
              style: TextStyle(
                fontFamily: 'ProductSans',
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
                fontSize: 20,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Re-encryption rewrites every encrypted file in your vault. If the process is interrupted — for example by a dead battery, app crash, force-stop, or running out of storage — some files may be left in a corrupted state and become permanently unrecoverable.',
            style: TextStyle(
              fontFamily: 'ProductSans',
              color: context.textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  color: AppColors.warning,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Make sure your device is charged, has enough free storage, and will not be interrupted before continuing.',
                    style: TextStyle(
                      fontFamily: 'ProductSans',
                      color: context.textPrimary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () => _showMoreInformationDialog(context),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(
                vertical: 8,
                horizontal: 12,
              ),
              decoration: BoxDecoration(
                color: context.accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: context.accentColor,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'More information',
                    style: TextStyle(
                      fontFamily: 'ProductSans',
                      color: context.accentColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: Text(
            'Cancel',
            style: TextStyle(
              fontFamily: 'ProductSans',
              color: context.textSecondary,
            ),
          ),
        ),
        FilledButton(
          onPressed: onContinue,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: const Text(
            'I Understand, Continue',
            style: TextStyle(fontFamily: 'ProductSans'),
          ),
        ),
      ],
    );
  }

  void _showMoreInformationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.shield_outlined, color: context.accentColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Why Can Re-Encryption Corrupt Files?',
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  fontWeight: FontWeight.bold,
                  color: context.textPrimary,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildExplanationItem(
                ctx,
                Icons.battery_alert,
                'Process interruption',
                'If the app is killed mid-write — by a low battery shutdown, a system kill, the user force-stopping it, or another app taking focus — the file on disk may end up partially rewritten. A partially rewritten file cannot be decrypted and is effectively lost.',
              ),
              const SizedBox(height: 16),
              _buildExplanationItem(
                ctx,
                Icons.sd_storage,
                'Storage running out',
                'Re-encryption needs roughly the same amount of free space as the encrypted files themselves, because each file is decrypted, re-encrypted, and rewritten. If storage fills up halfway through a file, the rewrite can fail and leave the file unreadable.',
              ),
              const SizedBox(height: 16),
              _buildExplanationItem(
                ctx,
                Icons.lock_reset,
                'Algorithm & key change',
                'Switching the algorithm or changing the KDF parameters produces a brand new ciphertext and a new IV for every file. If a single file fails to rewrite correctly while its index entry is updated, the vault will no longer know which key or IV to use for that file.',
              ),
              const SizedBox(height: 16),
              _buildExplanationItem(
                ctx,
                Icons.history,
                'Recovery is not guaranteed',
                'Latch keeps a recovery journal that lets it resume an interrupted re-encryption on the next launch, and it can roll back files that did not finish rewriting. However, if the journal itself is lost — for example due to storage corruption or an uninstall — any files that were caught mid-rewrite cannot be recovered.',
              ),
              const SizedBox(height: 16),
              _buildExplanationItem(
                ctx,
                Icons.backup_outlined,
                'Recommended safeguards',
                'Before continuing: charge your device, ensure you have at least 2× the size of your vault in free storage, keep the app in the foreground, and avoid switching apps until the process finishes. A full backup of the vault folder is strongly recommended.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Got it',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: context.accentColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExplanationItem(
    BuildContext context,
    IconData icon,
    String title,
    String description,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: context.accentColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: context.accentColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  color: context.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shows the re-encryption warning dialog.
///
/// Returns `true` only if the user explicitly acknowledges the warning and
/// taps "I Understand, Continue". Returns `false` if the user cancels or
/// dismisses the dialog. The dialog is `barrierDismissible: false` so
/// accidental taps outside it cannot silently approve it.
Future<bool> showReEncryptWarningDialog({required BuildContext context}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => ReEncryptWarningDialog(
      onContinue: () => Navigator.pop(ctx, true),
      onCancel: () => Navigator.pop(ctx, false),
    ),
  );
  return result ?? false;
}
