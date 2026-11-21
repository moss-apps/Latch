import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/note.dart';
import '../providers/note_providers.dart';
import '../providers/vault_providers.dart';
import '../themes/app_colors.dart';
import '../utils/note_text.dart';
import '../utils/toast_utils.dart';
import '../widgets/note_card.dart';
import 'note_editor_screen.dart';
import 'note_folders_screen.dart';

const _notesLayoutKey = 'notes_layout';

class NoteListScreen extends ConsumerStatefulWidget {
  const NoteListScreen({super.key});

  @override
  ConsumerState<NoteListScreen> createState() => _NoteListScreenState();
}

class _NoteListScreenState extends ConsumerState<NoteListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedNoteIds = {};
  bool _isSelectionMode = false;
  bool _isGrid = true;
  bool _layoutChanged = false;

  @override
  void initState() {
    super.initState();
    _searchController.text = ref.read(noteSearchQueryProvider);
    _loadLayoutPreference();
  }

  Future<void> _loadLayoutPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_notesLayoutKey);
      if (!mounted || _layoutChanged || saved == null) return;
      setState(() => _isGrid = saved != 'list');
    } catch (_) {
      // The default layout still works when preferences are unavailable.
    }
  }

  Future<void> _setGrid(bool isGrid) async {
    setState(() {
      _layoutChanged = true;
      _isGrid = isGrid;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_notesLayoutKey, isGrid ? 'grid' : 'list');
    } catch (_) {
      // Keep the current layout even if it can't be remembered.
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchQuery = ref.watch(noteSearchQueryProvider);
    ref.listen(noteSearchQueryProvider, (_, query) {
      if (_searchController.text != query) _searchController.text = query;
    });
    ref.listen(isDecoyModeProvider, (_, __) {
      if (_isSelectionMode) _exitSelectionMode();
    });
    final selectedFolder = ref.watch(selectedNoteFolderProvider);
    final notesAsync = ref.watch(notesNotifierProvider);
    final foldersAsync = ref.watch(noteFoldersNotifierProvider);
    final plaintextAsync = ref.watch(notePlaintextProvider);
    final plaintext = plaintextAsync.asData?.value ?? const <String, String>{};

    final folderName = selectedFolder == null
        ? null
        : foldersAsync.asData?.value
                .where((folder) => folder.id == selectedFolder)
                .firstOrNull
                ?.name ??
            'Folder';

    return PopScope(
        canPop: !_isSelectionMode,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _isSelectionMode) _exitSelectionMode();
        },
        child: Scaffold(
          backgroundColor: context.backgroundColor,
          appBar: _isSelectionMode
              ? _buildSelectionAppBar()
              : AppBar(
                  backgroundColor: context.backgroundColor,
                  elevation: 0,
                  leading: IconButton(
                    icon: Icon(Icons.arrow_back, color: context.textPrimary),
                    tooltip:
                        MaterialLocalizations.of(context).backButtonTooltip,
                    onPressed: () => Navigator.pop(context),
                  ),
                  title: Text(
                    'Notes',
                    style: TextStyle(
                      fontFamily: 'GoogleSansFlex',
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                  actions: [
                    IconButton(
                      icon: Icon(
                        Icons.folder_outlined,
                        color: context.textSecondary,
                      ),
                      tooltip: 'Folders',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NoteFoldersScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
          body: Column(
            children: [
              if (!_isSelectionMode)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: (value) {
                            ref.read(noteSearchQueryProvider.notifier).state =
                                value;
                          },
                          textInputAction: TextInputAction.search,
                          style: TextStyle(
                            fontFamily: 'GoogleSansFlex',
                            fontSize: 15,
                            color: context.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search notes',
                            hintStyle: TextStyle(
                              fontFamily: 'GoogleSansFlex',
                              color: context.textTertiary,
                            ),
                            prefixIcon: Icon(
                              Icons.search,
                              size: 20,
                              color: context.textTertiary,
                            ),
                            suffixIcon: searchQuery.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear search',
                                    icon: Icon(
                                      Icons.close,
                                      size: 18,
                                      color: context.textTertiary,
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
                                      ref
                                          .read(
                                              noteSearchQueryProvider.notifier)
                                          .state = '';
                                    },
                                  ),
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 12),
                            filled: true,
                            fillColor: context.surfaceColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color:
                                    context.dividerColor.withValues(alpha: 0.7),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide:
                                  BorderSide(color: context.accentColor),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _ToolbarButton(
                        icon: _isGrid
                            ? Icons.view_agenda_outlined
                            : Icons.grid_view_rounded,
                        tooltip: _isGrid ? 'List view' : 'Grid view',
                        onPressed: () => _setGrid(!_isGrid),
                      ),
                    ],
                  ),
                ),
              if (selectedFolder != null && !_isSelectionMode)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
                      decoration: BoxDecoration(
                        color: context.accentColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.folder,
                            size: 14,
                            color: context.accentColor,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 220),
                              child: Text(
                                folderName ?? 'Folder',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'GoogleSansFlex',
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: context.textPrimary,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              size: 15,
                              color: context.textSecondary,
                            ),
                            tooltip: 'Clear folder filter',
                            onPressed: () {
                              ref
                                  .read(selectedNoteFolderProvider.notifier)
                                  .state = null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: notesAsync.when(
                  data: (notes) {
                    final filtered = _filterNotes(
                        notes, searchQuery, selectedFolder, plaintext);
                    if (filtered.isEmpty) {
                      final waitingForBodyIndex =
                          searchQuery.trim().isNotEmpty &&
                              plaintextAsync.isLoading;
                      if (waitingForBodyIndex) {
                        return _NotesSkeleton(isGrid: _isGrid);
                      }
                      return _buildEmptyState(searchQuery, folderName);
                    }
                    return _buildNotesView(filtered, plaintext);
                  },
                  loading: () => _NotesSkeleton(isGrid: _isGrid),
                  error: (error, _) => Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 40,
                            color: context.textTertiary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Notes could not be loaded',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'GoogleSansFlex',
                              fontSize: 15,
                              color: context.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () => ref
                                .read(notesNotifierProvider.notifier)
                                .loadNotes(),
                            child: const Text(
                              'Try again',
                              style: TextStyle(fontFamily: 'GoogleSansFlex'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: _isSelectionMode
              ? null
              : FloatingActionButton(
                  onPressed: _createNote,
                  backgroundColor: context.accentColor,
                  foregroundColor: Colors.white,
                  elevation: 1,
                  tooltip: 'New note',
                  child: const Icon(Icons.add),
                ),
        ));
  }

  PreferredSizeWidget _buildSelectionAppBar() {
    return AppBar(
      backgroundColor: context.backgroundColor,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.close, color: context.textPrimary),
        tooltip: 'Exit selection',
        onPressed: _exitSelectionMode,
      ),
      title: Text(
        '${_selectedNoteIds.length} selected',
        style: TextStyle(
          fontFamily: 'GoogleSansFlex',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: context.textPrimary,
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.delete_outline, color: AppColors.error),
          tooltip: 'Delete selected notes',
          onPressed: _showDeleteConfirmation,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildNotesView(
    List<Note> notes,
    Map<String, String> plaintext,
  ) {
    final pinned = notes.where((note) => note.isPinned).toList();
    final others = notes.where((note) => !note.isPinned).toList();

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        if (pinned.isNotEmpty) ...[
          _sectionHeader('Pinned'),
          _sectionContent(pinned, plaintext),
        ],
        if (others.isNotEmpty) ...[
          if (pinned.isNotEmpty) _sectionHeader('Other notes'),
          if (pinned.isEmpty)
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
          _sectionContent(others, plaintext),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }

  Widget _sectionHeader(String label) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      sliver: SliverToBoxAdapter(
        child: Semantics(
            header: true,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'GoogleSansFlex',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                color: context.textSecondary,
              ),
            )),
      ),
    );
  }

  Widget _sectionContent(
    List<Note> notes,
    Map<String, String> plaintext,
  ) {
    if (_isGrid) {
      final width = MediaQuery.sizeOf(context).width;
      final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final crossAxisCount = width >= 900
          ? 4
          : width >= 620
              ? 3
              : (width < 300 || (width < 400 && textScale >= 2) ? 1 : 2);
      final cardHeight = (196 + (textScale - 1) * 92).clamp(196, 440);

      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: cardHeight.toDouble(),
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildCard(notes[index], plaintext),
            childCount: notes.length,
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildCard(notes[index], plaintext),
          ),
          childCount: notes.length,
        ),
      ),
    );
  }

  Widget _buildCard(Note note, Map<String, String> plaintext) {
    return NoteCard(
      key: ValueKey(note.id),
      note: note,
      preview: plaintext[note.id],
      isGrid: _isGrid,
      isSelected: _selectedNoteIds.contains(note.id),
      isSelectionMode: _isSelectionMode,
      onTap: () => _isSelectionMode ? _toggleSelection(note) : _openNote(note),
      onLongPress: _isSelectionMode ? null : () => _startSelection(note),
      onTogglePin: _isSelectionMode ? null : () => _togglePin(note),
      onDelete: _isSelectionMode ? null : () => _deleteNote(note),
    );
  }

  Widget _buildEmptyState(String searchQuery, String? folderName) {
    final searching = searchQuery.trim().isNotEmpty;
    final filtered = folderName != null;
    final title = searching
        ? 'No notes found'
        : filtered
            ? 'No notes in this folder'
            : 'No notes yet';
    final message = searching
        ? 'Try a different word, or search the note title.'
        : filtered
            ? 'New notes made here will start in $folderName.'
            : 'Capture a thought or a list. Notes stay in your vault.';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 96),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: context.surfaceColor,
                shape: BoxShape.circle,
                border: Border.all(color: context.dividerColor),
              ),
              child: Icon(
                searching ? Icons.search_off : Icons.sticky_note_2_outlined,
                size: 28,
                color: context.textTertiary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'GoogleSansFlex',
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'GoogleSansFlex',
                fontSize: 13.5,
                height: 1.45,
                color: context.textTertiary,
              ),
            ),
            const SizedBox(height: 18),
            if (searching && !_isSelectionMode)
              OutlinedButton(
                onPressed: () {
                  _searchController.clear();
                  ref.read(noteSearchQueryProvider.notifier).state = '';
                },
                child: const Text(
                  'Clear search',
                  style: TextStyle(fontFamily: 'GoogleSansFlex'),
                ),
              )
            else if (!_isSelectionMode)
              FilledButton.icon(
                onPressed: _createNote,
                icon: const Icon(Icons.add, size: 18),
                label: const Text(
                  'New note',
                  style: TextStyle(fontFamily: 'GoogleSansFlex'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Note> _filterNotes(
    List<Note> notes,
    String searchQuery,
    String? selectedFolder,
    Map<String, String> plaintext,
  ) {
    var filtered = List<Note>.of(notes);
    if (selectedFolder != null) {
      filtered = filtered.where((n) => n.folderId == selectedFolder).toList();
    }
    if (searchQuery.trim().isNotEmpty) {
      filtered = filtered
          .where((n) => noteMatchesQuery(
                searchQuery,
                n.title,
                n.isEncrypted ? null : plaintext[n.id],
              ))
          .toList();
    }
    filtered.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return filtered;
  }

  void _createNote() {
    final folderId = ref.read(selectedNoteFolderProvider);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(initialFolderId: folderId),
      ),
    );
  }

  void _openNote(Note note) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NoteEditorScreen(note: note)),
    );
  }

  void _startSelection(Note note) {
    FocusScope.of(context).unfocus();
    setState(() {
      _isSelectionMode = true;
      _selectedNoteIds.add(note.id);
    });
  }

  void _toggleSelection(Note note) {
    setState(() {
      if (_selectedNoteIds.contains(note.id)) {
        _selectedNoteIds.remove(note.id);
      } else {
        _selectedNoteIds.add(note.id);
      }
      if (_selectedNoteIds.isEmpty) _isSelectionMode = false;
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedNoteIds.clear();
    });
  }

  Future<void> _togglePin(Note note) async {
    try {
      await ref.read(notesNotifierProvider.notifier).togglePin(note);
    } catch (_) {
      if (mounted) ToastUtils.showError('Could not update pin');
    }
  }

  Future<void> _deleteNote(Note note) async {
    final isDecoy = ref.read(isDecoyModeProvider);
    if (!await _confirmDelete(1) ||
        !mounted ||
        ref.read(isDecoyModeProvider) != isDecoy) {
      return;
    }
    try {
      await ref.read(notesNotifierProvider.notifier).deleteNote(note);
      if (mounted) ToastUtils.showSuccess('Note deleted');
    } catch (_) {
      if (mounted) ToastUtils.showError('Could not delete note');
    }
  }

  Future<void> _showDeleteConfirmation() async {
    final isDecoy = ref.read(isDecoyModeProvider);
    final notes =
        ref.read(notesNotifierProvider).asData?.value ?? const <Note>[];
    final toDelete =
        notes.where((n) => _selectedNoteIds.contains(n.id)).toList();
    if (toDelete.isEmpty ||
        !await _confirmDelete(toDelete.length) ||
        !mounted ||
        ref.read(isDecoyModeProvider) != isDecoy) {
      return;
    }
    try {
      await ref.read(notesNotifierProvider.notifier).deleteNotes(toDelete);
      if (mounted) {
        _exitSelectionMode();
        ToastUtils.showSuccess(
          toDelete.length == 1 ? 'Note deleted' : 'Notes deleted',
        );
      }
    } catch (_) {
      if (mounted) {
        _exitSelectionMode();
        ToastUtils.showError('Could not delete all selected notes');
      }
    }
  }

  Future<bool> _confirmDelete(int count) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        backgroundColor: context.surfaceColor,
        title: Text(
          count == 1 ? 'Delete note?' : 'Delete $count notes?',
          style: TextStyle(
            fontFamily: 'GoogleSansFlex',
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
        ),
        content: Text(
          count == 1
              ? 'Recover it in Recently Deleted when retention is enabled. If retention is set to immediate deletion, this cannot be undone.'
              : 'The selected notes can be recovered in Recently Deleted when retention is enabled. If retention is set to immediate deletion, this cannot be undone.',
          style: TextStyle(
            fontFamily: 'GoogleSansFlex',
            height: 1.4,
            color: context.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'GoogleSansFlex',
                color: context.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: TextStyle(
                fontFamily: 'GoogleSansFlex',
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
    return confirmed == true;
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: context.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: context.dividerColor.withValues(alpha: 0.7),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          icon: Icon(icon, size: 20, color: context.textSecondary),
          tooltip: tooltip,
          onPressed: onPressed,
        ),
      ),
    );
  }
}

class _NotesSkeleton extends StatefulWidget {
  final bool isGrid;

  const _NotesSkeleton({required this.isGrid});

  @override
  State<_NotesSkeleton> createState() => _NotesSkeletonState();
}

class _NotesSkeletonState extends State<_NotesSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final opacity = MediaQuery.disableAnimationsOf(context)
            ? 0.5
            : 0.35 + (_controller.value * 0.25);
        if (widget.isGrid) {
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent: 196,
            ),
            itemCount: 6,
            itemBuilder: (context, index) => _SkeletonCard(opacity: opacity),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 6,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SkeletonCard(opacity: opacity, isList: true),
          ),
        );
      },
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  final double opacity;
  final bool isList;

  const _SkeletonCard({required this.opacity, this.isList = false});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        height: isList ? 88 : null,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _line(context, widthFactor: 0.72, height: 14),
            const SizedBox(height: 12),
            _line(context, widthFactor: 0.95, height: 9),
            const SizedBox(height: 7),
            _line(context, widthFactor: 0.85, height: 9),
            if (!isList) ...[
              const SizedBox(height: 7),
              _line(context, widthFactor: 0.55, height: 9),
              const Spacer(),
              _line(context, widthFactor: 0.3, height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _line(
    BuildContext context, {
    required double widthFactor,
    required double height,
  }) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: context.textTertiary.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}
