import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note.dart';
import '../providers/note_providers.dart';
import '../providers/vault_providers.dart';
import '../themes/app_colors.dart';
import '../utils/note_text.dart';
import '../utils/toast_utils.dart';
import '../widgets/note_save_options_sheet.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  final Note? note;
  final String? initialFolderId;

  const NoteEditorScreen({
    super.key,
    this.note,
    this.initialFolderId,
  });

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final FocusNode _titleFocus = FocusNode();
  final FocusNode _bodyFocus = FocusNode();

  bool _isMarkdown = false;
  bool _showPreview = false;
  bool _isSaving = false;
  bool _isLoading = false;
  bool _loadFailed = false;
  bool _isLeaving = false;
  NoteSaveOptions _saveOptions = const NoteSaveOptions();
  bool _isPinned = false;
  late final bool _isDecoy;
  String? _folderId;
  String _originalContent = '';

  @override
  void initState() {
    super.initState();
    _isDecoy = ref.read(isDecoyModeProvider);
    final note = widget.note;
    if (note == null) {
      _folderId = widget.initialFolderId;
      return;
    }
    _isLoading = true;
    _titleController.text = note.title;
    _isMarkdown = note.isMarkdown;
    _isPinned = note.isPinned;
    _folderId = note.folderId;
    _loadContent();
  }

  Future<void> _loadContent() async {
    final note = widget.note;
    if (note == null) return;
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });
    try {
      final content = await ref
          .read(noteServiceProvider)
          .decryptNoteContent(note, isDecoy: _isDecoy);
      if (!mounted || ref.read(isDecoyModeProvider) != _isDecoy) return;
      setState(() {
        _contentController.text = content;
        _originalContent = content;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
      ToastUtils.showError('Could not open this note');
    }
  }

  bool get _canEdit => !_isLoading && !_loadFailed && !_isSaving && !_isLeaving;

  void _togglePreview() {
    FocusScope.of(context).unfocus();
    setState(() => _showPreview = !_showPreview);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _titleFocus.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  bool get _hasChanges {
    if (_isLoading || _loadFailed) return false;
    final note = widget.note;
    if (note == null) {
      return _titleController.text.trim().isNotEmpty ||
          _contentController.text.trim().isNotEmpty;
    }
    return _titleController.text != note.title ||
        _contentController.text != _originalContent ||
        _folderId != note.folderId ||
        _isMarkdown != note.isMarkdown ||
        _isPinned != note.isPinned;
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.note != null;
    final sameVault = ref.watch(isDecoyModeProvider) == _isDecoy;
    if (!sameVault) {
      // Never show or save a draft in a different vault.
      return Scaffold(appBar: AppBar());
    }
    final folders = _folderId == null
        ? null
        : ref.watch(noteFoldersNotifierProvider).asData?.value;
    final folderName = _folderId == null
        ? null
        : folders
                ?.where((folder) => folder.id == _folderId)
                .firstOrNull
                ?.name ??
            'Folder';

    return PopScope(
      canPop: !_isSaving && !_hasChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleExit();
      },
      child: Scaffold(
        backgroundColor: context.backgroundColor,
        appBar: AppBar(
          backgroundColor: context.backgroundColor,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: context.textPrimary),
            tooltip: 'Save and close',
            onPressed: _handleExit,
          ),
          title: Text(
            isEditing ? 'Edit note' : 'New note',
            style: TextStyle(
              fontFamily: 'GoogleSansFlex',
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: context.textSecondary,
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(
                _isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: _isPinned ? context.accentColor : context.textSecondary,
                size: 21,
              ),
              tooltip: _isPinned ? 'Unpin note' : 'Pin note',
              onPressed: _canEdit
                  ? () => setState(() => _isPinned = !_isPinned)
                  : null,
            ),
            if (_isMarkdown)
              IconButton(
                icon: Icon(
                  _showPreview
                      ? Icons.edit_outlined
                      : Icons.visibility_outlined,
                  color: _showPreview
                      ? context.accentColor
                      : context.textSecondary,
                  size: 21,
                ),
                tooltip: _showPreview ? 'Edit' : 'Preview',
                onPressed: _canEdit ? _togglePreview : null,
              ),
            Padding(
              padding: const EdgeInsets.only(right: 6, left: 2),
              child: TextButton(
                onPressed: _isSaving ? null : _handleExit,
                style: TextButton.styleFrom(
                  foregroundColor: context.accentColor,
                  minimumSize: const Size(56, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: _isSaving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.accentColor,
                        ),
                      )
                    : const Text(
                        'Done',
                        style: TextStyle(
                          fontFamily: 'GoogleSansFlex',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
        body: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: _loadFailed
                    ? _buildLoadError()
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                            child: TextField(
                              controller: _titleController,
                              focusNode: _titleFocus,
                              readOnly: !_canEdit,
                              onChanged: (_) => setState(() {}),
                              maxLines: 1,
                              textInputAction: TextInputAction.next,
                              onSubmitted: (_) => _bodyFocus.requestFocus(),
                              style: TextStyle(
                                fontFamily: 'GoogleSansFlex',
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                                height: 1.25,
                                color: context.textPrimary,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Title',
                                hintStyle: TextStyle(
                                  fontFamily: 'GoogleSansFlex',
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  color: context.textTertiary,
                                ),
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                isDense: true,
                              ),
                            ),
                          ),
                          if (folderName != null)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 10, 20, 0),
                                child: Container(
                                  padding:
                                      const EdgeInsets.fromLTRB(9, 4, 4, 4),
                                  decoration: BoxDecoration(
                                    color: context.accentColor
                                        .withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.folder,
                                        size: 13,
                                        color: context.accentColor,
                                      ),
                                      const SizedBox(width: 5),
                                      Flexible(
                                        child: Text(
                                          folderName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontFamily: 'GoogleSansFlex',
                                            fontSize: 12,
                                            color: context.textPrimary,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          Icons.close,
                                          size: 14,
                                          color: context.textSecondary,
                                        ),
                                        tooltip: 'Remove from folder',
                                        onPressed: _canEdit
                                            ? () => setState(
                                                  () => _folderId = null,
                                                )
                                            : null,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: _showPreview && _isMarkdown
                                ? Markdown(
                                    data: _contentController.text,
                                    padding: const EdgeInsets.fromLTRB(
                                        20, 4, 20, 24),
                                    styleSheet: _markdownStyle(context),
                                  )
                                : Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        20, 0, 20, 12),
                                    child: TextField(
                                      controller: _contentController,
                                      focusNode: _bodyFocus,
                                      readOnly: !_canEdit,
                                      onChanged: (_) => setState(() {}),
                                      autofocus: widget.note == null,
                                      maxLines: null,
                                      expands: true,
                                      textAlignVertical: TextAlignVertical.top,
                                      keyboardType: TextInputType.multiline,
                                      style: TextStyle(
                                        fontFamily: 'GoogleSansFlex',
                                        fontSize: 15.5,
                                        height: 1.55,
                                        color: context.textPrimary,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: 'Note',
                                        hintStyle: TextStyle(
                                          fontFamily: 'GoogleSansFlex',
                                          fontSize: 15.5,
                                          color: context.textTertiary,
                                        ),
                                        filled: false,
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        contentPadding: EdgeInsets.zero,
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                          ),
                        ],
                      ),
              ),
            ),
            if (_isLoading)
              Positioned.fill(
                child: Container(
                  color: context.backgroundColor.withValues(alpha: 0.72),
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(context.accentColor),
                    ),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar:
            _isLoading || _loadFailed ? null : _buildEditorToolbar(context),
      ),
    );
  }

  Widget _buildLoadError() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 40, color: context.textTertiary),
            const SizedBox(height: 12),
            Text(
              'This note could not be opened',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'GoogleSansFlex',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your note is still in the vault. Try again, or close without changes.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'GoogleSansFlex',
                fontSize: 13.5,
                height: 1.45,
                color: context.textTertiary,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _loadContent,
              child: const Text(
                'Try again',
                style: TextStyle(fontFamily: 'GoogleSansFlex'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorToolbar(BuildContext context) {
    final note = widget.note;
    final format = note == null
        ? _saveOptions.format
        : note.fileFormat ?? NoteFileFormat.fromPath(note.encryptedContentPath);
    final encrypted = note?.isEncrypted ?? _saveOptions.encrypt;
    final encryptionLabel = encrypted ? 'Encrypted' : 'Not encrypted';
    final summary = format == null
        ? encryptionLabel
        : '.${format.extension} · $encryptionLabel';
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: context.backgroundColor,
          border: Border(
            top: BorderSide(color: context.dividerColor),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            _EditorToolButton(
              icon: Icons.folder_outlined,
              tooltip: _folderId == null ? 'Add to folder' : 'Change folder',
              active: _folderId != null,
              onPressed: _canEdit ? _showFolderPicker : null,
            ),
            if (note != null) ...[
              const SizedBox(width: 6),
              _EditorToolButton(
                icon: Icons.text_snippet_outlined,
                tooltip: _isMarkdown ? 'Turn off Markdown' : 'Turn on Markdown',
                active: _isMarkdown,
                onPressed: _canEdit
                    ? () => setState(() {
                          _isMarkdown = !_isMarkdown;
                          if (!_isMarkdown) _showPreview = false;
                        })
                    : null,
              ),
            ],
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                heightFactor: 1,
                child: TextButton(
                  onPressed: _canEdit ? _showSaveOptions : null,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    foregroundColor: context.accentColor,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Save options', textAlign: TextAlign.end),
                      Text(
                        summary,
                        textAlign: TextAlign.end,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: context.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSaveOptions() async {
    FocusScope.of(context).unfocus();
    final note = widget.note;
    final service = ref.read(noteServiceProvider);
    final options = await showModalBottomSheet<NoteSaveOptions>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.surfaceColor,
      builder: (context) => Consumer(
        builder: (context, ref, _) => ref.watch(isDecoyModeProvider) != _isDecoy
            ? const SizedBox.shrink()
            : NoteSaveOptionsSheet(
                initialOptions: _saveOptions,
                existingNote: note,
                resolveExistingFormat: note == null
                    ? null
                    : () => service.resolveNoteFormat(note, isDecoy: _isDecoy),
              ),
      ),
    );
    if (!mounted ||
        options == null ||
        ref.read(isDecoyModeProvider) != _isDecoy) {
      return;
    }
    setState(() {
      _saveOptions = options;
      _isMarkdown = options.format == NoteFileFormat.markdown;
      if (!_isMarkdown) _showPreview = false;
    });
  }

  MarkdownStyleSheet _markdownStyle(BuildContext context) {
    return MarkdownStyleSheet(
      p: TextStyle(
        fontFamily: 'GoogleSansFlex',
        fontSize: 15.5,
        height: 1.55,
        color: context.textPrimary,
      ),
      h1: TextStyle(
        fontFamily: 'GoogleSansFlex',
        fontSize: 26,
        fontWeight: FontWeight.bold,
        color: context.textPrimary,
      ),
      h2: TextStyle(
        fontFamily: 'GoogleSansFlex',
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: context.textPrimary,
      ),
      h3: TextStyle(
        fontFamily: 'GoogleSansFlex',
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: context.textPrimary,
      ),
      code: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        color: context.accentColor,
        backgroundColor: context.surfaceColor,
      ),
      codeblockDecoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(8),
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: context.accentColor, width: 3),
        ),
      ),
    );
  }

  Future<void> _handleExit() async {
    if (_isLeaving || _isSaving) return;

    if (ref.read(isDecoyModeProvider) != _isDecoy || !_hasChanges) {
      _leave();
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);

    try {
      final notifier = ref.read(notesNotifierProvider.notifier);
      final note = widget.note;
      final content = _contentController.text;
      final encrypt = note?.isEncrypted ?? _saveOptions.encrypt;
      final derivedTitle = deriveNoteTitle(
        _titleController.text,
        encrypt ? '' : content,
        isMarkdown: _isMarkdown,
      );
      final title = derivedTitle.isNotEmpty ? derivedTitle : 'Untitled note';

      if (note != null) {
        await notifier.updateNote(
          note,
          title: title,
          content: content == _originalContent ? null : content,
          folderId: _folderId,
          clearFolder: _folderId == null && note.folderId != null,
          isMarkdown: _isMarkdown,
          isPinned: _isPinned,
        );
      } else {
        await notifier.createNote(
          title: title,
          content: content,
          folderId: _folderId,
          isMarkdown: _isMarkdown,
          isPinned: _isPinned,
          fileExtension: _saveOptions.format.extension,
          encrypt: _saveOptions.encrypt,
          encryptionAlgorithm: _saveOptions.algorithm,
          kdfIterations: _saveOptions.kdfIterations,
        );
      }
      if (!mounted) return;
      _leave();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ToastUtils.showError('Could not save note. Your draft is still open.');
    }
  }

  void _leave() {
    if (!mounted || _isLeaving || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _isLeaving = true;
    Navigator.of(context).pop();
  }

  Future<void> _showFolderPicker() async {
    FocusScope.of(context).unfocus();
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Consumer(builder: (context, ref, _) {
        if (ref.watch(isDecoyModeProvider) != _isDecoy) {
          return const SizedBox.shrink();
        }
        final folders = ref.watch(noteFoldersNotifierProvider);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: context.borderColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Row(
                    children: [
                      Text(
                        'Move to folder',
                        style: TextStyle(
                          fontFamily: 'GoogleSansFlex',
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 12),
                    children: [
                      ListTile(
                        leading: Icon(
                          Icons.folder_off_outlined,
                          color: context.textSecondary,
                        ),
                        title: Text(
                          'No folder',
                          style: TextStyle(
                            fontFamily: 'GoogleSansFlex',
                            color: context.textPrimary,
                          ),
                        ),
                        trailing: _folderId == null
                            ? Icon(
                                Icons.check,
                                color: context.accentColor,
                                size: 20,
                              )
                            : null,
                        onTap: () => Navigator.pop(context, ''),
                      ),
                      if (folders.isLoading)
                        const Center(child: CircularProgressIndicator())
                      else if (folders.hasError)
                        ListTile(
                          title: const Text('Folders could not be loaded'),
                          trailing: TextButton(
                            onPressed: () =>
                                ref.invalidate(noteFoldersNotifierProvider),
                            child: const Text('Retry'),
                          ),
                        )
                      else if (folders.asData!.value.isEmpty)
                        const ListTile(
                          title: Text('Create a folder from the Notes screen.'),
                        ),
                      ...(folders.asData?.value ?? const <NoteFolder>[]).map(
                        (folder) => ListTile(
                          leading: Icon(
                            Icons.folder_outlined,
                            color: context.accentColor,
                          ),
                          title: Text(
                            folder.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'GoogleSansFlex',
                              color: context.textPrimary,
                            ),
                          ),
                          trailing: _folderId == folder.id
                              ? Icon(
                                  Icons.check,
                                  color: context.accentColor,
                                  size: 20,
                                )
                              : null,
                          onTap: () => Navigator.pop(context, folder.id),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );

    if (mounted &&
        selected != null &&
        ref.read(isDecoyModeProvider) == _isDecoy) {
      setState(() => _folderId = selected.isEmpty ? null : selected);
    }
  }
}

class _EditorToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback? onPressed;

  const _EditorToolButton({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active
            ? context.accentColor.withValues(alpha: 0.13)
            : context.surfaceColor,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(
              icon,
              size: 19,
              color: active ? context.accentColor : context.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
