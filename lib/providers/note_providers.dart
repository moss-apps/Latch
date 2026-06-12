import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../models/note.dart';
import '../models/encryption_algorithm.dart';
import '../services/note_service.dart';
import 'vault_providers.dart';

final noteServiceProvider = Provider<NoteService>((ref) {
  return NoteService.instance;
});

final noteSearchQueryProvider = StateProvider<String>((ref) => '');

final selectedNoteFolderProvider = StateProvider<String?>((ref) => null);

class NotesNotifier extends Notifier<AsyncValue<List<Note>>> {
  @override
  AsyncValue<List<Note>> build() {
    loadNotes();
    return const AsyncValue.loading();
  }

  NoteService get _noteService => ref.read(noteServiceProvider);

  bool get _isDecoy => ref.read(isDecoyModeProvider);

  Future<void> loadNotes() async {
    state = const AsyncValue.loading();
    try {
      _noteService.clearCache();
      final notes = await _noteService.loadNotes(isDecoy: _isDecoy);
      state = AsyncValue.data(notes);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<Note> createNote({
    required String title,
    required String content,
    String? folderId,
    bool isMarkdown = false,
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
      fileExtension: fileExtension,
      encrypt: encrypt,
      encryptionAlgorithm: encryptionAlgorithm,
      kdfIterations: kdfIterations,
      isDecoy: _isDecoy,
      onProgress: onProgress,
    );
    await loadNotes();
    _refreshVault();
    return note;
  }

  Future<Note> updateNote(
    Note note, {
    String? title,
    String? content,
    String? folderId,
    bool? clearFolder,
    bool? isMarkdown,
    String fileExtension = 'txt',
  }) async {
    final updated = await _noteService.updateNote(
      note,
      title: title,
      content: content,
      folderId: folderId,
      clearFolder: clearFolder,
      isMarkdown: isMarkdown,
      fileExtension: fileExtension,
      encrypt: note.isEncrypted,
      encryptionAlgorithm: note.encryptionAlgorithm,
      kdfIterations: note.kdfIterations,
      isDecoy: _isDecoy,
    );
    await loadNotes();
    _refreshVault();
    return updated;
  }

  Future<void> deleteNote(Note note) async {
    await _noteService.deleteNote(note, isDecoy: _isDecoy);
    await loadNotes();
    _refreshVault();
  }

  Future<void> deleteNotes(List<Note> notes) async {
    await _noteService.deleteNotes(notes, isDecoy: _isDecoy);
    await loadNotes();
    _refreshVault();
  }

  Future<Note> togglePin(Note note) async {
    final toggled = await _noteService.togglePin(note, isDecoy: _isDecoy);
    await loadNotes();
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
  @override
  AsyncValue<List<NoteFolder>> build() {
    loadFolders();
    return const AsyncValue.loading();
  }

  NoteService get _noteService => ref.read(noteServiceProvider);

  bool get _isDecoy => ref.read(isDecoyModeProvider);

  Future<void> loadFolders() async {
    state = const AsyncValue.loading();
    try {
      _noteService.clearCache();
      final folders = await _noteService.loadFolders(isDecoy: _isDecoy);
      state = AsyncValue.data(folders);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<NoteFolder> createFolder(String name) async {
    final folder = await _noteService.createFolder(name, isDecoy: _isDecoy);
    await loadFolders();
    return folder;
  }

  Future<NoteFolder> renameFolder(NoteFolder folder, String newName) async {
    final renamed = await _noteService.renameFolder(
      folder,
      newName,
      isDecoy: _isDecoy,
    );
    await loadFolders();
    return renamed;
  }

  Future<void> deleteFolder(NoteFolder folder) async {
    await _noteService.deleteFolder(folder, isDecoy: _isDecoy);
    await loadFolders();
  }
}

final noteFoldersNotifierProvider =
    NotifierProvider<NoteFoldersNotifier, AsyncValue<List<NoteFolder>>>(() {
  return NoteFoldersNotifier();
});
