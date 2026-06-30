import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/encryption_algorithm.dart';
import '../models/vaulted_file.dart';
import '../providers/vault_providers.dart';
import '../themes/app_colors.dart';
import '../widgets/operation_progress_sheet.dart';

class EncryptionManageScreen extends ConsumerStatefulWidget {
  final VaultEncryptionAction action;

  /// Algorithm to apply when adding encryption. Ignored for removeEncryption.
  final EncryptionAlgorithm algorithm;

  const EncryptionManageScreen({
    super.key,
    required this.action,
    required this.algorithm,
  });

  @override
  ConsumerState<EncryptionManageScreen> createState() =>
      _EncryptionManageScreenState();
}

class _EncryptionManageScreenState
    extends ConsumerState<EncryptionManageScreen> {
  final Set<String> _selectedIds = {};
  bool _isRunning = false;
  String _searchQuery = '';

  static const int _largeFileThresholdBytes = 50 * 1024 * 1024;

  bool get _isEncrypt => widget.action == VaultEncryptionAction.encrypt;

  String get _actionVerb => _isEncrypt ? 'Encrypt' : 'Remove Encryption';

  void _setSearchQuery(String value) =>
      setState(() => _searchQuery = value.trim().toLowerCase());

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatAlgorithm(EncryptionAlgorithm? algo) {
    if (algo == null) return 'None';
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

  List<VaultedFile> _eligibleFiles(AsyncValue<List<VaultedFile>> filesAsync) {
    return filesAsync.whenOrNull(
          data: (files) => files
              .where((f) => _isEncrypt ? !f.isEncrypted : f.isEncrypted)
              .toList(),
        ) ??
        [];
  }

  List<VaultedFile> _applySearchFilter(List<VaultedFile> files) {
    if (_searchQuery.isEmpty) return files;
    return files
        .where((f) => f.originalName.toLowerCase().contains(_searchQuery))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filesAsync = ref.watch(vaultNotifierProvider);
    final eligible = _eligibleFiles(filesAsync);
    final filtered = _applySearchFilter(eligible);

    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: _isRunning ? null : () => Navigator.pop(context),
        ),
        title: Text(
          'Select Files to $_actionVerb',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (!_isRunning)
            TextButton(
              onPressed: () {
                setState(() {
                  final filteredIds = filtered.map((f) => f.id).toSet();
                  if (filteredIds.every((id) => _selectedIds.contains(id))) {
                    _selectedIds.removeAll(filteredIds);
                  } else {
                    _selectedIds.addAll(filteredIds);
                  }
                });
              },
              child: Text(
                filtered.isNotEmpty &&
                        filtered.every((f) => _selectedIds.contains(f.id))
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
        data: (_) {
          if (eligible.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isEncrypt ? Icons.lock_open : Icons.lock_outline,
                    size: 64,
                    color: context.textTertiary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isEncrypt
                        ? 'No unencrypted files'
                        : 'No encrypted files',
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
                    Icon(Icons.info_outline,
                        color: context.accentColor, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _isEncrypt
                            ? 'Will encrypt with ${widget.algorithm.displayName}\n'
                                '${_selectedIds.length} of ${filtered.length} selected'
                            : 'Encryption will be removed (files stored as plaintext)\n'
                                '${_selectedIds.length} of ${filtered.length} selected',
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
                    prefixIcon:
                        Icon(Icons.search, color: context.textTertiary),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon:
                                Icon(Icons.clear, color: context.textTertiary),
                            onPressed: () => _setSearchQuery(''),
                          )
                        : null,
                    filled: true,
                    fillColor: context.surfaceColor,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 12),
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
                child: filtered.isEmpty
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
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final file = filtered[index];
                          final isSelected = _selectedIds.contains(file.id);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? context.accentColor
                                        .withValues(alpha: 0.08)
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
                                    if (file.fileSize >
                                        _largeFileThresholdBytes) ...[
                                      Icon(Icons.warning_amber,
                                          size: 14, color: Colors.orange),
                                      const SizedBox(width: 4),
                                    ],
                                    Expanded(
                                      child: Text(
                                        '${_formatSize(file.fileSize)} • ${_formatAlgorithm(file.encryptionAlgorithm)}',
                                        style: TextStyle(
                                          fontFamily: 'ProductSans',
                                          fontSize: 12,
                                          color: context.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: Checkbox(
                                  value: isSelected,
                                  onChanged: _isRunning
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
                                onTap: _isRunning
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
                    onPressed: _selectedIds.isEmpty || _isRunning
                        ? null
                        : _start,
                    icon: Icon(_isEncrypt ? Icons.lock_outline : Icons.lock_open),
                    label: Text(
                      '$_actionVerb ${_selectedIds.length} File(s)',
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

  Future<void> _start() async {
    final eligible = _eligibleFiles(ref.read(vaultNotifierProvider));
    final largeFiles = eligible
        .where((f) =>
            _selectedIds.contains(f.id) &&
            f.fileSize > _largeFileThresholdBytes)
        .toList();

    if (largeFiles.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.surfaceColor,
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Colors.orange, size: 24),
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
          content: Text(
            '${largeFiles.length} file(s) over 50MB will be processed. This may '
            'take a long time and could corrupt files if interrupted.',
            style: TextStyle(
              fontFamily: 'ProductSans',
              color: context.textSecondary,
              fontSize: 14,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style: TextStyle(color: context.textSecondary)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Proceed'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surfaceColor,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: AppColors.warning, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$_actionVerb Warning',
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
        content: Text(
          _isEncrypt
              ? 'Each selected file will be rewritten with encryption. If the '
                  'process is interrupted — dead battery, crash, force-stop, or '
                  'running out of storage — some files may be left corrupted and '
                  'permanently unrecoverable. Ensure your device is charged and '
                  'has enough free storage before continuing.'
              : 'Each selected file will be decrypted and rewritten as plaintext, '
                  'removing its encryption. If the process is interrupted, some '
                  'files may be left corrupted and permanently unrecoverable. '
                  'Ensure your device is charged and has enough free storage '
                  'before continuing.',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textSecondary,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: context.textSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('I Understand, Continue',
                style: TextStyle(fontFamily: 'ProductSans')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _runWithBottomSheet();
  }

  // Runs the operation off the main isolate (pool) and surfaces progress as a
  // modal bottom sheet — same pattern as gallery_vault_screen batch ops. The
  // sheet stays open during the await, then shows a Done state on success.
  Future<void> _runWithBottomSheet() async {
    setState(() => _isRunning = true);

    final progressState = ValueNotifier<OperationProgressState>(
      OperationProgressState(
        totalFiles: _selectedIds.length,
        currentFileName: 'Preparing...',
        statusMessage: 'Starting...',
        isProcessing: true,
        isEncrypting: _isEncrypt,
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
          operationType:
              _isEncrypt ? OperationType.encrypt : OperationType.decrypt,
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

    final vaultService = ref.read(vaultServiceProvider);
    final result = _isEncrypt
        ? await vaultService.encryptVaultFiles(
            widget.algorithm,
            fileFilter: _selectedIds,
            onProgress: onProgress,
          )
        : await vaultService.removeEncryption(
            fileFilter: _selectedIds,
            onProgress: onProgress,
          );

    if (!mounted) {
      progressState.dispose();
      return;
    }

    ref.invalidate(vaultNotifierProvider);

    if (result < 0) {
      Navigator.of(context).pop(); // close sheet
      progressState.dispose();
      setState(() => _isRunning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$_actionVerb failed',
            style: const TextStyle(fontFamily: 'ProductSans'),
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
    setState(() => _isRunning = false);
    Navigator.of(context).pop(); // pop picker, return to settings
  }
}
