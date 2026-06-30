import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/encryption_algorithm.dart';
import '../models/vaulted_file.dart';
import '../providers/vault_providers.dart';
import '../themes/app_colors.dart';
import '../widgets/operation_progress_sheet.dart';
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
  final Set<String> _selectedIds = {};
  bool _isReEncrypting = false;
  String _searchQuery = '';

  void _setSearchQuery(String value) {
    setState(() => _searchQuery = value.trim().toLowerCase());
  }

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
    final encryptedFiles = _encryptedFiles(filesAsync);
    final filteredFiles = _applySearchFilter(encryptedFiles);

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
                  final filteredIds =
                      filteredFiles.map((f) => f.id).toSet();
                  if (filteredIds.every((id) => _selectedIds.contains(id))) {
                    _selectedIds.removeAll(filteredIds);
                  } else {
                    _selectedIds.addAll(filteredIds);
                  }
                });
              },
              child: Text(
                filteredFiles.isNotEmpty &&
                        filteredFiles.every((f) => _selectedIds.contains(f.id))
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
                        '${_selectedIds.length} of ${filteredFiles.length} selected',
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  onChanged: _setSearchQuery,
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    color: context.textPrimary,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search files...',
                    hintStyle: TextStyle(
                      fontFamily: 'ProductSans',
                      color: context.textTertiary,
                    ),
                    prefixIcon: Icon(Icons.search, color: context.textTertiary),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, color: context.textTertiary),
                            onPressed: () => _setSearchQuery(''),
                          )
                        : null,
                    filled: true,
                    fillColor: context.surfaceColor,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: context.dividerColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: context.dividerColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: context.accentColor),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: filteredFiles.isEmpty
                    ? Center(
                        child: Text(
                          'No files match your search',
                          style: TextStyle(
                            fontFamily: 'ProductSans',
                            fontSize: 16,
                            color: context.textSecondary,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: filteredFiles.length,
                        itemBuilder: (context, index) {
                          final file = filteredFiles[index];
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

  List<VaultedFile> _applySearchFilter(List<VaultedFile> files) {
    if (_searchQuery.isEmpty) return files;
    return files
        .where((f) => f.originalName.toLowerCase().contains(_searchQuery))
        .toList();
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

    final progressState = ValueNotifier<OperationProgressState>(
      OperationProgressState(
        totalFiles: _selectedIds.length,
        currentFileName: 'Preparing...',
        statusMessage: 'Starting...',
        isProcessing: true,
        isEncrypting: true,
      ),
    );

    if (!mounted) {
      progressState.dispose();
      return;
    }

    void onProgress(
      int current, int total, String name, int processed, int totalBytes,
    ) {
      progressState.value = progressState.value.copyWith(
        totalFiles: total,
        currentFile: current,
        currentFileName: name,
        totalSizeBytes: totalBytes,
        processedSizeBytes: processed,
        statusMessage: current >= total
            ? 'Finalizing...'
            : 'Processing ${current + 1} of $total...',
      );
    }

    final sheetFuture = showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => ValueListenableBuilder<OperationProgressState>(
        valueListenable: progressState,
        builder: (context, state, _) => OperationProgressSheet(
          operationType: OperationType.reencrypt,
          totalFiles: state.totalFiles,
          currentFile: state.currentFile,
          currentFileName: state.currentFileName,
          totalSizeBytes: state.totalSizeBytes,
          processedSizeBytes: state.processedSizeBytes,
          statusMessage: state.statusMessage,
          isProcessing: state.isProcessing,
          isComplete: state.isComplete,
          isEncrypting: state.isEncrypting,
        ),
      ),
    );

    final result = await ref.read(vaultServiceProvider).reEncryptVault(
          widget.targetAlgorithm,
          fileFilter: _selectedIds,
          onProgress: onProgress,
        );

    if (!mounted) {
      progressState.dispose();
      return;
    }

    ref.invalidate(vaultSettingsProvider);
    ref.invalidate(vaultNotifierProvider);

    if (result < 0) {
      Navigator.of(context).pop(); // close sheet
      progressState.dispose();
      setState(() => _isReEncrypting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Re-encryption failed',
            style: TextStyle(fontFamily: 'ProductSans'),
          ),
        ),
      );
      return;
    }

    progressState.value = progressState.value.copyWith(
      isComplete: true,
      isProcessing: false,
      currentFile: progressState.value.totalFiles,
      processedSizeBytes: progressState.value.totalSizeBytes,
      statusMessage: 'Completed successfully',
    );

    await sheetFuture; // user taps Done
    progressState.dispose();
    if (!mounted) return;
    setState(() => _isReEncrypting = false);
    Navigator.of(context).pop(); // pop picker
  }
}
