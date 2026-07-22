import 'vaulted_file.dart';
import 'vault_folder.dart';
import 'encryption_algorithm.dart';

/// Helper class for batch file import
class FileToVault {
  final String sourcePath;
  final String originalName;
  final VaultedFileType type;
  final String mimeType;
  final bool? encrypt;
  final EncryptionAlgorithm? encryptionAlgorithm;
  final int? kdfIterations;

  const FileToVault({
    required this.sourcePath,
    required this.originalName,
    required this.type,
    required this.mimeType,
    this.encrypt,
    this.encryptionAlgorithm,
    this.kdfIterations,
  });
}

/// Result of importing a device folder
class FolderImportResult {
  final int foldersCreated;
  final int filesImported;
  final List<String> errors;
  final VaultFolder? rootFolder;

  const FolderImportResult({
    required this.foldersCreated,
    required this.filesImported,
    this.errors = const [],
    this.rootFolder,
  });
}
