import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/note.dart';
import '../models/encryption_algorithm.dart';
import 'encryption_service.dart';
import 'file_operation_gate.dart';
import 'vault_service.dart';

class NoteService {
  NoteService._();
  static final NoteService instance = NoteService._();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final EncryptionService _encryptionService = EncryptionService.instance;

  static const String _notesIndexKey = 'locker_notes_index';
  static const String _noteFoldersKey = 'locker_note_folders';
  static const String _notesIndexDecoyKey = 'locker_notes_index_decoy';
  static const String _noteFoldersDecoyKey = 'locker_note_folders_decoy';
  static const String _notesDirName = 'notes';
  static const int _defaultKdfIterations = 100000;

  final Map<bool, List<Note>> _notesCache = {};
  int _cacheGeneration = 0;
  final Map<bool, List<NoteFolder>> _foldersCache = {};

  Future<String> _getNotesDir({bool isDecoy = false}) async {
    final appDir = await getApplicationDocumentsDirectory();
    final baseDir = isDecoy ? '.locker_decoy' : '.locker_vault';
    return '${appDir.path}/$baseDir/$_notesDirName';
  }

  Future<void> _ensureNotesDir({bool isDecoy = false}) async {
    final dir = Directory(await _getNotesDir(isDecoy: isDecoy));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  Future<List<Note>> loadNotes({
    bool isDecoy = false,
    bool forceReload = false,
  }) async {
    final generation = _cacheGeneration;
    final cached = _notesCache[isDecoy];
    if (!forceReload && cached != null) {
      final visible = await _visibleNotes(cached, isDecoy);
      if (generation != _cacheGeneration) {
        throw StateError('Notes session changed');
      }
      return _notesCache[isDecoy] = visible;
    }
    if (!isDecoy) await _migrateLegacyNotes();
    final json = await _secureStorage.read(
      key: isDecoy ? _notesIndexDecoyKey : _notesIndexKey,
    );
    if (generation != _cacheGeneration) {
      throw StateError('Notes session changed');
    }
    final notes = <Note>[];
    if (json != null && json.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(json) as List<dynamic>;
        for (final e in decoded) {
          try {
            notes.add(Note.fromJson(e as Map<String, dynamic>));
          } catch (_) {
            // skip malformed entry, keep the rest
          }
        }
      } catch (_) {
        // index unreadable; keep loaded list empty
      }
    }
    final visible = await _visibleNotes(notes, isDecoy);
    if (generation != _cacheGeneration) {
      throw StateError('Notes session changed');
    }
    _notesCache[isDecoy] = visible;
    return _notesCache[isDecoy]!;
  }

  Future<List<Note>> _visibleNotes(List<Note> notes, bool decoy) async {
    final records = await VaultService.instance.store.visibleEditorRecords(
        notes.map((n) => n.toJson()).toList(), 'noteId',
        isDecoy: decoy);
    return records.map(Note.fromJson).toList();
  }

  // ponytail: one-time split of the pre-decoy-fix shared index; remove later
  Future<void> _migrateLegacyNotes() async {
    if (await _secureStorage.read(key: _notesIndexDecoyKey) != null) return;
    final json = await _secureStorage.read(key: _notesIndexKey);
    if (json == null || json.isEmpty) return;
    List<dynamic> decoded;
    try {
      decoded = jsonDecode(json) as List<dynamic>;
    } catch (_) {
      return;
    }
    final real = <Map<String, dynamic>>[];
    final decoy = <Map<String, dynamic>>[];
    for (final e in decoded) {
      if (e is! Map<String, dynamic>) continue;
      final path = e['encryptedContentPath'] as String?;
      if (path != null && path.contains('/.locker_decoy/')) {
        decoy.add(e);
      } else {
        real.add(e);
      }
    }
    if (decoy.isEmpty) return;
    await _secureStorage.write(key: _notesIndexKey, value: jsonEncode(real));
    await _secureStorage.write(
      key: _notesIndexDecoyKey,
      value: jsonEncode(decoy),
    );
  }

  Future<void> _saveNotes(List<Note> notes, {required bool isDecoy}) async {
    final json = jsonEncode(notes.map((n) => n.toJson()).toList());
    await _secureStorage.write(
      key: isDecoy ? _notesIndexDecoyKey : _notesIndexKey,
      value: json,
    );
  }

  Future<List<NoteFolder>> loadFolders({
    bool isDecoy = false,
    bool forceReload = false,
  }) async {
    final generation = _cacheGeneration;
    final cached = _foldersCache[isDecoy];
    if (!forceReload && cached != null) return cached;
    final json = await _secureStorage.read(
      key: isDecoy ? _noteFoldersDecoyKey : _noteFoldersKey,
    );
    if (generation != _cacheGeneration) {
      throw StateError('Notes session changed');
    }
    final folders = <NoteFolder>[];
    if (json != null && json.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(json) as List<dynamic>;
        for (final e in decoded) {
          try {
            folders.add(NoteFolder.fromJson(e as Map<String, dynamic>));
          } catch (_) {
            // skip malformed entry, keep the rest
          }
        }
      } catch (_) {
        // index unreadable; keep loaded list empty
      }
    }
    _foldersCache[isDecoy] = folders;
    return folders;
  }

  Future<void> _saveFolders({bool isDecoy = false}) async {
    final folders = _foldersCache[isDecoy];
    if (folders == null) return;
    final json = jsonEncode(folders.map((f) => f.toJson()).toList());
    await _secureStorage.write(
      key: isDecoy ? _noteFoldersDecoyKey : _noteFoldersKey,
      value: json,
    );
  }

  Future<Uint8List> _deriveKey(Note note, {bool isDecoy = false}) async {
    final masterKey = await _encryptionService.getMasterKey(isDecoy: isDecoy);
    final salt = base64Decode(note.keyDerivationSalt);
    return _encryptionService.deriveFileKeyAsync(
        masterKey, salt, note.kdfIterations);
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
    int kdfIterations = _defaultKdfIterations,
    bool isDecoy = false,
    void Function(String status, {bool isEncrypting})? onProgress,
  }) =>
      _mutate(() async {
        final format = NoteFileFormat.fromExtension(fileExtension);
        if (format == null) {
          throw ArgumentError.value(fileExtension, 'fileExtension');
        }
        final generation = _cacheGeneration;
        onProgress?.call('Preparing...', isEncrypting: false);
        await _ensureNotesDir(isDecoy: isDecoy);
        final notes = await loadNotes(isDecoy: isDecoy, forceReload: true);

        final id = const Uuid().v4();
        final now = DateTime.now();
        final notesDir = await _getNotesDir(isDecoy: isDecoy);

        String contentPath;
        String iv;
        String salt;
        int kdf;

        if (encrypt) {
          onProgress?.call('Encrypting note...', isEncrypting: true);
          final filePath = '$notesDir/$id.enc';
          final masterKey =
              await _encryptionService.getMasterKey(isDecoy: isDecoy);
          final saltBytes = _encryptionService.generateFileSalt();
          final derivedKey = await _encryptionService.deriveFileKeyAsync(
            masterKey,
            saltBytes,
            kdfIterations,
          );

          final data = Uint8List.fromList(utf8.encode(content));
          final result = encryptionAlgorithm == EncryptionAlgorithm.aes256Gcm
              ? await _encryptionService.encryptBytesStreamedGcm(
                  data,
                  filePath,
                  isDecoy: isDecoy,
                  derivedKey: derivedKey,
                )
              : await _encryptionService.encryptBytesStreamed(
                  data,
                  filePath,
                  isDecoy: isDecoy,
                  derivedKey: derivedKey,
                );

          if (!result.success) {
            throw Exception('Failed to encrypt note content');
          }

          contentPath = result.encryptedPath!;
          iv = result.iv!;
          salt = base64Encode(saltBytes);
          kdf = kdfIterations;
        } else {
          onProgress?.call('Saving note...', isEncrypting: false);
          final filePath = '$notesDir/$id.${format.extension}';
          final file = File(filePath);
          try {
            await file.writeAsString(content, flush: true);
          } catch (_) {
            await _deleteIfPossible(file);
            rethrow;
          }
          contentPath = filePath;
          iv = '';
          salt = '';
          kdf = 0;
        }

        onProgress?.call('Registering in vault...', isEncrypting: false);
        final note = Note(
          id: id,
          title: title,
          encryptedContentPath: contentPath,
          iv: iv,
          keyDerivationSalt: salt,
          kdfIterations: kdf,
          folderId: folderId,
          isMarkdown: isMarkdown,
          fileFormat: format,
          isPinned: isPinned,
          isEncrypted: encrypt,
          encryptionAlgorithm: encryptionAlgorithm,
          createdAt: now,
          updatedAt: now,
        );

        final updatedNotes = [note, ...notes];
        try {
          _checkSession(generation);
          await _saveNotes(updatedNotes, isDecoy: isDecoy);
        } catch (_) {
          await _deleteIfPossible(File(contentPath));
          rethrow;
        }
        if (generation == _cacheGeneration) _notesCache[isDecoy] = updatedNotes;

        await VaultService.instance.registerNoteEntry(
          noteId: note.id,
          title: note.title,
          encryptedContentPath: note.encryptedContentPath,
          fileExtension: format.extension,
          isEncrypted: note.isEncrypted,
          encryptionAlgorithm: note.encryptionAlgorithm,
          kdfIterations: note.kdfIterations,
          folderId: note.folderId,
          isDecoy: isDecoy,
        );

        return note;
      });

  Future<String> decryptNoteContent(Note note, {bool isDecoy = false}) async {
    if (!note.isEncrypted) {
      final file = File(note.encryptedContentPath);
      if (!await file.exists()) {
        throw Exception('Note file not found');
      }
      return await file.readAsString();
    }

    final derivedKey = await _deriveKey(note, isDecoy: isDecoy);

    final result = note.encryptionAlgorithm == EncryptionAlgorithm.aes256Gcm
        ? await _encryptionService.decryptStreamedFileToMemoryGcm(
            note.encryptedContentPath,
            note.iv,
            isDecoy: isDecoy,
            derivedKey: derivedKey,
          )
        : await _encryptionService.decryptStreamedFileToMemory(
            note.encryptedContentPath,
            note.iv,
            isDecoy: isDecoy,
            derivedKey: derivedKey,
          );

    if (!result.success || result.data == null) {
      throw Exception('Failed to decrypt note: ${result.error}');
    }

    return utf8.decode(result.data!);
  }

  Future<NoteFileFormat> resolveNoteFormat(Note note,
      {bool isDecoy = false}) async {
    final knownFormat =
        note.fileFormat ?? NoteFileFormat.fromPath(note.encryptedContentPath);
    if (knownFormat != null) return knownFormat;

    // Older encrypted notes use .enc on disk. Their logical extension was
    // recorded only in the vault file entry.
    final files = await VaultService.instance.getAllFiles(isDecoy: isDecoy);
    final entry =
        files.where((file) => file.metadata?['noteId'] == note.id).firstOrNull;
    return (entry == null
            ? null
            : NoteFileFormat.fromPath(entry.originalName)) ??
        NoteFileFormat.plainText;
  }

  Future<Note> updateNote(
    Note note, {
    String? title,
    String? content,
    String? folderId,
    bool? clearFolder,
    bool? isMarkdown,
    bool? isPinned,
    bool isDecoy = false,
  }) =>
      _mutate(() async {
        final generation = _cacheGeneration;
        final notes = await loadNotes(isDecoy: isDecoy, forceReload: true);
        final index = notes.indexWhere((n) => n.id == note.id);
        if (index == -1) throw StateError('Note is no longer in this vault');
        final original = notes[index];
        final format = await resolveNoteFormat(original, isDecoy: isDecoy);
        final algorithm = original.encryptionAlgorithm;
        final kdf = original.kdfIterations;

        var updated = original.copyWith(
          title: title,
          folderId: folderId,
          clearFolder: clearFolder,
          isMarkdown: isMarkdown,
          fileFormat: format,
          isPinned: isPinned,
          updatedAt: DateTime.now(),
        );

        final path = original.encryptedContentPath;
        final suffix = const Uuid().v4();
        final staged = File('$path.$suffix.tmp');
        final backup = File('$path.$suffix.bak');
        var replaced = false;
        var keepBackup = false;
        try {
          if (content != null) {
            if (updated.isEncrypted) {
              final masterKey =
                  await _encryptionService.getMasterKey(isDecoy: isDecoy);
              final salt = _encryptionService.generateFileSalt();
              final derivedKey = await _encryptionService.deriveFileKeyAsync(
                masterKey,
                salt,
                kdf,
              );

              final data = Uint8List.fromList(utf8.encode(content));
              final result = algorithm == EncryptionAlgorithm.aes256Gcm
                  ? await _encryptionService.encryptBytesStreamedGcm(
                      data,
                      staged.path,
                      isDecoy: isDecoy,
                      derivedKey: derivedKey,
                    )
                  : await _encryptionService.encryptBytesStreamed(
                      data,
                      staged.path,
                      isDecoy: isDecoy,
                      derivedKey: derivedKey,
                    );

              if (!result.success) {
                throw Exception('Failed to re-encrypt note content');
              }

              updated = updated.copyWith(
                iv: result.iv,
                keyDerivationSalt: base64Encode(salt),
                kdfIterations: kdf,
              );
            } else {
              await staged.writeAsString(content, flush: true);
            }
            // Preserve the old payload until the new note metadata is durable.
            await File(path).copy(backup.path);
            _checkSession(generation);
            await staged.rename(path);
            replaced = true;
          }
          _checkSession(generation);
          final updatedNotes = [...notes]..[index] = updated;
          await _saveNotes(updatedNotes, isDecoy: isDecoy);
          if (generation == _cacheGeneration) {
            _notesCache[isDecoy] = updatedNotes;
          }
        } catch (_) {
          if (replaced) {
            keepBackup = true;
            await backup.rename(path);
            keepBackup = false;
          }
          rethrow;
        } finally {
          if (content != null) {
            await _deleteIfPossible(staged);
            if (!keepBackup) await _deleteIfPossible(backup);
          }
        }

        await VaultService.instance.registerNoteEntry(
          noteId: updated.id,
          title: updated.title,
          encryptedContentPath: updated.encryptedContentPath,
          fileExtension: format.extension,
          isEncrypted: updated.isEncrypted,
          encryptionAlgorithm: updated.encryptionAlgorithm,
          kdfIterations: updated.kdfIterations,
          folderId: updated.folderId,
          isDecoy: isDecoy,
        );
        return updated;
      }, fileIds: content == null ? const {} : {note.id});

  Future<T> _mutate<T>(Future<T> Function() action,
      {Set<String> fileIds = const {}}) {
    final gate = FileOperationGate.instance;
    final lease = gate.acquire(fileIds);
    if (lease == null) {
      return Future.error(StateError('Another vault change is in progress'));
    }
    return gate.run(lease, action);
  }

  void _checkSession(int generation) {
    if (generation != _cacheGeneration ||
        !FileOperationGate.instance.allowsMutation) {
      throw StateError('Notes session changed');
    }
  }

  Future<void> _deleteIfPossible(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Cleanup must not turn a committed save into a reported failure.
    }
  }

  Future<void> deleteNote(Note note, {bool isDecoy = false}) async {
    final files = await VaultService.instance.getAllFiles(isDecoy: isDecoy);
    final file =
        files.where((f) => f.metadata?['noteId'] == note.id).firstOrNull;
    if (file == null ||
        !await VaultService.instance.removeFile(file.id, isDecoy: isDecoy)) {
      clearCache();
      throw StateError(
          'Note deletion could not finish. Retry in Recently Deleted.');
    }
    clearCache();
  }

  Future<void> deleteNotes(List<Note> notes, {bool isDecoy = false}) async {
    for (final note in notes) {
      await deleteNote(note, isDecoy: isDecoy);
    }
  }

  Future<Note> togglePin(Note note, {bool isDecoy = false}) =>
      _mutate(() async {
        final generation = _cacheGeneration;
        final notes = await loadNotes(isDecoy: isDecoy, forceReload: true);
        final index = notes.indexWhere((n) => n.id == note.id);
        if (index == -1) throw StateError('Note is no longer in this vault');
        final toggled = notes[index].copyWith(
          isPinned: !note.isPinned,
          updatedAt: DateTime.now(),
        );
        final updatedNotes = [...notes]..[index] = toggled;
        _checkSession(generation);
        await _saveNotes(updatedNotes, isDecoy: isDecoy);
        if (generation == _cacheGeneration) _notesCache[isDecoy] = updatedNotes;
        return toggled;
      });

  Future<NoteFolder> createFolder(String name, {bool isDecoy = false}) async {
    final folders = await loadFolders(isDecoy: isDecoy);
    final now = DateTime.now();
    final folder = NoteFolder(
      id: const Uuid().v4(),
      name: name,
      createdAt: now,
      updatedAt: now,
    );
    folders.add(folder);
    await _saveFolders(isDecoy: isDecoy);
    return folder;
  }

  Future<NoteFolder> renameFolder(
    NoteFolder folder,
    String newName, {
    bool isDecoy = false,
  }) async {
    final folders = await loadFolders(isDecoy: isDecoy);
    final renamed = folder.copyWith(name: newName, updatedAt: DateTime.now());
    final index = folders.indexWhere((f) => f.id == folder.id);
    if (index != -1) {
      folders[index] = renamed;
      await _saveFolders(isDecoy: isDecoy);
    }
    return renamed;
  }

  Future<void> deleteFolder(NoteFolder folder, {bool isDecoy = false}) =>
      _mutate(() async {
        final generation = _cacheGeneration;
        final folders = await loadFolders(isDecoy: isDecoy);
        final notes = await loadNotes(isDecoy: isDecoy, forceReload: true);
        final updatedNotes = [
          for (final note in notes)
            note.folderId == folder.id
                ? note.copyWith(clearFolder: true)
                : note,
        ];
        _checkSession(generation);
        await _saveNotes(updatedNotes, isDecoy: isDecoy);
        if (generation == _cacheGeneration) _notesCache[isDecoy] = updatedNotes;

        _checkSession(generation);
        folders.removeWhere((f) => f.id == folder.id);
        await _saveFolders(isDecoy: isDecoy);
      });

  List<Note> getNotesInFolder(String? folderId) {
    return _notesCache[false]?.where((n) => n.folderId == folderId).toList() ??
        [];
  }

  /// Plaintext bodies for unencrypted notes, keyed by note id.
  ///
  /// Used by the list screen for previews and body search. Encrypted notes are
  /// deliberately absent: their content is only decrypted when opened.
  Future<Map<String, String>> loadPlaintextContents(List<Note> notes) async {
    final generation = _cacheGeneration;
    final contents = <String, String>{};
    for (final note in notes) {
      if (generation != _cacheGeneration) return const {};
      if (note.isEncrypted) continue;
      try {
        final file = File(note.encryptedContentPath);
        contents[note.id] = await file.readAsString();
      } on FileSystemException {
        // A missing or unreadable note should not hide the rest of the list.
      } on FormatException {
        // Skip a note whose contents are no longer valid UTF-8.
      }
    }
    return generation == _cacheGeneration ? contents : const {};
  }

  List<Note> searchNotes(String query) {
    final notes = _notesCache[false];
    if (notes == null) return [];
    final lower = query.toLowerCase();
    return notes.where((n) => n.title.toLowerCase().contains(lower)).toList();
  }

  void clearCache() {
    _cacheGeneration++;
    _notesCache.clear();
    _foldersCache.clear();
  }
}
