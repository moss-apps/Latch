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
  static const String _notesDirName = 'notes';
  static const int _defaultKdfIterations = 100000;

  List<Note>? _cachedNotes;
  List<NoteFolder>? _cachedFolders;

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
    if (_cachedNotes != null) return _cachedNotes!;
    final json = await _secureStorage.read(key: _notesIndexKey);
    if (json == null || json.isEmpty) {
      _cachedNotes = [];
      return _cachedNotes!;
    }
    try {
      final List<dynamic> decoded = jsonDecode(json) as List<dynamic>;
      _cachedNotes = decoded
          .map((e) => Note.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _cachedNotes = [];
    }
    return _cachedNotes!;
  }

  Future<void> _saveNotes({bool isDecoy = false}) async {
    if (_cachedNotes == null) return;
    final json = jsonEncode(_cachedNotes!.map((n) => n.toJson()).toList());
    await _secureStorage.write(key: _notesIndexKey, value: json);
  }

  Future<List<NoteFolder>> loadFolders({bool isDecoy = false}) async {
    if (_cachedFolders != null) return _cachedFolders!;
    final json = await _secureStorage.read(key: _noteFoldersKey);
    if (json == null || json.isEmpty) {
      _cachedFolders = [];
      return _cachedFolders!;
    }
    try {
      final List<dynamic> decoded = jsonDecode(json) as List<dynamic>;
      _cachedFolders = decoded
          .map((e) => NoteFolder.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _cachedFolders = [];
    }
    return _cachedFolders!;
  }

  Future<void> _saveFolders() async {
    if (_cachedFolders == null) return;
    final json = jsonEncode(_cachedFolders!.map((f) => f.toJson()).toList());
    await _secureStorage.write(key: _noteFoldersKey, value: json);
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
    await loadNotes(isDecoy: isDecoy);

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

    _cachedNotes!.insert(0, note);
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
    EncryptionAlgorithm encryptionAlgorithm = EncryptionAlgorithm.aes256Gcm,
    int kdfIterations = _defaultKdfIterations,
    bool isDecoy = false,
  }) async {
    await loadNotes(isDecoy: isDecoy);

    var updated = note.copyWith(
      title: title,
      folderId: folderId,
      clearFolder: clearFolder,
      isMarkdown: isMarkdown,
      isEncrypted: encrypt || note.isEncrypted,
      encryptionAlgorithm: encryptionAlgorithm,
      updatedAt: DateTime.now(),
    );

    if (content != null) {
      if (updated.isEncrypted) {
        final masterKey = await _encryptionService.getMasterKey(isDecoy: isDecoy);
        final salt = _encryptionService.generateFileSalt();
        final derivedKey = await _encryptionService.deriveFileKeyAsync(
          masterKey,
          salt,
          kdfIterations,
        );

        final data = Uint8List.fromList(utf8.encode(content));
        final result = updated.encryptionAlgorithm == EncryptionAlgorithm.aes256Gcm
            ? await _encryptionService.encryptBytesStreamedGcm(
                data,
                note.encryptedContentPath,
                isDecoy: isDecoy,
                derivedKey: derivedKey,
              )
            : await _encryptionService.encryptBytesStreamed(
                data,
                note.encryptedContentPath,
                isDecoy: isDecoy,
                derivedKey: derivedKey,
              );

        if (!result.success) {
          throw Exception('Failed to re-encrypt note content');
        }

        updated = updated.copyWith(
          encryptedContentPath: result.encryptedPath,
          iv: result.iv,
          keyDerivationSalt: base64Encode(salt),
          kdfIterations: kdfIterations,
        );
      } else {
        final file = File(note.encryptedContentPath);
        await file.writeAsString(content);
      }
    }

    final index = _cachedNotes!.indexWhere((n) => n.id == note.id);
    if (index != -1) {
      _cachedNotes![index] = updated;
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
    await loadNotes(isDecoy: isDecoy);
    if (note.isEncrypted) {
      await _encryptionService.secureDelete(note.encryptedContentPath);
    } else {
      final file = File(note.encryptedContentPath);
      if (await file.exists()) await file.delete();
    }
    _cachedNotes!.removeWhere((n) => n.id == note.id);
    await _saveNotes(isDecoy: isDecoy);

    await VaultService.instance.removeNoteEntry(note.id, isDecoy: isDecoy);
  }

  Future<void> deleteNotes(List<Note> notes, {bool isDecoy = false}) async {
    await loadNotes(isDecoy: isDecoy);
    for (final note in notes) {
      if (note.isEncrypted) {
        await _encryptionService.secureDelete(note.encryptedContentPath);
      } else {
        final file = File(note.encryptedContentPath);
        if (await file.exists()) await file.delete();
      }
    }
    final ids = notes.map((n) => n.id).toSet();
    _cachedNotes!.removeWhere((n) => ids.contains(n.id));
    await _saveNotes(isDecoy: isDecoy);

    for (final note in notes) {
      await VaultService.instance.removeNoteEntry(note.id, isDecoy: isDecoy);
    }
  }

  Future<Note> togglePin(Note note, {bool isDecoy = false}) async {
    await loadNotes(isDecoy: isDecoy);
    final toggled = note.togglePin();
    final index = _cachedNotes!.indexWhere((n) => n.id == note.id);
    if (index != -1) {
      _cachedNotes![index] = toggled;
      await _saveNotes(isDecoy: isDecoy);
    }
    return toggled;
  }

  Future<NoteFolder> createFolder(String name, {bool isDecoy = false}) async {
    await loadFolders(isDecoy: isDecoy);
    final now = DateTime.now();
    final folder = NoteFolder(
      id: const Uuid().v4(),
      name: name,
      createdAt: now,
      updatedAt: now,
    );
    _cachedFolders!.add(folder);
    await _saveFolders();
    return folder;
  }

  Future<NoteFolder> renameFolder(
    NoteFolder folder,
    String newName, {
    bool isDecoy = false,
  }) async {
    await loadFolders(isDecoy: isDecoy);
    final renamed = folder.copyWith(name: newName, updatedAt: DateTime.now());
    final index = _cachedFolders!.indexWhere((f) => f.id == folder.id);
    if (index != -1) {
      _cachedFolders![index] = renamed;
      await _saveFolders();
    }
    return renamed;
  }

  Future<void> deleteFolder(NoteFolder folder, {bool isDecoy = false}) async {
    await loadFolders(isDecoy: isDecoy);
    await loadNotes(isDecoy: isDecoy);

    for (var i = 0; i < _cachedNotes!.length; i++) {
      if (_cachedNotes![i].folderId == folder.id) {
        _cachedNotes![i] = _cachedNotes![i].copyWith(
          clearFolder: true,
          updatedAt: DateTime.now(),
        );
      }
    }
    await _saveNotes(isDecoy: isDecoy);

    _cachedFolders!.removeWhere((f) => f.id == folder.id);
    await _saveFolders();
  }

  List<Note> getNotesInFolder(String? folderId) {
    if (_cachedNotes == null) return [];
    return _cachedNotes!.where((n) => n.folderId == folderId).toList();
  }

  List<Note> searchNotes(String query) {
    if (_cachedNotes == null) return [];
    final lower = query.toLowerCase();
    return _cachedNotes!
        .where((n) => n.title.toLowerCase().contains(lower))
        .toList();
  }

  void clearCache() {
    _cachedNotes = null;
    _cachedFolders = null;
  }
}
