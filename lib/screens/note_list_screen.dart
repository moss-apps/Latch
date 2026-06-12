import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/note.dart';
import '../models/encryption_algorithm.dart';
import '../providers/note_providers.dart';
import '../themes/app_colors.dart';
import '../utils/toast_utils.dart';
import '../widgets/note_card.dart';
import '../widgets/operation_progress_sheet.dart';
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
                  icon: Icon(Icons.folder_outlined, color: context.textSecondary),
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
            padding: const EdgeInsets.all(16),
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
                hintText: 'Search notes...',
                hintStyle: TextStyle(
                  fontFamily: 'ProductSans',
                  color: context.textTertiary,
                ),
                prefixIcon: Icon(Icons.search, color: context.textTertiary),
                filled: true,
                fillColor: context.surfaceColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.borderColor),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.folder, size: 16, color: context.accentColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      foldersAsync.when(
                        data: (folders) {
                          final folder = folders.firstWhere(
                            (f) => f.id == selectedFolder,
                            orElse: () =>
                                NoteFolder(id: '', name: 'Unknown', createdAt: DateTime.now(), updatedAt: DateTime.now()),
                          );
                          return folder.name;
                        },
                        loading: () => 'Loading...',
                        error: (_, __) => 'Error',
                      ),
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        fontSize: 13,
                        color: context.textSecondary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      ref.read(selectedNoteFolderProvider.notifier).state = null;
                    },
                    child: Text(
                      'Clear',
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        fontSize: 12,
                        color: context.accentColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: notesAsync.when(
              data: (notes) {
                final filtered = _filterNotes(notes, searchQuery, selectedFolder);
                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.note_outlined,
                          size: 64,
                          color: context.textTertiary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          searchQuery.isNotEmpty
                              ? 'No notes found'
                              : 'No notes yet',
                          style: TextStyle(
                            fontFamily: 'ProductSans',
                            fontSize: 16,
                            color: context.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.4,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final note = filtered[index];
                    final isSelected = _selectedNoteIds.contains(note.id);
                    return NoteCard(
                      note: note,
                      isSelected: isSelected,
                      onTap: () {
                        if (_isSelectionMode) {
                          setState(() {
                            if (isSelected) {
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
              onPressed: _showNewNoteSheet,
              backgroundColor: context.accentColor,
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
          onPressed: () => _showDeleteConfirmation(),
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

  void _showNewNoteSheet() {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    bool isSaving = false;
    String selectedFormat = 'txt';
    bool encrypt = false;
    EncryptionAlgorithm selectedAlgorithm = EncryptionAlgorithm.aes256Gcm;
    int selectedKdfIterations = 100000;
    const kdfOptions = [100000, 200000, 500000];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: context.borderColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'New Note',
                                    style: TextStyle(
                                      fontFamily: 'ProductSans',
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      color: context.textPrimary,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: isSaving
                                      ? null
                                      : () async {
                                          if (titleController.text
                                              .trim()
                                              .isEmpty) {
                                            ToastUtils.showError(
                                                'Title cannot be empty');
                                            return;
                                          }
                                          setSheetState(
                                              () => isSaving = true);

                                          Navigator.pop(context);

                                          final progressState =
                                              ValueNotifier<OperationProgressState>(
                                            OperationProgressState(
                                              totalFiles: 1,
                                              currentFile: 0,
                                              currentFileName:
                                                  titleController.text.trim(),
                                              totalSizeBytes: contentController
                                                  .text.length,
                                              processedSizeBytes: 0,
                                              statusMessage: 'Preparing...',
                                              isProcessing: true,
                                              isEncrypting: encrypt,
                                              isComplete: false,
                                            ),
                                          );

                                          if (!mounted) return;
                                          showModalBottomSheet(
                                            context: this.context,
                                            backgroundColor: Colors.transparent,
                                            isDismissible: false,
                                            enableDrag: false,
                                            builder: (ctx) =>
                                                ValueListenableBuilder<
                                                    OperationProgressState>(
                                              valueListenable: progressState,
                                              builder: (ctx, state, _) =>
                                                  OperationProgressSheet(
                                                operationType:
                                                    OperationType.hide,
                                                totalFiles: state.totalFiles,
                                                currentFile: state.currentFile,
                                                currentFileName:
                                                    state.currentFileName,
                                                totalSizeBytes:
                                                    state.totalSizeBytes,
                                                processedSizeBytes:
                                                    state.processedSizeBytes,
                                                statusMessage:
                                                    state.statusMessage,
                                                isProcessing: state.isProcessing,
                                                isComplete: state.isComplete,
                                                isEncrypting: state.isEncrypting,
                                              ),
                                            ),
                                          );

                                          try {
                                            await ref
                                                .read(notesNotifierProvider
                                                    .notifier)
                                                .createNote(
                                              title: titleController.text.trim(),
                                              content: contentController.text,
                                              fileExtension: selectedFormat,
                                              isMarkdown: selectedFormat == 'md',
                                              encrypt: encrypt,
                                              encryptionAlgorithm: encrypt
                                                  ? selectedAlgorithm
                                                  : EncryptionAlgorithm
                                                      .aes256Gcm,
                                              kdfIterations:
                                                  selectedKdfIterations,
                                              onProgress: (status,
                                                  {isEncrypting = false}) {
                                                progressState.value =
                                                    progressState.value.copyWith(
                                                  statusMessage: status,
                                                  isEncrypting: isEncrypting,
                                                  currentFile: 1,
                                                  processedSizeBytes:
                                                      isEncrypting
                                                          ? (progressState
                                                                  .value
                                                                  .processedSizeBytes +
                                                              (contentController
                                                                      .text
                                                                      .length ~/
                                                                      3))
                                                          : progressState.value
                                                              .processedSizeBytes,
                                                );
                                              },
                                            );
                                            progressState.value =
                                                progressState.value.copyWith(
                                              isProcessing: false,
                                              isComplete: true,
                                              statusMessage: 'Completed',
                                              processedSizeBytes: progressState
                                                  .value.totalSizeBytes,
                                            );
                                          } catch (e) {
                                            if (!mounted) return;
                                            Navigator.pop(this.context);
                                            ToastUtils.showError(
                                                'Failed to create note');
                                          }
                                        },
                                  child: Text(
                                    'Save',
                                    style: TextStyle(
                                      fontFamily: 'ProductSans',
                                      color: context.accentColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Text(
                                  'Format: ',
                                  style: TextStyle(
                                    fontFamily: 'ProductSans',
                                    fontSize: 13,
                                    color: context.textSecondary,
                                  ),
                                ),
                                ...['txt', 'md', 'html'].map((fmt) {
                                  final isSelected = fmt == selectedFormat;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      label: Text(
                                        '.$fmt',
                                        style: TextStyle(
                                          fontFamily: 'ProductSans',
                                          fontSize: 12,
                                          color: isSelected
                                              ? Colors.white
                                              : context.textSecondary,
                                        ),
                                      ),
                                      selected: isSelected,
                                      onSelected: (_) {
                                        setSheetState(
                                            () => selectedFormat = fmt);
                                      },
                                      selectedColor: context.accentColor,
                                      backgroundColor:
                                          context.backgroundColor,
                                      side: BorderSide(
                                        color: isSelected
                                            ? context.accentColor
                                            : context.borderColor,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  );
                                }),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.lock_outline,
                                    size: 16, color: context.textSecondary),
                                const SizedBox(width: 6),
                                Text(
                                  'Encrypt',
                                  style: TextStyle(
                                    fontFamily: 'ProductSans',
                                    fontSize: 13,
                                    color: context.textSecondary,
                                  ),
                                ),
                                const Spacer(),
                                Switch(
                                  value: encrypt,
                                  activeTrackColor: context.accentColor,
                                  onChanged: (v) =>
                                      setSheetState(() => encrypt = v),
                                ),
                              ],
                            ),
                            if (encrypt) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Algorithm',
                                style: TextStyle(
                                  fontFamily: 'ProductSans',
                                  fontSize: 13,
                                  color: context.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: EncryptionAlgorithm.values.map((algo) {
                                  final isSelected = algo == selectedAlgorithm;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      label: Text(
                                        algo.displayName,
                                        style: TextStyle(
                                          fontFamily: 'ProductSans',
                                          fontSize: 12,
                                          color: isSelected
                                              ? Colors.white
                                              : context.textSecondary,
                                        ),
                                      ),
                                      selected: isSelected,
                                      onSelected: (_) => setSheetState(
                                          () => selectedAlgorithm = algo),
                                      selectedColor: context.accentColor,
                                      backgroundColor: context.backgroundColor,
                                      side: BorderSide(
                                        color: isSelected
                                            ? context.accentColor
                                            : context.borderColor,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'KDF iterations',
                                style: TextStyle(
                                  fontFamily: 'ProductSans',
                                  fontSize: 13,
                                  color: context.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: kdfOptions.map((kdf) {
                                  final isSelected = kdf == selectedKdfIterations;
                                  final label = kdf == 100000
                                      ? '${(kdf / 1000).round()}K'
                                      : '${(kdf / 1000).round()}K';
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      label: Text(
                                        label,
                                        style: TextStyle(
                                          fontFamily: 'ProductSans',
                                          fontSize: 12,
                                          color: isSelected
                                              ? Colors.white
                                              : context.textSecondary,
                                        ),
                                      ),
                                      selected: isSelected,
                                      onSelected: (_) => setSheetState(
                                          () => selectedKdfIterations = kdf),
                                      selectedColor: context.accentColor,
                                      backgroundColor: context.backgroundColor,
                                      side: BorderSide(
                                        color: isSelected
                                            ? context.accentColor
                                            : context.borderColor,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                            const SizedBox(height: 8),
                            TextField(
                              controller: titleController,
                              style: TextStyle(
                                fontFamily: 'ProductSans',
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: context.textPrimary,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Title',
                                hintStyle: TextStyle(
                                  fontFamily: 'ProductSans',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: context.textTertiary,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            Divider(color: context.dividerColor),
                            SizedBox(
                              height: 200,
                              child: TextField(
                                controller: contentController,
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
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showDeleteConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.surfaceColor,
        title: Text(
          'Delete Notes',
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
        ),
        content: Text(
          'Delete ${_selectedNoteIds.length} note(s)? This cannot be undone.',
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
