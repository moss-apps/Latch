import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/password_entry.dart';
import '../models/encryption_algorithm.dart';
import 'encryption_service.dart';
import 'vault_service.dart';

class PasswordService {
  PasswordService._();
  static final PasswordService instance = PasswordService._();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final EncryptionService _encryptionService = EncryptionService.instance;

  static const String _indexKey = 'locker_passwords_index';
  static const String _decoyIndexKey = 'locker_passwords_index_decoy';
  static const String _dirName = 'passwords';
  static const int _defaultKdfIterations = 100000;

  final Map<bool, List<PasswordEntry>> _caches = {};

  List<String> _normalizedTags(List<String> tags) => tags
      .map((t) => t.toLowerCase().trim())
      .where((t) => t.isNotEmpty)
      .toSet()
      .toList();

  Future<String> _getDir({bool isDecoy = false}) async {
    final appDir = await getApplicationDocumentsDirectory();
    final baseDir = isDecoy ? '.locker_decoy' : '.locker_vault';
    return '${appDir.path}/$baseDir/$_dirName';
  }

  Future<void> _ensureDir({bool isDecoy = false}) async {
    final dir = Directory(await _getDir(isDecoy: isDecoy));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  Future<List<PasswordEntry>> loadPasswords({bool isDecoy = false}) async {
    final cached = _caches[isDecoy];
    if (cached != null) return cached;
    final json = await _secureStorage.read(
      key: isDecoy ? _decoyIndexKey : _indexKey,
    );
    if (json == null || json.isEmpty) {
      return _caches[isDecoy] = [];
    }
    try {
      final List<dynamic> decoded = jsonDecode(json) as List<dynamic>;
      return _caches[isDecoy] = decoded
          .map((e) => PasswordEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // ponytail: a corrupt index must throw, an empty list here would
      // silently overwrite every entry on the next _save
      throw Exception('Password index is corrupt: $e');
    }
  }

  Future<void> _save({bool isDecoy = false}) async {
    final entries = _caches[isDecoy];
    if (entries == null) return;
    final json = jsonEncode(entries.map((e) => e.toJson()).toList());
    await _secureStorage.write(
      key: isDecoy ? _decoyIndexKey : _indexKey,
      value: json,
    );
  }

  Future<Uint8List> _deriveKey(
    PasswordEntry entry, {
    bool isDecoy = false,
  }) async {
    final masterKey =
        await _encryptionService.getMasterKey(isDecoy: isDecoy);
    final salt = base64Decode(entry.keyDerivationSalt);
    return _encryptionService.deriveFileKeyAsync(
        masterKey, salt, entry.kdfIterations);
  }

  Future<PasswordEntry> createPassword({
    required String title,
    required PasswordContent content,
    List<String> tags = const [],
    EncryptionAlgorithm encryptionAlgorithm = EncryptionAlgorithm.aes256Gcm,
    int kdfIterations = _defaultKdfIterations,
    bool isDecoy = false,
    void Function(String status, {bool isEncrypting})? onProgress,
  }) async {
    onProgress?.call('Preparing...', isEncrypting: false);
    await _ensureDir(isDecoy: isDecoy);
    await loadPasswords(isDecoy: isDecoy);

    final id = const Uuid().v4();
    final now = DateTime.now();
    final dir = await _getDir(isDecoy: isDecoy);

    onProgress?.call('Encrypting...', isEncrypting: true);
    final filePath = '$dir/$id.enc';
    final masterKey =
        await _encryptionService.getMasterKey(isDecoy: isDecoy);
    final saltBytes = _encryptionService.generateFileSalt();
    final derivedKey = await _encryptionService.deriveFileKeyAsync(
      masterKey,
      saltBytes,
      kdfIterations,
    );

    final data = utf8.encode(content.toJsonString());
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
      throw Exception('Failed to encrypt password entry');
    }

    onProgress?.call('Registering in vault...', isEncrypting: false);
    final entry = PasswordEntry(
      id: id,
      title: title,
      encryptedContentPath: result.encryptedPath!,
      iv: result.iv!,
      keyDerivationSalt: base64Encode(saltBytes),
      kdfIterations: kdfIterations,
      tags: _normalizedTags(tags),
      isEncrypted: true,
      encryptionAlgorithm: encryptionAlgorithm,
      createdAt: now,
      updatedAt: now,
    );

    _caches[isDecoy]!.insert(0, entry);
    await _save(isDecoy: isDecoy);

    await VaultService.instance.registerPasswordEntry(
      passwordId: entry.id,
      title: entry.title,
      encryptedContentPath: entry.encryptedContentPath,
      tags: entry.tags,
      isEncrypted: true,
      encryptionAlgorithm: encryptionAlgorithm,
      kdfIterations: kdfIterations,
      isDecoy: isDecoy,
    );

    return entry;
  }

  Future<PasswordContent> decryptContent(
    PasswordEntry entry, {
    bool isDecoy = false,
  }) async {
    final derivedKey = await _deriveKey(entry, isDecoy: isDecoy);

    final result = entry.encryptionAlgorithm == EncryptionAlgorithm.aes256Gcm
        ? await _encryptionService.decryptStreamedFileToMemoryGcm(
            entry.encryptedContentPath,
            entry.iv,
            isDecoy: isDecoy,
            derivedKey: derivedKey,
          )
        : await _encryptionService.decryptStreamedFileToMemory(
            entry.encryptedContentPath,
            entry.iv,
            isDecoy: isDecoy,
            derivedKey: derivedKey,
          );

    if (!result.success || result.data == null) {
      throw Exception('Failed to decrypt password entry');
    }

    return PasswordContent.fromJsonString(utf8.decode(result.data!));
  }

  Future<PasswordEntry> updatePassword(
    PasswordEntry entry, {
    String? title,
    PasswordContent? content,
    List<String>? tags,
    EncryptionAlgorithm? encryptionAlgorithm,
    int? kdfIterations,
    bool isDecoy = false,
  }) async {
    final entries = await loadPasswords(isDecoy: isDecoy);
    final algorithm = encryptionAlgorithm ?? entry.encryptionAlgorithm;
    final iterations = kdfIterations ?? entry.kdfIterations;

    var updated = entry.copyWith(
      title: title,
      tags: tags == null ? null : _normalizedTags(tags),
      encryptionAlgorithm: algorithm,
      updatedAt: DateTime.now(),
    );

    if (content != null) {
      final masterKey =
          await _encryptionService.getMasterKey(isDecoy: isDecoy);
      final salt = _encryptionService.generateFileSalt();
      final derivedKey = await _encryptionService.deriveFileKeyAsync(
        masterKey,
        salt,
        iterations,
      );

      final data = utf8.encode(content.toJsonString());
      // ponytail: encrypt beside the original then swap, so a failed
      // re-encrypt can't destroy the only copy
      final tmpPath = '${entry.encryptedContentPath}.tmp';
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
        throw Exception('Failed to re-encrypt password entry');
      }

      await _encryptionService.secureDelete(entry.encryptedContentPath);
      await File(result.encryptedPath!).rename(entry.encryptedContentPath);

      updated = updated.copyWith(
        encryptedContentPath: entry.encryptedContentPath,
        iv: result.iv,
        keyDerivationSalt: base64Encode(salt),
        kdfIterations: iterations,
      );
    }

    final index = entries.indexWhere((e) => e.id == entry.id);
    if (index != -1) {
      entries[index] = updated;
      await _save(isDecoy: isDecoy);

      await VaultService.instance.registerPasswordEntry(
        passwordId: updated.id,
        title: updated.title,
        encryptedContentPath: updated.encryptedContentPath,
        tags: updated.tags,
        isEncrypted: true,
        encryptionAlgorithm: updated.encryptionAlgorithm,
        kdfIterations: updated.kdfIterations,
        isDecoy: isDecoy,
      );
    }

    return updated;
  }

  Future<void> deletePassword(PasswordEntry entry,
      {bool isDecoy = false}) async {
    await loadPasswords(isDecoy: isDecoy);
    await _encryptionService.secureDelete(entry.encryptedContentPath);
    _caches[isDecoy]!.removeWhere((e) => e.id == entry.id);
    await _save(isDecoy: isDecoy);
    await VaultService.instance.removePasswordEntry(entry.id, isDecoy: isDecoy);
  }

  Future<void> deletePasswords(List<PasswordEntry> entries,
      {bool isDecoy = false}) async {
    await loadPasswords(isDecoy: isDecoy);
    for (final entry in entries) {
      await _encryptionService.secureDelete(entry.encryptedContentPath);
    }
    final ids = entries.map((e) => e.id).toSet();
    _caches[isDecoy]!.removeWhere((e) => ids.contains(e.id));
    await _save(isDecoy: isDecoy);
    for (final entry in entries) {
      await VaultService.instance.removePasswordEntry(entry.id, isDecoy: isDecoy);
    }
  }

  Future<PasswordEntry> toggleFavorite(PasswordEntry entry,
      {bool isDecoy = false}) async {
    final entries = await loadPasswords(isDecoy: isDecoy);
    final toggled = entry.toggleFavorite();
    final index = entries.indexWhere((e) => e.id == entry.id);
    if (index != -1) {
      entries[index] = toggled;
      await _save(isDecoy: isDecoy);
    }
    return toggled;
  }

  void clearCache() {
    _caches.clear();
  }
}
