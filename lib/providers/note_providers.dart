import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../models/note.dart';
import '../models/encryption_algorithm.dart';
import '../services/note_service.dart';
import 'vault_providers.dart';

final noteServiceProvider = Provider<NoteService>((ref) {
  return NoteService.instance;
});

final noteSearchQueryProvider = StateProvider<String>((ref) {
  ref.watch(isDecoyModeProvider);
  return '';
});

final selectedNoteFolderProvider = StateProvider<String?>((ref) {
  ref.watch(isDecoyModeProvider);
  return null;
});

/// Plaintext bodies of unencrypted notes, used for previews and body search.
final notePlaintextProvider =
    FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final notes = ref.watch(notesNotifierProvider).asData?.value;
  if (notes == null || notes.isEmpty) return const {};
  return ref.watch(noteServiceProvider).loadPlaintextContents(notes);
});

class NotesNotifier extends Notifier<AsyncValue<List<Note>>> {
  int _loadId = 0;

  @override
  AsyncValue<List<Note>> build() {
    _loadNotes(ref.watch(isDecoyModeProvider));
    return const AsyncValue.loading();
  }

  NoteService get _noteService => ref.read(noteServiceProvider);

  bool get _isDecoy => ref.read(isDecoyModeProvider);

  Future<void> loadNotes() {
    state = const AsyncValue.loading();
    return _loadNotes(_isDecoy);
  }

  Future<void> _loadNotes(bool isDecoy) async {
    final id = ++_loadId;
    try {
      final notes =
          await _noteService.loadNotes(isDecoy: isDecoy, forceReload: true);
      if (ref.mounted && id == _loadId && isDecoy == _isDecoy) {
        state = AsyncValue.data(notes);
      }
    } catch (e, st) {
      if (ref.mounted && id == _loadId && isDecoy == _isDecoy) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<Note> createNote({
    required String title,
    required String content,
    String? folderId,
    bool isMarkdown = false,
    bool isPinned = false,
    String fileExtension = 'txt',
    bool encrypt = false,
    EncryptionAlgorithm encryptionAlgorithm = EncryptionAlgorithm.aes256Gcm,
    int kdfIterations = 100000,
    void Function(String status, {bool isEncrypting})? onProgress,
  }) async {
    final note = await _noteService.createNote(
      title: title,
      content: content,
      folderId: folderId,
      isMarkdown: isMarkdown,
      isPinned: isPinned,
      fileExtension: fileExtension,
      encrypt: encrypt,
      encryptionAlgorithm: encryptionAlgorithm,
      kdfIterations: kdfIterations,
      isDecoy: _isDecoy,
      onProgress: onProgress,
    );
    if (ref.mounted) {
      await loadNotes();
      if (ref.mounted) _refreshVault();
    }
    return note;
  }

  Future<Note> updateNote(
    Note note, {
    String? title,
    String? content,
    String? folderId,
    bool? clearFolder,
    bool? isMarkdown,
    bool? isPinned,
  }) async {
    final updated = await _noteService.updateNote(
      note,
      title: title,
      content: content,
      folderId: folderId,
      clearFolder: clearFolder,
      isMarkdown: isMarkdown,
      isPinned: isPinned,
      isDecoy: _isDecoy,
    );
    if (ref.mounted) {
      await loadNotes();
      if (ref.mounted) _refreshVault();
    }
    return updated;
  }

  Future<void> deleteNote(Note note) async {
    await deleteNotes([note]);
  }

  Future<void> deleteNotes(List<Note> notes) async {
    try {
      await _noteService.deleteNotes(notes, isDecoy: _isDecoy);
    } finally {
      if (ref.mounted) {
        await loadNotes();
        if (ref.mounted) _refreshVault();
      }
    }
  }

  Future<Note> togglePin(Note note) async {
    final toggled = await _noteService.togglePin(note, isDecoy: _isDecoy);
    if (ref.mounted) await loadNotes();
    return toggled;
  }

  void _refreshVault() {
    ref.invalidate(vaultNotifierProvider);
  }
}

final notesNotifierProvider =
    NotifierProvider<NotesNotifier, AsyncValue<List<Note>>>(() {
  return NotesNotifier();
});

class NoteFoldersNotifier extends Notifier<AsyncValue<List<NoteFolder>>> {
  int _loadId = 0;

  @override
  AsyncValue<List<NoteFolder>> build() {
    _loadFolders(ref.watch(isDecoyModeProvider));
    return const AsyncValue.loading();
  }

  NoteService get _noteService => ref.read(noteServiceProvider);

  bool get _isDecoy => ref.read(isDecoyModeProvider);

  Future<void> loadFolders() {
    state = const AsyncValue.loading();
    return _loadFolders(_isDecoy);
  }

  Future<void> _loadFolders(bool isDecoy) async {
    final id = ++_loadId;
    try {
      final folders =
          await _noteService.loadFolders(isDecoy: isDecoy, forceReload: true);
      if (ref.mounted && id == _loadId && isDecoy == _isDecoy) {
        state = AsyncValue.data(folders);
      }
    } catch (e, st) {
      if (ref.mounted && id == _loadId && isDecoy == _isDecoy) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<NoteFolder> createFolder(String name) async {
    final folder = await _noteService.createFolder(name, isDecoy: _isDecoy);
    if (ref.mounted) await loadFolders();
    return folder;
  }

  Future<NoteFolder> renameFolder(NoteFolder folder, String newName) async {
    final renamed = await _noteService.renameFolder(
      folder,
      newName,
      isDecoy: _isDecoy,
    );
    if (ref.mounted) await loadFolders();
    return renamed;
  }

  Future<void> deleteFolder(NoteFolder folder) async {
    await _noteService.deleteFolder(folder, isDecoy: _isDecoy);
    if (!ref.mounted) return;
    if (ref.read(selectedNoteFolderProvider) == folder.id) {
      ref.read(selectedNoteFolderProvider.notifier).state = null;
    }
    ref.invalidate(notesNotifierProvider);
    await loadFolders();
  }
}

final noteFoldersNotifierProvider =
    NotifierProvider<NoteFoldersNotifier, AsyncValue<List<NoteFolder>>>(() {
  return NoteFoldersNotifier();
});
