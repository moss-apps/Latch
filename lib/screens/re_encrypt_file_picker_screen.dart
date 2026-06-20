import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/encryption_algorithm.dart';
import '../models/vaulted_file.dart';
import '../providers/vault_providers.dart';
import '../themes/app_colors.dart';
import '../widgets/re_encrypt_warning_dialog.dart';

class ReEncryptFilePickerScreen extends ConsumerStatefulWidget {
  final EncryptionAlgorithm targetAlgorithm;

  const ReEncryptFilePickerScreen({
    super.key,
    required this.targetAlgorithm,
  });

  @override
  ConsumerState<ReEncryptFilePickerScreen> createState() =>
      _ReEncryptFilePickerScreenState();
}

class _ReEncryptFilePickerScreenState
    extends ConsumerState<ReEncryptFilePickerScreen> {
  Set<String> _selectedIds = {};
  bool _isReEncrypting = false;

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatAlgorithm(EncryptionAlgorithm? algo) {
    if (algo == null) return 'Unknown';
    return algo == EncryptionAlgorithm.aes256Ctr ? 'AES-CTR' : 'AES-GCM';
  }

  IconData _iconForType(VaultedFileType type) {
    switch (type) {
      case VaultedFileType.image:
        return Icons.image_outlined;
      case VaultedFileType.video:
        return Icons.videocam_outlined;
      case VaultedFileType.song:
        return Icons.audiotrack_outlined;
      case VaultedFileType.document:
        return Icons.description_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filesAsync = ref.watch(vaultNotifierProvider);
    final reEncryptProgress = ref.watch(reEncryptProvider);

    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: _isReEncrypting ? null : () => Navigator.pop(context),
        ),
        title: Text(
          'Select Files to Re-Encrypt',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (!_isReEncrypting)
            TextButton(
              onPressed: () {
                setState(() {
                  if (_selectedIds.length == _encryptedFiles(filesAsync).length) {
                    _selectedIds = {};
                  } else {
                    _selectedIds = _encryptedFiles(filesAsync)
                        .map((f) => f.id)
                        .toSet();
                  }
                });
              },
              child: Text(
                _selectedIds.length == _encryptedFiles(filesAsync).length
                    ? 'Deselect All'
                    : 'Select All',
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  color: context.accentColor,
                ),
              ),
            ),
        ],
      ),
      body: filesAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: context.accentColor),
        ),
        error: (_, __) => Center(
          child: Text(
            'Failed to load files',
            style: TextStyle(
              fontFamily: 'ProductSans',
              color: context.textPrimary,
            ),
          ),
        ),
        data: (files) {
          final encryptedFiles = _encryptedFiles(filesAsync);

          if (encryptedFiles.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_open, size: 64, color: context.textTertiary),
                  const SizedBox(height: 16),
                  Text(
                    'No encrypted files',
                    style: TextStyle(
                      fontFamily: 'ProductSans',
                      fontSize: 18,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: context.accentColor, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Target: ${widget.targetAlgorithm.displayName}\n'
                        '${_selectedIds.length} of ${encryptedFiles.length} selected',
                        style: TextStyle(
                          fontFamily: 'ProductSans',
                          fontSize: 13,
                          color: context.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (reEncryptProgress.isInProgress && _isReEncrypting)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      LinearProgressIndicator(
                        value: reEncryptProgress.total > 0
                            ? reEncryptProgress.current /
                                reEncryptProgress.total
                            : null,
                        backgroundColor: context.dividerColor,
                        valueColor: AlwaysStoppedAnimation(context.accentColor),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Re-encrypting ${reEncryptProgress.current} of ${reEncryptProgress.total}...',
                        style: TextStyle(
                          fontFamily: 'ProductSans',
                          fontSize: 12,
                          color: context.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              if (reEncryptProgress.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    reEncryptProgress.error!,
                    style: const TextStyle(
                      fontFamily: 'ProductSans',
                      color: Colors.red,
                      fontSize: 12,
                    ),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: encryptedFiles.length,
                  itemBuilder: (context, index) {
                    final file = encryptedFiles[index];
                    final isSelected = _selectedIds.contains(file.id);
                    final needsReEncrypt =
                        file.encryptionAlgorithm != widget.targetAlgorithm;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? context.accentColor.withValues(alpha: 0.08)
                              : context.surfaceColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? context.accentColor
                                : context.dividerColor,
                          ),
                        ),
                        child: ListTile(
                          leading: Icon(
                            _iconForType(file.type),
                            color: isSelected
                                ? context.accentColor
                                : context.textSecondary,
                          ),
                          title: Text(
                            file.originalName,
                            style: TextStyle(
                              fontFamily: 'ProductSans',
                              fontSize: 14,
                              color: context.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Row(
                            children: [
                              if (file.fileSize > _largeFileThresholdBytes) ...[
                                Icon(Icons.warning_amber, size: 14, color: Colors.orange),
                                const SizedBox(width: 4),
                              ],
                              Expanded(
                                child: Text(
                                  '${_formatSize(file.fileSize)} • ${_formatAlgorithm(file.encryptionAlgorithm)}'
                                  '${needsReEncrypt ? ' → ${_formatAlgorithm(widget.targetAlgorithm)}' : ' (no change)'}',
                                  style: TextStyle(
                                    fontFamily: 'ProductSans',
                                    fontSize: 12,
                                    color: needsReEncrypt
                                        ? context.textSecondary
                                        : context.textTertiary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          trailing: Checkbox(
                            value: isSelected,
                            onChanged: _isReEncrypting
                                ? null
                                : (value) {
                                    setState(() {
                                      if (value == true) {
                                        _selectedIds.add(file.id);
                                      } else {
                                        _selectedIds.remove(file.id);
                                      }
                                    });
                                  },
                            activeColor: context.accentColor,
                          ),
                          onTap: _isReEncrypting
                              ? null
                              : () {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedIds.remove(file.id);
                                    } else {
                                      _selectedIds.add(file.id);
                                    }
                                  });
                                },
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _selectedIds.isEmpty || _isReEncrypting
                        ? null
                        : () => _startReEncrypt(),
                    icon: const Icon(Icons.sync),
                    label: Text(
                      'Re-Encrypt ${_selectedIds.length} File(s)',
                      style: const TextStyle(fontFamily: 'ProductSans'),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: context.accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static const int _largeFileThresholdBytes = 50 * 1024 * 1024;

  List<VaultedFile> _encryptedFiles(AsyncValue<List<VaultedFile>> filesAsync) {
    return filesAsync.whenOrNull(
          data: (files) => files.where((f) => f.isEncrypted).toList(),
        ) ??
        [];
  }

  Future<void> _startReEncrypt() async {
    final encryptedFiles = _encryptedFiles(ref.read(vaultNotifierProvider));
    final largeFiles = encryptedFiles
        .where((f) => _selectedIds.contains(f.id) && f.fileSize > _largeFileThresholdBytes)
        .toList();

    if (largeFiles.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.surfaceColor,
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Large Files Detected',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    color: context.textPrimary,
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
                '${largeFiles.length} file(s) over 50MB will be re-encrypted. This may take a long time and could corrupt files if interrupted.',
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  color: context.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              ...largeFiles.take(5).map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• ${f.originalName} (${_formatSize(f.fileSize)})',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 12,
                    color: context.textTertiary,
                  ),
                ),
              )),
              if (largeFiles.length > 5)
                Text(
                  '...and ${largeFiles.length - 5} more',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 12,
                    color: context.textTertiary,
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: TextStyle(color: context.textSecondary),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange,
              ),
              child: const Text('Proceed'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    final warningAcknowledged = await showReEncryptWarningDialog(
      context: context,
    );
    if (warningAcknowledged != true || !mounted) return;

    setState(() => _isReEncrypting = true);
    await ref.read(reEncryptProvider.notifier).reEncryptVault(
          widget.targetAlgorithm,
          fileFilter: _selectedIds,
        );
    if (mounted) {
      setState(() => _isReEncrypting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Re-encryption complete',
            style: TextStyle(fontFamily: 'ProductSans'),
          ),
        ),
      );
      ref.invalidate(vaultNotifierProvider);
    }
  }
}
