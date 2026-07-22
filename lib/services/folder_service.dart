import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../models/file_to_vault.dart';
import '../models/vault_folder.dart';
import '../models/vaulted_file.dart';
import 'file_service.dart';
import 'vault_store.dart';

/// Folder CRUD + importDeviceFolder. Splits out of `VaultService`.
class FolderService {
  final VaultStore _store;
  final FileService _fileService;

  FolderService(this._store, this._fileService);

  Future<List<VaultFolder>> getAllFolders() => _store.loadFolders();

  Future<VaultFolder?> getFolderById(String folderId) async {
    final folders = await _store.loadFolders();
    try {
      return folders.firstWhere((f) => f.id == folderId);
    } catch (e) {
      return null;
    }
  }

  Future<List<VaultFolder>> getRootFolders() async {
    final folders = await _store.loadFolders();
    return folders.where((f) => f.isRoot).toList();
  }

  Future<List<VaultFolder>> getSubfolders(String parentId) async {
    final folders = await _store.loadFolders();
    return folders.where((f) => f.parentId == parentId).toList();
  }

  Future<VaultFolder?> createFolder({
    required String name,
    String? parentId,
    String? description,
  }) async {
    try {
      final now = DateTime.now();
      final id = sha256
          .convert(utf8.encode('$name${now.millisecondsSinceEpoch}'))
          .toString()
          .substring(0, 16);

      final folder = VaultFolder(
        id: id,
        name: name,
        parentId: parentId,
        description: description,
        createdAt: now,
        updatedAt: now,
      );

      _store.cachedFolders ??= [];
      _store.cachedFolders!.add(folder);

      if (parentId != null) {
        final parentIndex = _store.cachedFolders!.indexWhere((f) => f.id == parentId);
        if (parentIndex != -1) {
          _store.cachedFolders![parentIndex] =
              _store.cachedFolders![parentIndex].addSubfolder(id);
        }
      }

      await _store.saveFolders();

      return folder;
    } catch (e) {
      debugPrint('Error creating folder: $e');
      return null;
    }
  }

  Future<VaultFolder?> updateFolder(VaultFolder updatedFolder) async {
    try {
      final folders = await _store.loadFolders();
      final index = folders.indexWhere((f) => f.id == updatedFolder.id);

      if (index == -1) return null;

      _store.cachedFolders![index] = updatedFolder.copyWith(updatedAt: DateTime.now());
      await _store.saveFolders();

      return _store.cachedFolders![index];
    } catch (e) {
      debugPrint('Error updating folder: $e');
      return null;
    }
  }

  Future<bool> deleteFolder(String folderId, {bool deleteContents = false}) async {
    try {
      final folders = await _store.loadFolders();
      final folder = folders.firstWhere(
        (f) => f.id == folderId,
        orElse: () => throw Exception('Folder not found'),
      );

      if (deleteContents) {
        for (final subfolderId in folder.subfolderIds) {
          await deleteFolder(subfolderId, deleteContents: true);
        }

        for (final fileId in folder.fileIds) {
          await _fileService.removeFile(fileId);
        }
      } else {
        for (final fileId in folder.fileIds) {
          final file = await _fileService.getFileById(fileId);
          if (file != null) {
            await _fileService.updateFile(file.removeFromFolder());
          }
        }

        for (final subfolderId in folder.subfolderIds) {
          final subfolder = await getFolderById(subfolderId);
          if (subfolder != null) {
            await updateFolder(subfolder.copyWith(parentId: folder.parentId));
            if (folder.parentId != null) {
              final parentIndex = _store.cachedFolders!.indexWhere((f) => f.id == folder.parentId);
              if (parentIndex != -1) {
                _store.cachedFolders![parentIndex] =
                    _store.cachedFolders![parentIndex].addSubfolder(subfolderId);
              }
            }
          }
        }
      }

      if (folder.parentId != null) {
        final parentIndex = _store.cachedFolders!.indexWhere((f) => f.id == folder.parentId);
        if (parentIndex != -1) {
          _store.cachedFolders![parentIndex] =
              _store.cachedFolders![parentIndex].removeSubfolder(folderId);
        }
      }

      _store.cachedFolders!.removeWhere((f) => f.id == folderId);
      await _store.saveFolders();

      return true;
    } catch (e) {
      debugPrint('Error deleting folder: $e');
      return false;
    }
  }

  Future<bool> addFileToFolder(String fileId, String folderId) async {
    try {
      final file = await _fileService.getFileById(fileId);
      if (file == null) return false;

      final folders = await _store.loadFolders();
      final folderIndex = folders.indexWhere((f) => f.id == folderId);
      if (folderIndex == -1) return false;

      if (file.folderId != null && file.folderId != folderId) {
        final oldFolderIndex = _store.cachedFolders!.indexWhere((f) => f.id == file.folderId);
        if (oldFolderIndex != -1) {
          _store.cachedFolders![oldFolderIndex] =
              _store.cachedFolders![oldFolderIndex].removeFile(fileId);
        }
      }

      _store.cachedFolders![folderIndex] = _store.cachedFolders![folderIndex].addFile(fileId);
      await _store.saveFolders();

      final updatedFile = file.addToFolder(folderId);
      await _fileService.updateFile(updatedFile);

      return true;
    } catch (e) {
      debugPrint('Error adding file to folder: $e');
      return false;
    }
  }

  Future<bool> removeFileFromFolder(String fileId, String folderId) async {
    try {
      final folders = await _store.loadFolders();
      final folderIndex = folders.indexWhere((f) => f.id == folderId);
      if (folderIndex == -1) return false;

      _store.cachedFolders![folderIndex] = _store.cachedFolders![folderIndex].removeFile(fileId);
      await _store.saveFolders();

      final file = await _fileService.getFileById(fileId);
      if (file != null && file.folderId == folderId) {
        await _fileService.updateFile(file.removeFromFolder());
      }

      return true;
    } catch (e) {
      debugPrint('Error removing file from folder: $e');
      return false;
    }
  }

  Future<List<VaultedFile>> getFilesInFolder(String folderId) async {
    final folder = await getFolderById(folderId);
    if (folder == null) return [];

    final files = await _fileService.getAllFiles();
    return files.where((f) => folder.fileIds.contains(f.id)).toList();
  }

  Future<FolderImportResult> importDeviceFolder(
    String deviceFolderPath, {
    String? parentFolderId,
    bool recursive = true,
    bool deleteOriginals = false,
    bool encrypt = false,
    bool isDecoy = false,
    Function(int current, int total)? onProgress,
    Function(String fileName, int fileNumber, int total)? onFileProgress,
  }) async {
    final deviceDir = Directory(deviceFolderPath);
    if (!await deviceDir.exists()) {
      return FolderImportResult(foldersCreated: 0, filesImported: 0, errors: ['Directory does not exist: $deviceFolderPath']);
    }

    final folderName = deviceDir.path.split('/').last;
    final folder = await createFolder(name: folderName, parentId: parentFolderId);
    if (folder == null) {
      return FolderImportResult(foldersCreated: 0, filesImported: 0, errors: ['Failed to create folder']);
    }

    int foldersCreated = 1;
    int filesImported = 0;
    final errors = <String>[];

    final allFiles = <FileToVault>[];
    final subfolderPaths = <String>[];

    await _collectFilesFromDirectory(
      deviceDir,
      allFiles: allFiles,
      subfolderPaths: subfolderPaths,
      recursive: recursive,
    );

    final totalFiles = allFiles.length;
    if (totalFiles > 0) {
      final importedFiles = await _fileService.addFiles(
        files: allFiles,
        deleteOriginals: deleteOriginals,
        encrypt: encrypt,
        isDecoy: isDecoy,
        onProgress: onProgress,
        onFileProgress: onFileProgress != null
            ? (info) => onFileProgress(info.fileName, info.current, info.total)
            : null,
      );

      for (final importedFile in importedFiles) {
        await addFileToFolder(importedFile.id, folder.id);
        filesImported++;
      }
    }

    if (recursive) {
      for (final subPath in subfolderPaths) {
        final subResult = await importDeviceFolder(
          subPath,
          parentFolderId: folder.id,
          recursive: true,
          deleteOriginals: deleteOriginals,
          encrypt: encrypt,
          isDecoy: isDecoy,
        );
        foldersCreated += subResult.foldersCreated;
        filesImported += subResult.filesImported;
        errors.addAll(subResult.errors);
      }
    }

    return FolderImportResult(
      foldersCreated: foldersCreated,
      filesImported: filesImported,
      errors: errors,
      rootFolder: folder,
    );
  }

  Future<void> _collectFilesFromDirectory(
    Directory dir, {
    required List<FileToVault> allFiles,
    required List<String> subfolderPaths,
    required bool recursive,
  }) async {
    try {
      await for (final entity in dir.list()) {
        if (entity is File) {
          final file = entity;
          final fileName = file.path.split('/').last;
          if (fileName.startsWith('.')) continue;

          final extension = fileName.contains('.')
              ? fileName.split('.').last.toLowerCase()
              : '';
          final mimeType = _getMimeTypeFromExtension(extension);
          final fileType = getFileTypeFromExtension(extension);

          allFiles.add(FileToVault(
            sourcePath: file.path,
            originalName: fileName,
            type: fileType,
            mimeType: mimeType,
          ));
        } else if (entity is Directory && recursive) {
          final dirName = entity.path.split('/').last;
          if (dirName.startsWith('.')) continue;
          subfolderPaths.add(entity.path);
        }
      }
    } catch (e) {
      debugPrint('Error collecting files from directory: $e');
    }
  }

  String _getMimeTypeFromExtension(String extension) {
    const mimeMap = {
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
      'gif': 'image/gif', 'webp': 'image/webp', 'bmp': 'image/bmp',
      'heic': 'image/heic', 'heif': 'image/heif',
      'mp4': 'video/mp4', 'mov': 'video/quicktime', 'avi': 'video/x-msvideo',
      'mkv': 'video/x-matroska', 'webm': 'video/webm',
      'mp3': 'audio/mpeg', 'wav': 'audio/wav', 'flac': 'audio/flac',
      'aac': 'audio/aac', 'ogg': 'audio/ogg', 'm4a': 'audio/mp4',
      'pdf': 'application/pdf', 'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'txt': 'text/plain', 'rtf': 'application/rtf',
      'zip': 'application/zip', 'rar': 'application/x-rar-compressed',
      '7z': 'application/x-7z-compressed',
      'json': 'application/json', 'xml': 'application/xml',
      'csv': 'text/csv', 'html': 'text/html', 'htm': 'text/html',
    };
    return mimeMap[extension.toLowerCase()] ?? 'application/octet-stream';
  }
}