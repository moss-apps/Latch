import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../themes/app_colors.dart';

/// Device folder selection; no vault mutation takes place on this route.
class FolderImportPickerScreen extends StatefulWidget {
  const FolderImportPickerScreen({super.key});

  @override
  State<FolderImportPickerScreen> createState() =>
      _FolderImportPickerScreenState();
}

class _FolderImportPickerScreenState extends State<FolderImportPickerScreen> {
  String? _currentPath;
  final _pathStack = <String>[];
  List<Directory> _subdirs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRoot();
  }

  Future<void> _loadRoot() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      if (!mounted) return;
      await _navigateInto(
          Platform.isAndroid ? '/storage/emulated/0' : appDir.path);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              'Couldn’t open this folder — check permissions and try again';
        });
      }
    }
  }

  Future<void> _navigateInto(String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        throw const FileSystemException('Missing directory');
      }
      final entities = await dir.list().toList();
      final subdirs = entities.whereType<Directory>().where((dir) {
        final name = dir.path.split('/').last;
        return !name.startsWith('.') && name != 'Android';
      }).toList()
        ..sort((a, b) => a.path
            .split('/')
            .last
            .toLowerCase()
            .compareTo(b.path.split('/').last.toLowerCase()));
      if (!mounted) return;
      setState(() {
        if (_currentPath != null) _pathStack.add(_currentPath!);
        _currentPath = path;
        _subdirs = subdirs;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      debugPrint('Folder browse error: $error');
      setState(() {
        _loading = false;
        _error = 'Couldn’t open this folder — check permissions and try again';
      });
    }
  }

  void _goBack() {
    if (_pathStack.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final path = _pathStack.removeLast();
    _currentPath = null;
    _navigateInto(path);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Select Folder to Import'),
          leading: _pathStack.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Back',
                  onPressed: _goBack,
                  icon: const Icon(Icons.arrow_back)),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: context.textSecondary))))
                : Column(children: [
                    if (_pathStack.isNotEmpty)
                      ListTile(
                          leading: const Icon(Icons.arrow_back),
                          title: Text(_currentPath ?? '',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: _goBack),
                    Expanded(
                        child: _subdirs.isEmpty
                            ? Center(
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                    Icon(Icons.folder_off_outlined,
                                        size: 48, color: context.textTertiary),
                                    const SizedBox(height: 16),
                                    const Text('No subfolders'),
                                  ]))
                            : ListView.builder(
                                padding: const EdgeInsets.all(8),
                                itemCount: _subdirs.length,
                                itemBuilder: (context, index) {
                                  final dir = _subdirs[index];
                                  return ListTile(
                                      leading: Icon(Icons.folder,
                                          color: context.accentColor),
                                      title: Text(dir.path.split('/').last),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () => _navigateInto(dir.path));
                                })),
                  ]),
        bottomNavigationBar: _currentPath == null
            ? null
            : SafeArea(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context, _currentPath),
                        icon: const Icon(Icons.check),
                        label: const Text('Import This Folder'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: context.accentColor,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)))))),
      );
}
