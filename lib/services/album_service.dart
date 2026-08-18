import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../models/album.dart';
import '../models/vaulted_file.dart';
import 'file_service.dart';
import 'vault_store.dart';

/// Album CRUD + file↔album cross-mutation. Splits out of `VaultService`.
///
/// reverse direction wired via late setter to avoid a constructor cycle.
class AlbumService {
  final VaultStore _store;
  final FileService _fileService;

  AlbumService(this._store, this._fileService);

  Future<List<Album>> getAllAlbums() => _store.loadAlbums();

  Future<Album?> getAlbumById(String albumId) async {
    final albums = await _store.loadAlbums();
    try {
      return albums.firstWhere((a) => a.id == albumId);
    } catch (e) {
      return null;
    }
  }

  Future<Album?> createAlbum({
    required String name,
    String? description,
    String? coverImageId,
  }) async {
    try {
      final now = DateTime.now();
      final id = sha256
          .convert(utf8.encode('$name${now.millisecondsSinceEpoch}'))
          .toString()
          .substring(0, 16);

      final album = Album(
        id: id,
        name: name,
        description: description,
        coverImageId: coverImageId,
        createdAt: now,
        updatedAt: now,
        sortOrder: (_store.cachedAlbums?.length ?? 0) + 1,
      );

      _store.cachedAlbums ??= [];
      _store.cachedAlbums!.add(album);
      await _store.saveAlbums();

      return album;
    } catch (e) {
      debugPrint('Error creating album: $e');
      return null;
    }
  }

  Future<Album?> updateAlbum(Album updatedAlbum) async {
    try {
      final albums = await _store.loadAlbums();
      final index = albums.indexWhere((a) => a.id == updatedAlbum.id);

      if (index == -1) return null;

      _store.cachedAlbums![index] = updatedAlbum.copyWith(updatedAt: DateTime.now());
      await _store.saveAlbums();

      return _store.cachedAlbums![index];
    } catch (e) {
      debugPrint('Error updating album: $e');
      return null;
    }
  }

  Future<bool> deleteAlbum(String albumId) async {
    try {
      final albums = await _store.loadAlbums();
      final album = albums.firstWhere(
        (a) => a.id == albumId,
        orElse: () => throw Exception('Album not found'),
      );

      if (album.isDefault) {
        debugPrint('Cannot delete default album');
        return false;
      }

      for (final fileId in album.fileIds) {
        final file = await _fileService.getFileById(fileId);
        if (file != null) {
          await _fileService.updateFile(file.removeFromAlbum(albumId));
        }
      }

      _store.cachedAlbums!.removeWhere((a) => a.id == albumId);
      await _store.saveAlbums();

      return true;
    } catch (e) {
      debugPrint('Error deleting album: $e');
      return false;
    }
  }

  Future<bool> addFileToAlbum(String fileId, String albumId) async {
    try {
      final file = await _fileService.getFileById(fileId);
      if (file == null) return false;

      final albums = await _store.loadAlbums();
      final albumIndex = albums.indexWhere((a) => a.id == albumId);
      if (albumIndex == -1) return false;

      _store.cachedAlbums![albumIndex] = _store.cachedAlbums![albumIndex].addFile(fileId);
      await _store.saveAlbums();

      VaultedFile updatedFile = file.addToAlbum(albumId);
      if (albumId == 'favorites') {
        updatedFile = updatedFile.copyWith(isFavorite: true);
      }
      await _fileService.updateFile(updatedFile);

      return true;
    } catch (e) {
      debugPrint('Error adding file to album: $e');
      return false;
    }
  }

  Future<bool> addFilesToAlbum(List<String> fileIds, String albumId) async {
    try {
      final albums = await _store.loadAlbums();
      final albumIndex = albums.indexWhere((a) => a.id == albumId);
      if (albumIndex == -1) return false;

      final files = await _store.loadFileIndex();
      bool changed = false;

      for (final fileId in fileIds) {
        final fileIdx = files.indexWhere((f) => f.id == fileId);
        if (fileIdx == -1) continue;

        _store.cachedAlbums![albumIndex] = _store.cachedAlbums![albumIndex].addFile(fileId);

        VaultedFile updatedFile = files[fileIdx].addToAlbum(albumId);
        if (albumId == 'favorites') {
          updatedFile = updatedFile.copyWith(isFavorite: true);
        }
        _store.cachedFiles![fileIdx] = updatedFile;
        changed = true;
      }

      if (changed) {
        await _store.saveAlbums();
        await _store.saveFileIndex();
      }
      return true;
    } catch (e) {
      debugPrint('Error adding files to album: $e');
      return false;
    }
  }

  Future<bool> removeFilesFromAlbum(List<String> fileIds, String albumId) async {
    try {
      final albums = await _store.loadAlbums();
      final albumIndex = albums.indexWhere((a) => a.id == albumId);
      if (albumIndex == -1) return false;

      final files = await _store.loadFileIndex();
      bool changed = false;

      for (final fileId in fileIds) {
        _store.cachedAlbums![albumIndex] = _store.cachedAlbums![albumIndex].removeFile(fileId);

        final fileIdx = files.indexWhere((f) => f.id == fileId);
        if (fileIdx != -1) {
          VaultedFile updatedFile = files[fileIdx].removeFromAlbum(albumId);
          if (albumId == 'favorites') {
            updatedFile = updatedFile.copyWith(isFavorite: false);
          }
          _store.cachedFiles![fileIdx] = updatedFile;
        }
        changed = true;
      }

      if (changed) {
        await _store.saveAlbums();
        await _store.saveFileIndex();
      }
      return true;
    } catch (e) {
      debugPrint('Error removing files from album: $e');
      return false;
    }
  }

  Future<bool> removeFileFromAlbum(String fileId, String albumId) async {
    try {
      final albums = await _store.loadAlbums();
      final albumIndex = albums.indexWhere((a) => a.id == albumId);
      if (albumIndex == -1) return false;

      _store.cachedAlbums![albumIndex] = _store.cachedAlbums![albumIndex].removeFile(fileId);
      await _store.saveAlbums();

      final file = await _fileService.getFileById(fileId);
      if (file != null) {
        VaultedFile updatedFile = file.removeFromAlbum(albumId);
        if (albumId == 'favorites') {
          updatedFile = updatedFile.copyWith(isFavorite: false);
        }
        await _fileService.updateFile(updatedFile);
      }

      return true;
    } catch (e) {
      debugPrint('Error removing file from album: $e');
      return false;
    }
  }

  Future<List<VaultedFile>> getFilesInAlbum(String albumId) async {
    final album = await getAlbumById(albumId);
    if (album == null) return [];

    final files = await _fileService.getAllFiles();
    return files.where((f) => album.fileIds.contains(f.id)).toList();
  }
}