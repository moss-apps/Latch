import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/vaulted_file.dart';
import 'vault_service.dart';
import 'diagnostics.dart';
import 'encryption_service.dart';

/// Backup run result: success, zip path, or error message.
class BackupResult {
  final bool success;
  final String? zipPath;
  final String? error;
  final String? diagnosticId;

  const BackupResult({
    required this.success,
    this.zipPath,
    this.error,
    this.diagnosticId,
  });
}

/// Builds a decrypted ZIP of the vault; one job only.
class BackupService {
  BackupService({VaultService? vaultService})
      : _vaultService = vaultService ?? VaultService.instance;

  static final BackupService instance = BackupService();
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
    File? partial;
    ZipFileEncoder? encoder;
    var closed = false;
    final crypto = EncryptionService.instance;
    final generation = crypto.cacheGeneration;
    void checkSession() {
      if (!crypto.isCurrentSession(generation)) throw StateError('Vault session locked');
    }
    try {
      checkSession();
      final destination = await Directory(destinationDirPath).resolveSymbolicLinks();
      final documents = await getApplicationDocumentsDirectory();
      final support = await getApplicationSupportDirectory();
      final temporary = await getTemporaryDirectory();
      if ([documents.path, support.path, temporary.path].any((root) =>
          destination == root || destination.startsWith('$root/')) ||
          destination.contains('/Android/data/')) {
        return const BackupResult(success: false,
            error: 'Choose a folder outside Latch, such as Documents or a removable drive, so the backup survives uninstalling.');
      }
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
        encoder = ZipFileEncoder();
        final zipPath = '$destinationDirPath/${generateRandomZipName()}';
        partial = File('$zipPath.partial');
        encoder.create(partial.path);

        final total = filesToBackup.length;
        int current = 0;
        final usedEntryNames = <String>{};

        for (final file in filesToBackup) {
          checkSession();
          final subdir = _subdirForType(file.type);
          final dir = Directory('${workDir.path}/$subdir');
          if (!await dir.exists()) await dir.create(recursive: true);

          final original = file.originalName.replaceAll('\\', '/').split('/').last;
          final baseName = original.isEmpty || original == '.' || original == '..' ? 'file' : original;
          final ext = baseName.contains('.') ? '.${baseName.split('.').last}' : '';
          final stem = ext.isEmpty
              ? baseName
              : baseName.substring(0, baseName.length - ext.length);
          var name = baseName;
          // Unique per ZIP entry: "a (2).jpg" can itself collide with a
          // dedupe-generated name, and duplicate ZIP entries lose data.
          var suffix = 1;
          while (!usedEntryNames.add('$subdir/$name')) {
            suffix++;
            name = '$stem ($suffix)$ext';
          }

          final destPath = '${dir.path}/$name';
          final exported = await _vaultService.exportFile(file.id, destPath);
          checkSession();
          if (exported != null && await exported.exists()) {
            final entryName = '$subdir/$name';
            await encoder.addFile(exported, entryName);
            try {
              await exported.delete();
            } catch (_) {}
          } else {
            throw const FileSystemException('A backup file could not be exported');
          }
          current++;
          onProgress?.call(current, total);
        }

        final passwordIndex = await _secureStorage.read(key: _passwordIndexKey);
        if (passwordIndex != null && passwordIndex.isNotEmpty) {
          final indexFile = File('${workDir.path}/$_passwordIndexEntry');
          await indexFile.writeAsString(passwordIndex);
          await encoder.addFile(indexFile, _passwordIndexEntry);
          try {
            await indexFile.delete();
          } catch (_) {}
        }

        await encoder.close();
        closed = true;
        checkSession();
        await partial.rename(zipPath);
        partial = null;
        Diagnostics.event('backup.finished', {'files': total});
        return BackupResult(success: true, zipPath: zipPath);
      } finally {
        try {
          await workDir.delete(recursive: true);
        } catch (e) {
          Diagnostics.failure('backup.cleanup', e, StackTrace.current);
        }
      }
    } catch (e, st) {
      final id = Diagnostics.failure('backup.failed', e, st);
      return BackupResult(
        success: false,
        diagnosticId: id,
        error: !crypto.isCurrentSession(generation)
            ? 'Backup stopped when the vault locked. Unlock it and try again.'
            : e.toString().toLowerCase().contains('no space')
            ? 'Not enough free space to create the backup'
            : 'Backup failed — check the destination and try again',
      );
    } finally {
      if (!closed && encoder != null) {
        try { await encoder.close(); } catch (_) {}
      }
      if (partial != null && await partial.exists()) {
        try { await partial.delete(); } catch (e, st) {
          Diagnostics.failure('backup.partialCleanup', e, st);
        }
      }
    }
  }
}
