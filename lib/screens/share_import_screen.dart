import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_to_vault.dart';
import '../models/shared_file_ref.dart';
import '../models/vaulted_file.dart';
import '../providers/vault_providers.dart';
import '../services/auto_kill_service.dart';
import '../services/file_import_service.dart';
import '../services/session_service.dart';
import '../services/share_intake_service.dart';
import '../services/vault_service.dart';
import '../themes/app_colors.dart';
import '../widgets/per_file_encryption_sheet.dart';

enum _SharePhase { review, busy, done }

class ShareImportScreen extends ConsumerStatefulWidget {
  const ShareImportScreen({super.key});

  @override
  ConsumerState<ShareImportScreen> createState() => _ShareImportScreenState();
}

class _ShareImportScreenState extends ConsumerState<ShareImportScreen> {
  _SharePhase _phase = _SharePhase.review;
  String _status = '';
  double? _progress;
  String _resultTitle = '';
  String _resultMessage = '';
  bool _resultIsError = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _phase == _SharePhase.done,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_phase == _SharePhase.review) {
          _deferAndClose();
        }
      },
      child: Scaffold(
        backgroundColor: context.backgroundColor,
        appBar: AppBar(
          backgroundColor: context.backgroundColor,
          elevation: 0,
          automaticallyImplyLeading: _phase != _SharePhase.busy,
          title: Text(
            'Share to Latch',
            style: TextStyle(
              fontFamily: 'ProductSans',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
        ),
        body: ListenableBuilder(
          listenable: ShareIntakeService.instance,
          builder: (context, _) {
            switch (_phase) {
              case _SharePhase.review:
                return _buildReview();
              case _SharePhase.busy:
                return _buildBusy();
              case _SharePhase.done:
                return _buildResult();
            }
          },
        ),
      ),
    );
  }

  Widget _buildReview() {
    final items = ShareIntakeService.instance.pending;
    return Column(
      children: [
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    'No shared files remaining',
                    style: TextStyle(
                      fontFamily: 'ProductSans',
                      color: context.textSecondary,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      leading: Icon(
                        _typeIcon(getFileTypeFromMime(item.mimeType)),
                        color: context.accentColor,
                      ),
                      title: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'ProductSans',
                          color: context.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        _formatSize(item.sizeBytes),
                        style: TextStyle(
                          fontFamily: 'ProductSans',
                          color: context.textSecondary,
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Icon(Icons.info_outline,
                  size: 16, color: context.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Files are copied into Latch. The originals stay in the '
                  'source app.',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 12,
                    color: context.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _discard,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.textPrimary,
                    side: BorderSide(color: context.borderColor),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Discard'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: items.isEmpty ? null : _startImport,
                  style: FilledButton.styleFrom(
                    backgroundColor: context.accentColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Import Files'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBusy() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: CircularProgressIndicator(
              value: _progress,
              strokeWidth: 3,
              color: context.accentColor,
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _status,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'ProductSans',
                fontSize: 14,
                color: context.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResult() {
    final errorColor = Theme.of(context).colorScheme.error;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _resultIsError
                  ? Icons.error_outline
                  : Icons.check_circle_outline,
              size: 64,
              color: _resultIsError ? errorColor : context.accentColor,
            ),
            const SizedBox(height: 16),
            Text(
              _resultTitle,
              style: TextStyle(
                fontFamily: 'ProductSans',
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _resultMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'ProductSans',
                fontSize: 14,
                color: context.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: context.accentColor,
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
              ),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startImport() async {
    final service = ShareIntakeService.instance;
    final attempted = List<SharedFileRef>.of(service.pending);
    if (attempted.isEmpty) return;

    final generation = SessionService.instance.generation;
    final settings = await VaultService.instance.getSettings();
    if (!mounted) return;

    setState(() {
      _phase = _SharePhase.busy;
      _status = 'Preparing shared files…';
      _progress = null;
    });

    final stagingDir = await service.prepareStagingDirectory(generation);
    final staged = await service.stage(destinationDir: stagingDir.path);
    if (!mounted) return;

    final usable = staged.where((s) => s.ok).toList();
    final failed = staged.where((s) => !s.ok).toList();

    if (usable.isEmpty) {
      await service.consume(attempted.map((ref) => ref.id).toList());
      await service.purgeStaging();
      if (!mounted) return;
      _finish(
        title: 'Nothing imported',
        message: failed.isEmpty
            ? 'The shared files could not be read.'
            : failed
                .map((f) => '${f.name}: ${f.error}')
                .join('\n'),
        isError: true,
      );
      return;
    }

    final decisions = await PerFileEncryptionSheet.show(
      context,
      files: [
        for (final stagedFile in usable)
          PerFileEncryptionSettings(
            fileName: stagedFile.name,
            filePath: stagedFile.path!,
            fileSize: stagedFile.sizeBytes,
            encrypt: settings.encryptionEnabled,
            algorithm: settings.encryptionAlgorithm,
          ),
      ],
      encryptionEnabled: settings.encryptionEnabled,
      defaultAlgorithm: settings.encryptionAlgorithm,
    );

    if (!mounted) return;
    if (decisions == null) {
      await service.purgeStaging();
      service.deferCurrent();
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final stagedByPath = {for (final s in usable) s.path!: s};
    final files = <FileToVault>[];
    for (final decision in decisions) {
      final source = stagedByPath[decision.filePath];
      if (source == null) continue;
      files.add(FileToVault(
        sourcePath: decision.filePath,
        originalName: decision.fileName,
        type: getFileTypeFromMime(source.mimeType),
        mimeType: source.mimeType,
        encrypt: settings.encryptionEnabled ? decision.encrypt : null,
        encryptionAlgorithm:
            settings.encryptionEnabled ? decision.algorithm : null,
      ));
    }

    setState(() => _status = 'Encrypting and importing…');

    ImportResult result;
    try {
      result = await AutoKillService.runSafe(
        () => FileImportService.instance.importPreparedFiles(
          files: files,
          onProgress: (current, total) {
            if (!mounted) return;
            setState(() {
              _progress = total == 0 ? null : current / total;
              _status = 'Importing $current of $total…';
            });
          },
          onFileProgress: (info) {
            if (!mounted) return;
            if (info.status.isNotEmpty) {
              setState(() => _status = info.status);
            }
          },
        ),
      );
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    if (!mounted) return;
    if (SessionService.instance.generation != generation) {
      Navigator.of(context).pop();
      return;
    }

    await service.consume(attempted.map((ref) => ref.id).toList());
    await service.purgeStaging();
    if (!mounted) return;

    ref.read(vaultNotifierProvider.notifier).loadFiles();

    final parts = <String>[];
    if (result.importedCount > 0) parts.add('${result.importedCount} imported');
    if (result.skippedDuplicates > 0) {
      parts.add('${result.skippedDuplicates} already in vault');
    }
    if (result.failedCount > 0) parts.add('${result.failedCount} failed');
    if (failed.isNotEmpty) parts.add('${failed.length} unreadable');

    _finish(
      title: result.importedCount > 0 ? 'Import complete' : 'Nothing imported',
      message: parts.isEmpty
          ? (result.message ?? 'No files imported')
          : parts.join(' · '),
      isError: result.importedCount == 0,
    );
  }

  void _finish({
    required String title,
    required String message,
    required bool isError,
  }) {
    setState(() {
      _phase = _SharePhase.done;
      _resultTitle = title;
      _resultMessage = message;
      _resultIsError = isError;
    });
  }

  Future<void> _deferAndClose() async {
    final service = ShareIntakeService.instance;
    await service.purgeStaging();
    service.deferCurrent();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _discard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(dialogContext).scaffoldBackgroundColor,
        title: Text(
          'Discard shared files?',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: dialogContext.textPrimary,
          ),
        ),
        content: Text(
          'They will not be imported into Latch.',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: dialogContext.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ShareIntakeService.instance.clearAll();
    await ShareIntakeService.instance.purgeStaging();
    if (mounted) Navigator.of(context).pop();
  }

  IconData _typeIcon(VaultedFileType type) {
    switch (type) {
      case VaultedFileType.image:
        return Icons.image_outlined;
      case VaultedFileType.video:
        return Icons.videocam_outlined;
      case VaultedFileType.song:
        return Icons.music_note_outlined;
      case VaultedFileType.document:
        return Icons.description_outlined;
      case VaultedFileType.other:
        return Icons.insert_drive_file_outlined;
    }
  }

  String _formatSize(int? bytes) {
    if (bytes == null || bytes <= 0) return 'Unknown size';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final text = value >= 100 || unit == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$text ${units[unit]}';
  }
}
