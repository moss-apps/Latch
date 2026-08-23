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

  Future<List<Note>> loadNotes({bool isDecoy = false}) async {
    final cached = _notesCache[isDecoy];
    if (cached != null) return cached;
    if (!isDecoy) await _migrateLegacyNotes();
    final json = await _secureStorage.read(
      key: isDecoy ? _notesIndexDecoyKey : _notesIndexKey,
    );
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
    _notesCache[isDecoy] = notes;
    return notes;
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

  Future<void> _saveNotes({bool isDecoy = false}) async {
    final notes = _notesCache[isDecoy];
    if (notes == null) return;
    final json = jsonEncode(notes.map((n) => n.toJson()).toList());
    await _secureStorage.write(
      key: isDecoy ? _notesIndexDecoyKey : _notesIndexKey,
      value: json,
    );
  }

  Future<List<NoteFolder>> loadFolders({bool isDecoy = false}) async {
    final cached = _foldersCache[isDecoy];
    if (cached != null) return cached;
    final json = await _secureStorage.read(
      key: isDecoy ? _noteFoldersDecoyKey : _noteFoldersKey,
    );
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
    return _encryptionService.deriveFileKeyAsync(masterKey, salt, note.kdfIterations);
  }

  Future<Note> createNote({
    required String title,
    required String content,
    String? folderId,
    bool isMarkdown = false,
    String fileExtension = 'txt',
    bool encrypt = false,
    EncryptionAlgorithm encryptionAlgorithm = EncryptionAlgorithm.aes256Gcm,
    int kdfIterations = _defaultKdfIterations,
    bool isDecoy = false,
    void Function(String status, {bool isEncrypting})? onProgress,
  }) async {
    onProgress?.call('Preparing...', isEncrypting: false);
    await _ensureNotesDir(isDecoy: isDecoy);
    final notes = await loadNotes(isDecoy: isDecoy);

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
      final masterKey = await _encryptionService.getMasterKey(isDecoy: isDecoy);
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
      final filePath = '$notesDir/$id.$fileExtension';
      final file = File(filePath);
      await file.writeAsString(content);
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
      isEncrypted: encrypt,
      encryptionAlgorithm: encryptionAlgorithm,
      createdAt: now,
      updatedAt: now,
    );

    notes.insert(0, note);
    await _saveNotes(isDecoy: isDecoy);

    await VaultService.instance.registerNoteEntry(
      noteId: note.id,
      title: note.title,
      encryptedContentPath: note.encryptedContentPath,
      fileExtension: fileExtension,
      isEncrypted: encrypt,
      encryptionAlgorithm: encryptionAlgorithm,
      kdfIterations: kdfIterations,
      folderId: note.folderId,
      isDecoy: isDecoy,
    );

    return note;
  }

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

  Future<Note> updateNote(
    Note note, {
    String? title,
    String? content,
    String? folderId,
    bool? clearFolder,
    bool? isMarkdown,
    String fileExtension = 'txt',
    bool encrypt = false,
    EncryptionAlgorithm? encryptionAlgorithm,
    int? kdfIterations,
    bool isDecoy = false,
  }) async {
    final notes = await loadNotes(isDecoy: isDecoy);
    final algorithm = encryptionAlgorithm ?? note.encryptionAlgorithm;
    final kdf = kdfIterations ?? note.kdfIterations;

    var updated = note.copyWith(
      title: title,
      folderId: folderId,
      clearFolder: clearFolder,
      isMarkdown: isMarkdown,
      isEncrypted: encrypt || note.isEncrypted,
      encryptionAlgorithm: algorithm,
      updatedAt: DateTime.now(),
    );

    if (content != null) {
      if (updated.isEncrypted) {
        final masterKey = await _encryptionService.getMasterKey(isDecoy: isDecoy);
        final salt = _encryptionService.generateFileSalt();
        final derivedKey = await _encryptionService.deriveFileKeyAsync(
          masterKey,
          salt,
          kdf,
        );

        final data = Uint8List.fromList(utf8.encode(content));
        // write to temp then rename so a failed re-encrypt can't destroy the only copy
        final tmpPath = '${note.encryptedContentPath}.tmp';
        final result = algorithm == EncryptionAlgorithm.aes256Gcm
            ? await _encryptionService.encryptBytesStreamedGcm(
                data,
                tmpPath,
                isDecoy: isDecoy,
                derivedKey: derivedKey,
              )
            : await _encryptionService.encryptBytesStreamed(
                data,
                tmpPath,
                isDecoy: isDecoy,
                derivedKey: derivedKey,
              );

        if (!result.success) {
          final tmp = File(tmpPath);
          if (await tmp.exists()) await tmp.delete();
          throw Exception('Failed to re-encrypt note content');
        }

        await File(tmpPath).rename(note.encryptedContentPath);
        updated = updated.copyWith(
          iv: result.iv,
          keyDerivationSalt: base64Encode(salt),
          kdfIterations: kdf,
        );
      } else {
        final file = File(note.encryptedContentPath);
        await file.writeAsString(content);
      }
    }

    final index = notes.indexWhere((n) => n.id == note.id);
    if (index != -1) {
      notes[index] = updated;
      await _saveNotes(isDecoy: isDecoy);

      await VaultService.instance.registerNoteEntry(
        noteId: updated.id,
        title: updated.title,
        encryptedContentPath: updated.encryptedContentPath,
        fileExtension: fileExtension,
        isEncrypted: updated.isEncrypted,
        encryptionAlgorithm: updated.encryptionAlgorithm,
        kdfIterations: updated.kdfIterations,
        folderId: updated.folderId,
        isDecoy: isDecoy,
      );
    }

    return updated;
  }

  Future<void> deleteNote(Note note, {bool isDecoy = false}) async {
    final notes = await loadNotes(isDecoy: isDecoy);
    if (note.isEncrypted) {
      await _encryptionService.secureDelete(note.encryptedContentPath);
    } else {
      final file = File(note.encryptedContentPath);
      if (await file.exists()) await file.delete();
    }
    notes.removeWhere((n) => n.id == note.id);
    await _saveNotes(isDecoy: isDecoy);

    await VaultService.instance.removeNoteEntry(note.id, isDecoy: isDecoy);
  }

  Future<void> deleteNotes(List<Note> notes, {bool isDecoy = false}) async {
    final cached = await loadNotes(isDecoy: isDecoy);
    for (final note in notes) {
      if (note.isEncrypted) {
        await _encryptionService.secureDelete(note.encryptedContentPath);
      } else {
        final file = File(note.encryptedContentPath);
        if (await file.exists()) await file.delete();
      }
    }
    final ids = notes.map((n) => n.id).toSet();
    cached.removeWhere((n) => ids.contains(n.id));
    await _saveNotes(isDecoy: isDecoy);

    for (final note in notes) {
      await VaultService.instance.removeNoteEntry(note.id, isDecoy: isDecoy);
    }
  }

  Future<Note> togglePin(Note note, {bool isDecoy = false}) async {
    final notes = await loadNotes(isDecoy: isDecoy);
    final toggled = note.togglePin();
    final index = notes.indexWhere((n) => n.id == note.id);
    if (index != -1) {
      notes[index] = toggled;
      await _saveNotes(isDecoy: isDecoy);
    }
    return toggled;
  }

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

  Future<void> deleteFolder(NoteFolder folder, {bool isDecoy = false}) async {
    final folders = await loadFolders(isDecoy: isDecoy);
    final notes = await loadNotes(isDecoy: isDecoy);

    for (var i = 0; i < notes.length; i++) {
      if (notes[i].folderId == folder.id) {
        notes[i] = notes[i].copyWith(
          clearFolder: true,
          updatedAt: DateTime.now(),
        );
      }
    }
    await _saveNotes(isDecoy: isDecoy);

    folders.removeWhere((f) => f.id == folder.id);
    await _saveFolders(isDecoy: isDecoy);
  }

  List<Note> getNotesInFolder(String? folderId) {
    return _notesCache[false]
            ?.where((n) => n.folderId == folderId)
            .toList() ??
        [];
  }

  List<Note> searchNotes(String query) {
    final notes = _notesCache[false];
    if (notes == null) return [];
    final lower = query.toLowerCase();
    return notes
        .where((n) => n.title.toLowerCase().contains(lower))
        .toList();
  }

  void clearCache() {
    _notesCache.clear();
    _foldersCache.clear();
  }
}
