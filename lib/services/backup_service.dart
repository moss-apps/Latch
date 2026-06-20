import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/vaulted_file.dart';
import 'vault_service.dart';

/// Backup run result: success, zip path, or error message.
class BackupResult {
  final bool success;
  final String? zipPath;
  final String? error;

  const BackupResult({
    required this.success,
    this.zipPath,
    this.error,
  });
}

/// Builds a decrypted ZIP of the vault; one job only.
class BackupService {
  BackupService._({VaultService? vaultService})
      : _vaultService = vaultService ?? VaultService.instance;

  static final BackupService instance = BackupService._();
  final VaultService _vaultService;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  static const String _zipPrefix = 'locker_';
  static const String _zipSuffix = '.zip';
  static const String _passwordIndexKey = 'locker_passwords_index';
  static const String _passwordIndexEntry = '_passwords_index.json';

  /// Map file type to ZIP subdir name (images/videos/documents).
  String _subdirForType(VaultedFileType type) {
    switch (type) {
      case VaultedFileType.image:
        return 'images';
      case VaultedFileType.video:
        return 'videos';
      case VaultedFileType.song:
        return 'songs';
      case VaultedFileType.document:
      case VaultedFileType.other:
        return 'documents';
    }
  }

  /// Random ZIP filename so backups don’t overwrite.
  String generateRandomZipName() {
    return '$_zipPrefix${const Uuid().v4().replaceAll('-', '')}$_zipSuffix';
  }

  /// ZIPs real vault files (decrypted) into [destinationDirPath] with a random name.
  Future<BackupResult> createBackup(
    String destinationDirPath, {
    List<VaultedFile>? files,
    void Function(int current, int total)? onProgress,
  }) async {
    try {
      final filesToBackup =
          files ?? await _vaultService.getAllFiles(isDecoy: false);
      if (filesToBackup.isEmpty) {
        return BackupResult(
          success: false,
          error: files == null
              ? 'No files in vault to backup'
              : 'No files selected for backup',
        );
      }

      final tempDir = await getTemporaryDirectory();
      final workDir = Directory(
          '${tempDir.path}/locker_backup_${DateTime.now().millisecondsSinceEpoch}');
      await workDir.create(recursive: true);

      try {
        final encoder = ZipFileEncoder();
        final zipPath = '$destinationDirPath/${generateRandomZipName()}';
        encoder.create(zipPath);

        final total = filesToBackup.length;
        int current = 0;
        final usedNames = <String, int>{};

        for (final file in filesToBackup) {
          final subdir = _subdirForType(file.type);
          final dir = Directory('${workDir.path}/$subdir');
          if (!await dir.exists()) await dir.create(recursive: true);

          final baseName = file.originalName;
          var name = baseName;
          final key = '$subdir/$baseName';
          final count = (usedNames[key] ?? 0) + 1;
          usedNames[key] = count;
          if (count > 1) {
            final ext = name.contains('.') ? '.${name.split('.').last}' : '';
            final withoutExt = ext.isEmpty
                ? name
                : name.substring(0, name.length - ext.length);
            name = '$withoutExt ($count)$ext';
          }

          final destPath = '${dir.path}/$name';
          final exported = await _vaultService.exportFile(file.id, destPath);
          if (exported != null && await exported.exists()) {
            final entryName = '$subdir/$name';
            await encoder.addFile(exported, entryName);
            try {
              await exported.delete();
            } catch (_) {}
          }
          current++;
          onProgress?.call(current, total);
        }

        final passwordIndex =
            await _secureStorage.read(key: _passwordIndexKey);
        if (passwordIndex != null && passwordIndex.isNotEmpty) {
          final indexFile = File('${workDir.path}/$_passwordIndexEntry');
          await indexFile.writeAsString(passwordIndex);
          await encoder.addFile(indexFile, _passwordIndexEntry);
          try {
            await indexFile.delete();
          } catch (_) {}
        }

        await encoder.close();
        return BackupResult(success: true, zipPath: zipPath);
      } finally {
        try {
          await workDir.delete(recursive: true);
        } catch (e) {
          debugPrint('BackupService: failed to delete temp dir: $e');
        }
      }
    } catch (e, st) {
      debugPrint('BackupService createBackup error: $e $st');
      return BackupResult(success: false, error: e.toString());
    }
  }
}
