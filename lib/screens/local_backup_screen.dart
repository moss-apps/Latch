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

  // ValueNotifier crosses the route boundary where setState can't.
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

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: context.accentColor,
        ),
      ),
    );
  }

  Widget _hint(String text) {
    return Text(
      text,
      style: TextStyle(fontSize: 12, color: context.textTertiary),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: context.accentColor),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: context.textTertiary),
      ),
      trailing: Icon(Icons.chevron_right, color: context.textTertiary),
      onTap: onTap,
    );
  }

  ChoiceChip _themedChoiceChip({
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: context.accentColor,
      side: BorderSide(color: context.borderColor),
      onSelected: onSelected,
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _targetFileCount;
    final size = _humanSize(_targetBytes);

    return Scaffold(
      appBar: AppBar(title: const Text('Local backup')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _sectionTitle('Summary'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading:
                Icon(Icons.archive_outlined, color: context.accentColor),
            title: const Text('Ready to backup'),
            subtitle: Text(
              _allFilesLoaded
                  ? '$count ${count == 1 ? 'file' : 'files'} • ~$size'
                  : 'Counting files...',
              style:
                  TextStyle(fontSize: 12, color: context.textTertiary),
            ),
          ),
          const SizedBox(height: 24),
          _sectionTitle('Files to include'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _themedChoiceChip(
                label: 'All files',
                selected: !_backupSelectedFilesOnly,
                onSelected: (_) =>
                    setState(() => _backupSelectedFilesOnly = false),
              ),
              _themedChoiceChip(
                label: 'Selected files',
                selected: _backupSelectedFilesOnly,
                onSelected: (_) =>
                    setState(() => _backupSelectedFilesOnly = true),
              ),
            ],
          ),
          if (_backupSelectedFilesOnly) ...[
            const SizedBox(height: 8),
            _tile(
              icon: Icons.library_books_outlined,
              title: 'Choose files',
              subtitle: _selectedFilesSubtitle(),
              onTap: _chooseFilesForBackup,
            ),
            if (_selectedFiles.isEmpty)
              _hint('No files chosen yet — tap "Choose files".'),
          ],
          const SizedBox(height: 24),
          _sectionTitle('Save location'),
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
          _tile(
            icon: Icons.folder_open_outlined,
            title: 'Choose folder...',
            subtitle: 'Pick any folder on device',
            onTap: _pickFolderAndBackup,
          ),
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
                style: TextStyle(color: context.textPrimary),
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
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.folder_outlined,
            color: available ? context.accentColor : context.textTertiary,
          ),
          title: Text(name),
          subtitle: Text(
            path ?? (snapshot.hasError ? 'Unavailable' : '...'),
            style: TextStyle(fontSize: 12, color: context.textTertiary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: available ? onTap : null,
        );
      },
    );
  }
}

// standard 1024-base size formatter.
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
