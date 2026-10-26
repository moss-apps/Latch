import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vaulted_file.dart';
import '../providers/vault_providers.dart';
import '../services/crypto_isolate_pool.dart';
import '../services/file_operation_gate.dart';
import '../services/file_viewer_context.dart';
import '../services/vault_service.dart';
import 'document_viewer_screen.dart';
import 'song_player_screen.dart';

/// Gallery-only browsing for songs or Docs, using the existing file viewers.
class FileBrowserScreen extends ConsumerStatefulWidget {
  final VaultedFile initialFile;
  final List<VaultedFile> files;
  final File? initialDecryptedFile;

  const FileBrowserScreen({
    super.key,
    required this.initialFile,
    required this.files,
    this.initialDecryptedFile,
  });

  @override
  ConsumerState<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends ConsumerState<FileBrowserScreen> {
  late final List<VaultedFile> _files;
  late final PageController _controller;
  late final VaultService _vault;
  late int _index;
  final _loads = <String, Future<File>>{};
  final _tokens = <String, CancelToken>{};
  double _navigationDrag = 0;

  String get _kind => widget.initialFile.isSong ? 'song' : 'document';

  @override
  void initState() {
    super.initState();
    _files = fileViewerContext(widget.initialFile, widget.files);
    _index = _files.indexWhere((file) => file.id == widget.initialFile.id);
    _controller = PageController(initialPage: _index);
    _vault = ref.read(vaultServiceProvider);
  }

  @override
  void dispose() {
    _controller.dispose();
    for (final token in _tokens.values) {
      token.cancel();
    }
    // Pages share prepared files. Clean up only after closing the browser,
    // never while changing pages or by clearing another viewer's temp files.
    unawaited(_cleanup());
    super.dispose();
  }

  Future<void> _cleanup() async {
    try {
      await Future.wait(_loads.entries.map((entry) async {
        try {
          final prepared = await entry.value;
          final file = _files.firstWhere((file) => file.id == entry.key);
          if (file.isEncrypted &&
              file.encryptionIv != null &&
              prepared.path != file.vaultPath &&
              await prepared.exists()) {
            await prepared.delete();
          }
        } catch (_) {
          // The vault handles cancelled decrypts and session-lock cleanup.
        }
      }));
    } catch (error) {
      debugPrint('Error cleaning up file browser: $error');
    }
  }

  Future<File> _prepareFile(VaultedFile file) async {
    if (!FileOperationGate.instance.canRead(file.id)) {
      throw StateError('File is being processed');
    }
    File? prepared;
    if (file.id == widget.initialFile.id) {
      prepared = widget.initialDecryptedFile;
    }
    if (prepared == null) {
      if (file.isEncrypted && file.encryptionIv != null) {
        final token = _tokens.putIfAbsent(file.id, CancelToken.new);
        prepared = await _vault.getVaultedFile(file.id, cancelToken: token);
      } else {
        prepared = File(file.vaultPath);
      }
    }
    if (prepared == null || !await prepared.exists()) {
      throw StateError('Could not prepare file');
    }
    return prepared;
  }

  void _changePage(int index) {
    setState(() => _index = index);
    unawaited(_vault.updateFile(_files[index].markViewed()));
  }

  void _goTo(int index) {
    if (index < 0 || index >= _files.length) return;
    _controller.animateToPage(index,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeBottom: _files.length > 1,
              child: PageView.builder(
                controller: _controller,
                onPageChanged: _changePage,
                itemCount: _files.length,
                itemBuilder: (context, index) {
                  final file = _files[index];
                  // Do not mount off-screen players or conversion dialogs. Only
                  // the active page may decrypt, play, or interact with the user.
                  return KeyedSubtree(
                    key: ValueKey(file.id),
                    child: index == _index
                        ? _buildFile(file)
                        : Center(
                            child: Text(file.originalName,
                                textAlign: TextAlign.center)),
                  );
                },
              ),
            ),
          ),
          if (_files.length > 1)
            SafeArea(
              top: false,
              child: GestureDetector(
                key: const ValueKey('file-browser-navigation'),
                behavior: HitTestBehavior.opaque,
                // PDFs own pan/zoom gestures, so this strip also provides an
                // unobstructed swipe target without disrupting document reading.
                onHorizontalDragStart: (_) => _navigationDrag = 0,
                onHorizontalDragUpdate: (details) =>
                    _navigationDrag += details.primaryDelta ?? 0,
                onHorizontalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (_navigationDrag.abs() > 48 || velocity.abs() > 100) {
                    final delta =
                        _navigationDrag.abs() > 48 ? _navigationDrag : velocity;
                    final forward =
                        Directionality.of(context) == TextDirection.ltr
                            ? delta < 0
                            : delta > 0;
                    _goTo(_index + (forward ? 1 : -1));
                  }
                },
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous $_kind',
                      onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Semantics(
                        liveRegion: true,
                        label: '$_kind ${_index + 1} of ${_files.length}',
                        child: Text('${_index + 1} of ${_files.length}',
                            textAlign: TextAlign.center),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next $_kind',
                      onPressed: _index < _files.length - 1
                          ? () => _goTo(_index + 1)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFile(VaultedFile file) {
    return FutureBuilder<File>(
      future: _loads.putIfAbsent(file.id, () => _prepareFile(file)),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          if (file.isSong) {
            return SongPlayerScreen(
                file: file, decryptedFile: snapshot.data, embedded: true);
          }
          return DocumentViewerScreen(
            file: file,
            decryptedFile: snapshot.data,
            embedded: true,
            onFileSwipe: _files.length > 1
                ? (direction) {
                    if (_files[_index].id == file.id) {
                      _goTo(_index + direction);
                    }
                  }
                : null,
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text(file.originalName)),
          body: Center(
            child: snapshot.hasError
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Could not open this $_kind.'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => setState(() {
                          _loads.remove(file.id);
                          _tokens.remove(file.id);
                        }),
                        child: const Text('Try again'),
                      ),
                    ],
                  )
                : const CircularProgressIndicator(),
          ),
        );
      },
    );
  }
}
