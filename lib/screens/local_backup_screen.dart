import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/path_utils.dart';
import '../models/vaulted_file.dart';
import '../services/backup_service.dart';
import '../themes/app_colors.dart';
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
  bool _isBackingUp = false;
  bool _backupSelectedFilesOnly = false;
  List<VaultedFile> _selectedFiles = const [];

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
    setState(() => _isBackingUp = true);

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
            ),
            const SizedBox(height: 16),
            Text(
              'Backing up...',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
          ],
        ),
      ),
    );

    final result = await _backupService.createBackup(
      destinationDirPath,
      files: _backupSelectedFilesOnly ? _selectedFiles : null,
    );

    if (mounted) Navigator.of(context).pop();

    if (mounted) setState(() => _isBackingUp = false);

    if (result.success && result.zipPath != null) {
      ToastUtils.showSuccess(
          'Backup saved: ${result.zipPath!.split('/').last}');
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
      body: _isBackingUp
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent))
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Files to include',
                    style: TextStyle(
                      fontFamily: 'ProductSans',
                      fontSize: 14,
                      color: context.textTertiary,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('All files'),
                      selected: !_backupSelectedFilesOnly,
                      onSelected: (_) {
                        setState(() => _backupSelectedFilesOnly = false);
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Selected files'),
                      selected: _backupSelectedFilesOnly,
                      onSelected: (_) {
                        setState(() => _backupSelectedFilesOnly = true);
                      },
                    ),
                  ],
                ),
                if (_backupSelectedFilesOnly)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.library_books_outlined,
                        color: context.accentColor),
                    title: Text(
                      'Choose files',
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        fontWeight: FontWeight.w500,
                        color: context.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      _selectedFilesSubtitle(),
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        fontSize: 12,
                        color: context.textTertiary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing:
                        Icon(Icons.chevron_right, color: context.textTertiary),
                    onTap: _chooseFilesForBackup,
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Save backup ZIP to',
                    style: TextStyle(
                      fontFamily: 'ProductSans',
                      fontSize: 14,
                      color: context.textTertiary,
                    ),
                  ),
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
                  leading: Icon(Icons.folder_open_outlined,
                      color: context.accentColor),
                  title: Text(
                    'Choose folder...',
                    style: TextStyle(
                      fontFamily: 'ProductSans',
                      fontWeight: FontWeight.w500,
                      color: context.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    'Pick any folder on device',
                    style: TextStyle(
                      fontFamily: 'ProductSans',
                      fontSize: 12,
                      color: context.textTertiary,
                    ),
                  ),
                  onTap: _pickFolderAndBackup,
                ),
              ],
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
