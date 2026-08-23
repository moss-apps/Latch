import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../themes/app_colors.dart';
import '../utils/responsive_utils.dart';

/// One browsable root: display label and absolute path.
class FolderPickerRoot {
  final String label;
  final String path;

  const FolderPickerRoot({required this.label, required this.path});
}

/// Returns platform-specific roots for the folder picker.
Future<List<FolderPickerRoot>> getFolderPickerRoots() async {
  if (Platform.isAndroid) {
    const internal = '/storage/emulated/0';
    final roots = <FolderPickerRoot>[];
    final d = Directory(internal);
    if (await d.exists()) {
      roots.add(
          const FolderPickerRoot(label: 'Internal storage', path: internal));
    }
    final ext = await getExternalStorageDirectory();
    if (ext != null && !roots.any((r) => r.path == ext.path)) {
      roots.add(FolderPickerRoot(label: 'App storage', path: ext.path));
    }
    if (roots.isEmpty) {
      final app = await getApplicationDocumentsDirectory();
      roots.add(FolderPickerRoot(label: 'App documents', path: app.path));
    }
    return roots;
  }
  final app = await getApplicationDocumentsDirectory();
  return [FolderPickerRoot(label: 'App documents', path: app.path)];
}

/// In-app folder browser: pick a directory to save the backup. Follows app theme and responsive layout.
class FolderPickerScreen extends StatefulWidget {
  /// Initial path to show; if null, shows roots.
  final String? initialPath;

  const FolderPickerScreen({super.key, this.initialPath});

  @override
  State<FolderPickerScreen> createState() => _FolderPickerScreenState();
}

class _FolderPickerScreenState extends State<FolderPickerScreen> {
  List<FolderPickerRoot>? _roots;
  List<FileSystemEntity>? _subdirs;
  String? _currentPath;
  bool _loading = true;
  String? _error;
  final List<String> _pathStack = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialPath != null) {
      _currentPath = widget.initialPath;
      _pathStack.add(widget.initialPath!);
      _loadSubdirs(widget.initialPath!);
    } else {
      _loadRoots();
    }
  }

  Future<void> _loadRoots() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final roots = await getFolderPickerRoots();
      if (mounted) {
        setState(() {
          _roots = roots;
          _loading = false;
          _currentPath = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          debugPrint('Folder browse error: $e');
          _error = 'Couldn\'t open this folder — check permissions and try again';
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadSubdirs(String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        if (mounted) setState(() => _error = 'Folder not found');
        return;
      }
      final entities = await dir.list().toList();
      final subdirs = entities
          .where(
              (e) => e is Directory && !e.path.split('/').last.startsWith('.'))
          .toList();
      subdirs.sort((a, b) => a.path
          .split('/')
          .last
          .toLowerCase()
          .compareTo(b.path.split('/').last.toLowerCase()));
      if (mounted) {
        setState(() {
          _subdirs = subdirs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          debugPrint('Folder browse error: $e');
          _error = 'Couldn\'t open this folder — check permissions and try again';
          _loading = false;
        });
      }
    }
  }

  void _navigateInto(String path) {
    _pathStack.add(path);
    setState(() => _currentPath = path);
    _loadSubdirs(path);
  }

  void _goBack() {
    if (_pathStack.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    if (_pathStack.length == 1) {
      _pathStack.clear();
      setState(() {
        _currentPath = null;
        _subdirs = null;
      });
      _loadRoots();
      return;
    }
    _pathStack.removeLast();
    final path = _pathStack.last;
    setState(() => _currentPath = path);
    _loadSubdirs(path);
  }

  void _selectCurrentFolder() {
    final path =
        _currentPath ?? (_pathStack.isNotEmpty ? _pathStack.last : null);
    if (path != null) Navigator.of(context).pop(path);
  }

  String _displayName(String path) {
    final name = path.split('/').where((s) => s.isNotEmpty).lastOrNull ?? path;
    return name.isEmpty ? path : name;
  }

  @override
  Widget build(BuildContext context) {
    final padding = ResponsiveUtils.getPadding(context);
    final spacing = ResponsiveUtils.getSpacing(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goBack,
          color: context.textPrimary,
        ),
        title: Text(
          _pathStack.isEmpty ? 'Choose folder' : _displayName(_pathStack.last),
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontWeight: FontWeight.w600,
            fontSize: 20,
            color: context.textPrimary,
          ),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: context.textPrimary),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_currentPath != null || (_pathStack.isNotEmpty)) ...[
              _BreadcrumbBar(
                pathStack: _pathStack,
                roots: _roots,
                onTap: (index) {
                  if (index < _pathStack.length) {
                    final path = _pathStack[index];
                    _pathStack.removeRange(index + 1, _pathStack.length);
                    setState(() => _currentPath = path);
                    _loadSubdirs(path);
                  }
                },
              ),
              Divider(height: 1, color: context.dividerColor),
            ],
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation<Color>(context.accentColor),
                      ),
                    )
                  : _error != null
                      ? _ErrorState(
                          message: _error!,
                          onRetry: () => _pathStack.isEmpty
                              ? _loadRoots()
                              : _loadSubdirs(_pathStack.last),
                        )
                      : _buildContent(padding, spacing),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildSelectBar(),
    );
  }

  Widget _buildContent(EdgeInsets padding, double spacing) {
    if (_roots != null && _pathStack.isEmpty) {
      return ListView.builder(
        padding: padding,
        itemCount: _roots!.length,
        itemBuilder: (context, i) {
          final root = _roots![i];
          return _FolderTile(
            name: root.label,
            path: root.path,
            onTap: () => _navigateInto(root.path),
          );
        },
      );
    }
    if (_subdirs == null) return const SizedBox.shrink();
    if (_subdirs!.isEmpty) {
      return _EmptyState(
        onSelectThisFolder: _pathStack.isNotEmpty ? _selectCurrentFolder : null,
      );
    }
    return ListView.builder(
      padding: padding,
      itemCount: _subdirs!.length,
      itemBuilder: (context, i) {
        final entity = _subdirs![i] as Directory;
        final path = entity.path;
        final name = _displayName(path);
        return _FolderTile(
          name: name,
          path: path,
          onTap: () => _navigateInto(path),
        );
      },
    );
  }

  Widget _buildSelectBar() {
    final canSelect = _pathStack.isNotEmpty;
    return Container(
      padding: EdgeInsets.fromLTRB(
        ResponsiveUtils.getSpacing(context) * 2,
        ResponsiveUtils.getSpacing(context),
        ResponsiveUtils.getSpacing(context) * 2,
        ResponsiveUtils.getSpacing(context) +
            MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: context.dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: canSelect ? _selectCurrentFolder : null,
            icon: const Icon(Icons.check, size: 20),
            label: Text(
              'Select this folder',
              style: TextStyle(
                fontFamily: 'ProductSans',
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: context.accentColor,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ),
    );
  }
}

class _BreadcrumbBar extends StatelessWidget {
  final List<String> pathStack;
  final List<FolderPickerRoot>? roots;
  final void Function(int index) onTap;

  const _BreadcrumbBar({
    required this.pathStack,
    required this.roots,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (pathStack.isEmpty) return const SizedBox.shrink();
    final names = <String>[];
    final firstPath = pathStack.first;
    if (roots != null && roots!.isNotEmpty) {
      final match = roots!.where((r) => r.path == firstPath).firstOrNull;
      names.add(match?.label ?? _segmentName(firstPath));
    } else {
      names.add(_segmentName(firstPath));
    }
    for (var i = 1; i < pathStack.length; i++) {
      names.add(_segmentName(pathStack[i]));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveUtils.getSpacing(context) * 2,
        vertical: ResponsiveUtils.getSpacing(context),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < names.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.chevron_right,
                    size: 20, color: context.textTertiary),
              ),
            InkWell(
              onTap: () => onTap(i),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  names[i],
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 14,
                    color: i == names.length - 1
                        ? context.textPrimary
                        : context.textTertiary,
                    fontWeight: i == names.length - 1
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _segmentName(String path) {
    return path.split('/').where((s) => s.isNotEmpty).lastOrNull ?? path;
  }
}

class _FolderTile extends StatelessWidget {
  final String name;
  final String path;
  final VoidCallback onTap;

  const _FolderTile({
    required this.name,
    required this.path,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: context.accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child:
              Icon(Icons.folder_outlined, color: context.accentColor, size: 24),
        ),
        title: Text(
          name,
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontWeight: FontWeight.w500,
            fontSize: 16,
            color: context.textPrimary,
          ),
        ),
        trailing: Icon(Icons.chevron_right, color: context.textTertiary),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback? onSelectThisFolder;

  const _EmptyState({this.onSelectThisFolder});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(ResponsiveUtils.getSpacing(context) * 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_off_outlined,
                size: 64, color: context.textTertiary),
            SizedBox(height: ResponsiveUtils.getSpacing(context) * 2),
            Text(
              'No subfolders here',
              style: TextStyle(
                fontFamily: 'ProductSans',
                fontSize: 16,
                color: context.textSecondary,
              ),
            ),
            SizedBox(height: ResponsiveUtils.getSpacing(context)),
            Text(
              'You can still select this folder',
              style: TextStyle(
                fontFamily: 'ProductSans',
                fontSize: 14,
                color: context.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(ResponsiveUtils.getSpacing(context) * 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: context.textTertiary),
            SizedBox(height: ResponsiveUtils.getSpacing(context) * 2),
            Text(
              'Could not load folder',
              style: TextStyle(
                fontFamily: 'ProductSans',
                fontSize: 16,
                color: context.textSecondary,
              ),
            ),
            SizedBox(height: ResponsiveUtils.getSpacing(context)),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'ProductSans',
                fontSize: 12,
                color: context.textTertiary,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: ResponsiveUtils.getSpacing(context) * 2),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry',
                  style: TextStyle(fontFamily: 'ProductSans')),
              style: FilledButton.styleFrom(
                backgroundColor: context.accentColor,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
