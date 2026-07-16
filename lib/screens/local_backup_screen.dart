import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../models/vaulted_file.dart';
import '../services/backup_service.dart';
import '../services/vault_service.dart';
import '../themes/app_colors.dart';
import '../utils/path_utils.dart';
import '../utils/toast_utils.dart';
import 'backup_file_selection_screen.dart';
import 'folder_picker_screen.dart';

/// One save target: label and a way to get its path (or null).
class SaveLocation {
  final String name;
  final Future<String?> Function() resolvePath;

  const SaveLocation({required this.name, required this.resolvePath});
}

/// Lists save folders and runs backup to the chosen one.
class LocalBackupScreen extends ConsumerStatefulWidget {
  const LocalBackupScreen({super.key});

  @override
  ConsumerState<LocalBackupScreen> createState() => _LocalBackupScreenState();
}

class _LocalBackupScreenState extends ConsumerState<LocalBackupScreen> {
  final BackupService _backupService = BackupService.instance;
  final VaultService _vaultService = VaultService.instance;

  bool _isBackingUp = false;
  bool _backupSelectedFilesOnly = false;
  List<VaultedFile> _selectedFiles = const [];

  List<VaultedFile> _allFiles = const [];
  bool _allFilesLoaded = false;

  // ponytail: ValueNotifier drives the progress dialog across the route
  // boundary (setState here won't rebuild a separately-pushed dialog route).
  final ValueNotifier<({int current, int total})?> _progress =
      ValueNotifier(null);

  static List<SaveLocation> get _saveLocations => [
        SaveLocation(
          name: 'Downloads',
          resolvePath: () async {
            final d = await PathUtils.getDownloadsDirectory();
            return d?.path;
          },
        ),
        SaveLocation(
          name: 'App documents',
          resolvePath: () async {
            final d = await getApplicationDocumentsDirectory();
            return d.path;
          },
        ),
      ];

  @override
  void initState() {
    super.initState();
    _loadAllFiles();
    if (kDebugMode) _selfCheckHumanSize();
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  Future<void> _loadAllFiles() async {
    final files = await _vaultService.getAllFiles(isDecoy: false);
    if (!mounted) return;
    setState(() {
      _allFiles = files;
      _allFilesLoaded = true;
    });
  }

  int get _targetFileCount =>
      _backupSelectedFilesOnly ? _selectedFiles.length : _allFiles.length;

  int get _targetBytes {
    final files = _backupSelectedFilesOnly ? _selectedFiles : _allFiles;
    return files.fold<int>(0, (sum, f) => sum + f.fileSize);
  }

  Future<void> _chooseFilesForBackup() async {
    final selectedFiles = await Navigator.of(context).push<List<VaultedFile>>(
      MaterialPageRoute(
        builder: (context) => BackupFileSelectionScreen(
          initialSelection: _selectedFiles,
        ),
      ),
    );

    if (!mounted || selectedFiles == null) return;

    setState(() {
      _backupSelectedFilesOnly = true;
      _selectedFiles = selectedFiles;
    });
  }

  Future<bool> _ensureSelectedFiles() async {
    if (!_backupSelectedFilesOnly) return true;
    if (_selectedFiles.isNotEmpty) return true;

    await _chooseFilesForBackup();
    if (_selectedFiles.isNotEmpty) return true;

    ToastUtils.showError('Select at least one file to backup');
    return false;
  }

  String _selectedFilesSubtitle() {
    if (_selectedFiles.isEmpty) {
      return 'No files selected';
    }
    if (_selectedFiles.length == 1) {
      return _selectedFiles.first.originalName;
    }
    return '${_selectedFiles.length} files selected';
  }

  Future<void> _runBackupToPath(String destinationDirPath) async {
    if (!await _ensureSelectedFiles()) return;
    if (_isBackingUp) return;

    final fileCount = _targetFileCount;
    setState(() {
      _isBackingUp = true;
      _progress.value = null;
    });

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BackupProgressDialog(progress: _progress),
    );

    final result = await _backupService.createBackup(
      destinationDirPath,
      files: _backupSelectedFilesOnly ? _selectedFiles : null,
      onProgress: (current, total) => _progress.value = (current: current, total: total),
    );

    if (mounted) Navigator.of(context).pop();

    if (mounted) {
      setState(() {
        _isBackingUp = false;
        _progress.value = null;
      });
    }

    if (result.success && result.zipPath != null) {
      final size = _humanSize(File(result.zipPath!).lengthSync());
      final name = result.zipPath!.split('/').last;
      ToastUtils.showSuccess('Backed up $fileCount '
          '${fileCount == 1 ? 'file' : 'files'} • $size • $name');
    } else {
      ToastUtils.showError(result.error ?? 'Backup failed');
    }
  }

  Future<void> _pickFolderAndBackup() async {
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => const FolderPickerScreen(),
      ),
    );
    if (path == null || path.isEmpty) return;
    await _runBackupToPath(path);
  }

  // ---- builders ----

  Widget _sectionCard(BuildContext context, {required Widget child}) => Card(
        elevation: 0,
        color: context.backgroundSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: child,
        ),
      );

  TextStyle _sectionLabel(BuildContext context) => TextStyle(
        fontFamily: 'ProductSans',
        fontSize: 14,
        color: context.textTertiary,
      );

  TextStyle _tileTitle(BuildContext context) => TextStyle(
        fontFamily: 'ProductSans',
        fontWeight: FontWeight.w500,
        color: context.textPrimary,
      );

  TextStyle _tileSubtitle(BuildContext context) => TextStyle(
        fontFamily: 'ProductSans',
        fontSize: 12,
        color: context.textTertiary,
      );

  ChoiceChip _themedChoiceChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    final accent = context.accentColor;
    final onAccent = Theme.of(context).colorScheme.onPrimary;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: accent,
      side: BorderSide(color: context.borderColor),
      labelStyle: TextStyle(
        fontFamily: 'ProductSans',
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        color: selected ? onAccent : context.textPrimary,
      ),
      checkmarkColor: onAccent,
      onSelected: onSelected,
    );
  }

  Widget _buildSummaryCard(BuildContext context) {
    final count = _targetFileCount;
    final size = _humanSize(_targetBytes);
    return _sectionCard(
      context,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(Icons.archive_outlined, color: context.accentColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ready to backup',
                    style: TextStyle(
                      fontFamily: 'ProductSans',
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _allFilesLoaded
                        ? '$count ${count == 1 ? 'file' : 'files'} • ~$size'
                        : 'Counting files...',
                    style: _tileSubtitle(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilesToIncludeCard(BuildContext context) {
    return _sectionCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: Text('Files to include', style: _sectionLabel(context)),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _themedChoiceChip(
                context,
                label: 'All files',
                selected: !_backupSelectedFilesOnly,
                onSelected: (_) =>
                    setState(() => _backupSelectedFilesOnly = false),
              ),
              _themedChoiceChip(
                context,
                label: 'Selected files',
                selected: _backupSelectedFilesOnly,
                onSelected: (_) =>
                    setState(() => _backupSelectedFilesOnly = true),
              ),
            ],
          ),
          if (_backupSelectedFilesOnly) ...[
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.library_books_outlined,
                  color: context.accentColor),
              title: Text('Choose files', style: _tileTitle(context)),
              subtitle: Text(
                _selectedFilesSubtitle(),
                style: _tileSubtitle(context),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing:
                  Icon(Icons.chevron_right, color: context.textTertiary),
              onTap: _chooseFilesForBackup,
            ),
            if (_selectedFiles.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text(
                  'No files chosen yet — tap "Choose files".',
                  style: _tileSubtitle(context),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildSaveLocationCard(BuildContext context) {
    return _sectionCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: Text('Save backup ZIP to', style: _sectionLabel(context)),
          ),
          ..._saveLocations.map((loc) => _SaveLocationTile(
                name: loc.name,
                resolvePath: loc.resolvePath,
                onTap: () async {
                  final path = await loc.resolvePath();
                  if (path == null || path.isEmpty) {
                    ToastUtils.showError('Could not access ${loc.name}');
                    return;
                  }
                  await _runBackupToPath(path);
                },
              )),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.folder_open_outlined, color: context.accentColor),
            title: Text('Choose folder...', style: _tileTitle(context)),
            subtitle: Text('Pick any folder on device',
                style: _tileSubtitle(context)),
            onTap: _pickFolderAndBackup,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Local backup',
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: context.textPrimary),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        children: [
          _buildSummaryCard(context),
          const SizedBox(height: 16),
          _buildFilesToIncludeCard(context),
          const SizedBox(height: 16),
          _buildSaveLocationCard(context),
        ],
      ),
    );
  }
}

/// Backup progress dialog driven by a [ValueNotifier] so it updates live
/// without rebuilding the parent route.
class _BackupProgressDialog extends StatelessWidget {
  final ValueListenable<({int current, int total})?> progress;

  const _BackupProgressDialog({required this.progress});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      content: ValueListenableBuilder<({int current, int total})?>(
        valueListenable: progress,
        builder: (context, p, _) {
          final value = (p != null && p.total > 0) ? p.current / p.total : null;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: value,
                color: AppColors.accent,
                backgroundColor: context.borderColor,
              ),
              const SizedBox(height: 16),
              Text(
                p == null
                    ? 'Preparing backup...'
                    : 'Backing up file ${p.current} of ${p.total}',
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  color: context.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SaveLocationTile extends StatelessWidget {
  final String name;
  final Future<String?> Function() resolvePath;
  final VoidCallback onTap;

  const _SaveLocationTile({
    required this.name,
    required this.resolvePath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: resolvePath(),
      builder: (context, snapshot) {
        final path = snapshot.data;
        final available = path != null && path.isNotEmpty;
        return ListTile(
          leading: Icon(
            Icons.folder_outlined,
            color: available ? context.accentColor : context.textTertiary,
          ),
          title: Text(
            name,
            style: TextStyle(
              fontFamily: 'ProductSans',
              fontWeight: FontWeight.w500,
              color: context.textPrimary,
            ),
          ),
          subtitle: Text(
            path ?? (snapshot.hasError ? 'Unavailable' : '...'),
            style: TextStyle(
              fontFamily: 'ProductSans',
              fontSize: 12,
              color: context.textTertiary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: available ? onTap : null,
        );
      },
    );
  }
}

// ponytail: standard 1024-base size formatter. Known outputs:
// _humanSize(0)=="0 B", _humanSize(1023)=="1023 B", _humanSize(1024)=="1.0 KB",
// _humanSize(1048576)=="1.0 MB".
String _humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var size = bytes / 1024;
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(size >= 100 ? 0 : 1)} ${units[unit]}';
}

void _selfCheckHumanSize() {
  assert(_humanSize(0) == '0 B');
  assert(_humanSize(1023) == '1023 B');
  assert(_humanSize(1024) == '1.0 KB');
  assert(_humanSize(1048576) == '1.0 MB');
}
