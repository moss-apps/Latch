import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/note.dart';
import '../providers/note_providers.dart';
import '../themes/app_colors.dart';
import '../utils/toast_utils.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  final Note? note;

  const NoteEditorScreen({super.key, this.note});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  bool _isMarkdown = false;
  bool _showPreview = false;
  bool _isSaving = false;
  bool _isLoading = false;
  bool _encrypt = false;
  String? _folderId;

  @override
  void initState() {
    super.initState();
    if (widget.note != null) {
      _isLoading = true;
      _titleController.text = widget.note!.title;
      _isMarkdown = widget.note!.isMarkdown;
      _folderId = widget.note!.folderId;
      _loadContent();
    }
  }

  Future<void> _loadContent() async {
    if (widget.note == null) return;
    try {
      final content =
          await ref.read(noteServiceProvider).decryptNoteContent(widget.note!);
      if (mounted) {
        setState(() {
          _contentController.text = content;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ToastUtils.showError('Failed to load note content');
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.note != null;

    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        backgroundColor: context.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isEditing ? 'Edit Note' : 'New Note',
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
        ),
        actions: [
          if (_isMarkdown)
            IconButton(
              icon: Icon(
                _showPreview ? Icons.edit : Icons.preview,
                color: context.textSecondary,
              ),
              onPressed: () {
                setState(() {
                  _showPreview = !_showPreview;
                });
              },
              tooltip: _showPreview ? 'Edit' : 'Preview',
            ),
          IconButton(
            icon: Icon(
              _isMarkdown ? Icons.text_snippet : Icons.text_fields,
              color: _isMarkdown ? context.accentColor : context.textSecondary,
            ),
            onPressed: () {
              setState(() {
                _isMarkdown = !_isMarkdown;
                if (!_isMarkdown) _showPreview = false;
              });
            },
            tooltip: _isMarkdown ? 'Plain text' : 'Markdown',
          ),
          if (!isEditing)
            IconButton(
              icon: Icon(
                _encrypt ? Icons.lock : Icons.lock_outline,
                color: _encrypt ? context.accentColor : context.textSecondary,
              ),
              onPressed: () {
                setState(() => _encrypt = !_encrypt);
              },
              tooltip: _encrypt ? 'Encrypted' : 'Encrypt note',
            ),
          IconButton(
            icon: Icon(Icons.folder_outlined, color: context.textSecondary),
            onPressed: _showFolderPicker,
            tooltip: 'Folder',
          ),
          IconButton(
            icon: Icon(Icons.check, color: context.accentColor),
            onPressed: _isSaving ? null : _saveNote,
            tooltip: 'Save',
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  controller: _titleController,
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Title',
                    hintStyle: TextStyle(
                      fontFamily: 'ProductSans',
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: context.textTertiary,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              if (_folderId != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(Icons.folder, size: 14, color: context.accentColor),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          ref.read(noteFoldersNotifierProvider).when(
                                data: (folders) {
                                  final folder = folders.firstWhere(
                                    (f) => f.id == _folderId,
                                    orElse: () => NoteFolder(
                                      id: '',
                                      name: 'Unknown',
                                      createdAt: DateTime.now(),
                                      updatedAt: DateTime.now(),
                                    ),
                                  );
                                  return folder.name;
                                },
                                loading: () => '...',
                                error: (_, __) => 'Error',
                              ),
                          style: TextStyle(
                            fontFamily: 'ProductSans',
                            fontSize: 12,
                            color: context.textTertiary,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close,
                            size: 14, color: context.textTertiary),
                        onPressed: () => setState(() => _folderId = null),
                        tooltip: 'Clear folder',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 36, minHeight: 36),
                      ),
                    ],
                  ),
                ),
              Divider(color: context.dividerColor),
              Expanded(
                child: _showPreview && _isMarkdown
                    ? Markdown(
                        data: _contentController.text,
                        styleSheet: MarkdownStyleSheet(
                          p: TextStyle(
                            fontFamily: 'ProductSans',
                            fontSize: 15,
                            color: context.textPrimary,
                          ),
                          h1: TextStyle(
                            fontFamily: 'ProductSans',
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimary,
                          ),
                          h2: TextStyle(
                            fontFamily: 'ProductSans',
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimary,
                          ),
                          h3: TextStyle(
                            fontFamily: 'ProductSans',
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
                              left: BorderSide(
                                color: context.accentColor,
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(16),
                        child: TextField(
                          controller: _contentController,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          style: TextStyle(
                            fontFamily: 'ProductSans',
                            fontSize: 15,
                            color: context.textPrimary,
                            height: 1.5,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Start writing...',
                            hintStyle: TextStyle(
                              fontFamily: 'ProductSans',
                              fontSize: 15,
                              color: context.textTertiary,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                      ),
              ),
            ],
          ),
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: context.backgroundColor.withValues(alpha: 0.7),
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(context.accentColor),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _saveNote() async {
    if (_titleController.text.trim().isEmpty) {
      ToastUtils.showError('Title cannot be empty');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final notifier = ref.read(notesNotifierProvider.notifier);
      if (widget.note != null) {
        await notifier.updateNote(
          widget.note!,
          title: _titleController.text.trim(),
          content: _contentController.text,
          folderId: _folderId,
          clearFolder: _folderId == null && widget.note!.folderId != null,
          isMarkdown: _isMarkdown,
        );
        if (mounted) ToastUtils.showSuccess('Note updated');
      } else {
        await notifier.createNote(
          title: _titleController.text.trim(),
          content: _contentController.text,
          folderId: _folderId,
          isMarkdown: _isMarkdown,
          encrypt: _encrypt,
        );
        if (mounted) ToastUtils.showSuccess('Note created');
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ToastUtils.showError('Failed to save note');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _showFolderPicker() async {
    final foldersAsync = ref.read(noteFoldersNotifierProvider);
    final folders = foldersAsync.whenOrNull(data: (f) => f) ?? [];

    if (folders.isEmpty) {
      ToastUtils.showInfo('Create a folder first');
      return;
    }

    final selected = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: context.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
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
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Select Folder',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
              ),
              ListTile(
                leading: Icon(Icons.folder_off_outlined,
                    color: context.textSecondary),
                title: Text(
                  'No Folder',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    color: context.textPrimary,
                  ),
                ),
                onTap: () => Navigator.pop(context, ''),
              ),
              ...folders.map((folder) => ListTile(
                    leading: Icon(Icons.folder, color: context.accentColor),
                    title: Text(
                      folder.name,
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        color: context.textPrimary,
                      ),
                    ),
                    onTap: () => Navigator.pop(context, folder.id),
                  )),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );

    if (selected != null) {
      setState(() => _folderId = selected.isEmpty ? null : selected);
    }
  }
}
