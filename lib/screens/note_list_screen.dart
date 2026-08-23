import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/note.dart';
import '../providers/note_providers.dart';
import '../themes/app_colors.dart';
import '../utils/toast_utils.dart';
import '../widgets/note_card.dart';
import 'note_editor_screen.dart';
import 'note_folders_screen.dart';

class NoteListScreen extends ConsumerStatefulWidget {
  const NoteListScreen({super.key});

  @override
  ConsumerState<NoteListScreen> createState() => _NoteListScreenState();
}

class _NoteListScreenState extends ConsumerState<NoteListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedNoteIds = {};
  bool _isSelectionMode = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchQuery = ref.watch(noteSearchQueryProvider);
    final selectedFolder = ref.watch(selectedNoteFolderProvider);
    final notesAsync = ref.watch(notesNotifierProvider);
    final foldersAsync = ref.watch(noteFoldersNotifierProvider);

    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: _isSelectionMode
          ? _buildSelectionAppBar()
          : AppBar(
              backgroundColor: context.backgroundColor,
              elevation: 0,
              automaticallyImplyLeading: false,
              title: Text(
                'Notes',
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
              actions: [
                IconButton(
                  icon: Icon(Icons.folder_outlined,
                      color: context.textSecondary),
                  tooltip: 'Folders',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NoteFoldersScreen(),
                    ),
                  ),
                ),
              ],
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                ref.read(noteSearchQueryProvider.notifier).state = value;
              },
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: context.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Search notes',
                hintStyle: TextStyle(
                  fontFamily: 'ProductSans',
                  color: context.textTertiary,
                ),
                prefixIcon:
                    Icon(Icons.search, size: 20, color: context.textTertiary),
                isDense: true,
                filled: true,
                fillColor: context.surfaceColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.accentColor),
                ),
              ),
            ),
          ),
          if (selectedFolder != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: Row(
                children: [
                  Icon(Icons.folder, size: 14, color: context.accentColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      foldersAsync.maybeWhen(
                        data: (folders) => folders
                            .where((f) => f.id == selectedFolder)
                            .fold('', (prev, f) => f.name),
                        orElse: () => '',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        fontSize: 13,
                        color: context.textSecondary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close,
                        size: 16, color: context.textTertiary),
                    tooltip: 'Clear folder filter',
                    onPressed: () {
                      ref.read(selectedNoteFolderProvider.notifier).state =
                          null;
                    },
                  ),
                ],
              ),
            ),
          Expanded(
            child: notesAsync.when(
              data: (notes) {
                final filtered =
                    _filterNotes(notes, searchQuery, selectedFolder);
                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.note_outlined,
                          size: 48,
                          color: context.textTertiary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          searchQuery.isNotEmpty
                              ? 'No notes found'
                              : 'No notes yet',
                          style: TextStyle(
                            fontFamily: 'ProductSans',
                            fontSize: 15,
                            color: context.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: context.dividerColor,
                  ),
                  itemBuilder: (context, index) {
                    final note = filtered[index];
                    return NoteCard(
                      note: note,
                      isSelected: _selectedNoteIds.contains(note.id),
                      isSelectionMode: _isSelectionMode,
                      onTap: () {
                        if (_isSelectionMode) {
                          setState(() {
                            if (_selectedNoteIds.contains(note.id)) {
                              _selectedNoteIds.remove(note.id);
                              if (_selectedNoteIds.isEmpty) {
                                _isSelectionMode = false;
                              }
                            } else {
                              _selectedNoteIds.add(note.id);
                            }
                          });
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => NoteEditorScreen(note: note),
                            ),
                          );
                        }
                      },
                      onLongPress: () {
                        if (!_isSelectionMode) {
                          setState(() {
                            _isSelectionMode = true;
                            _selectedNoteIds.add(note.id);
                          });
                        }
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Text(
                  'Error loading notes',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    color: context.textTertiary,
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
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NoteEditorScreen()),
              ),
              backgroundColor: context.accentColor,
              elevation: 0,
              child: const Icon(Icons.add, color: Colors.white),
            ),
    );
  }

  PreferredSizeWidget _buildSelectionAppBar() {
    return AppBar(
      backgroundColor: context.backgroundColor,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.close, color: context.textPrimary),
        onPressed: () {
          setState(() {
            _isSelectionMode = false;
            _selectedNoteIds.clear();
          });
        },
      ),
      title: Text(
        '${_selectedNoteIds.length} selected',
        style: TextStyle(
          fontFamily: 'ProductSans',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: context.textPrimary,
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.delete_outline, color: AppColors.error),
          onPressed: _showDeleteConfirmation,
        ),
      ],
    );
  }

  List<Note> _filterNotes(
    List<Note> notes,
    String searchQuery,
    String? selectedFolder,
  ) {
    var filtered = notes;
    if (selectedFolder != null) {
      filtered = filtered.where((n) => n.folderId == selectedFolder).toList();
    }
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      filtered = filtered
          .where((n) => n.title.toLowerCase().contains(query))
          .toList();
    }
    filtered.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return filtered;
  }

  Future<void> _showDeleteConfirmation() async {
    final count = _selectedNoteIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.surfaceColor,
        title: Text(
          count == 1 ? 'Delete Note' : 'Delete Notes',
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
        ),
        content: Text(
          'Delete $count ${count == 1 ? 'note' : 'notes'}? This cannot be undone.',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: context.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final notesAsync = ref.read(notesNotifierProvider);
      notesAsync.whenData((notes) async {
        final toDelete =
            notes.where((n) => _selectedNoteIds.contains(n.id)).toList();
        await ref.read(notesNotifierProvider.notifier).deleteNotes(toDelete);
        if (mounted) {
          setState(() {
            _isSelectionMode = false;
            _selectedNoteIds.clear();
          });
          ToastUtils.showSuccess('Notes deleted');
        }
      });
    }
  }
}
