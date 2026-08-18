import 'package:flutter/foundation.dart';

import '../models/vaulted_file.dart';
import 'album_service.dart';
import 'file_service.dart';
import 'vault_store.dart';

/// Tag CRUD + favorites toggle. Splits out of `VaultService`.
///
/// favorites-as-tag keeps the service dep graph one-directional.
class TagService {
  final VaultStore _store;
  final AlbumService _albumService;
  final FileService _fileService;

  TagService(this._store, this._albumService, this._fileService);

  Future<List<TagInfo>> getAllTags() => _store.loadTags();

  Future<List<VaultedFile>> getFilesByTag(String tag) async {
    final files = await _fileService.getAllFiles();
    return files.where((f) => f.hasTag(tag)).toList();
  }

  Future<VaultedFile?> addTagToFile(String fileId, String tag) async {
    final file = await _fileService.getFileById(fileId);
    if (file == null) return null;

    final updatedFile = file.addTag(tag);
    await _fileService.updateFile(updatedFile);
    await updateTagUsage([tag]);

    return updatedFile;
  }

  Future<VaultedFile?> removeTagFromFile(String fileId, String tag) async {
    final file = await _fileService.getFileById(fileId);
    if (file == null) return null;

    final updatedFile = file.removeTag(tag);
    await _fileService.updateFile(updatedFile);

    return updatedFile;
  }

  Future<void> updateTagUsage(List<String> tags) async {
    _store.cachedTags ??= [];

    for (final tag in tags) {
      final normalizedTag = tag.toLowerCase().trim();
      if (normalizedTag.isEmpty) continue;

      final existingIndex =
          _store.cachedTags!.indexWhere((t) => t.name == normalizedTag);

      if (existingIndex == -1) {
        _store.cachedTags!.add(TagInfo(name: normalizedTag, usageCount: 1));
      } else {
        _store.cachedTags![existingIndex] = TagInfo(
          name: normalizedTag,
          colorValue: _store.cachedTags![existingIndex].colorValue,
          usageCount: _store.cachedTags![existingIndex].usageCount + 1,
        );
      }
    }

    await _store.saveTags();
  }

  Future<TagInfo> createTag(String name, [int? colorValue]) async {
    _store.cachedTags ??= await _store.loadTags();

    final normalizedName = name.toLowerCase().trim();
    final existingIndex =
        _store.cachedTags!.indexWhere((t) => t.name == normalizedName);

    if (existingIndex != -1) {
      if (colorValue != null) {
        _store.cachedTags![existingIndex] = TagInfo(
          name: normalizedName,
          colorValue: colorValue,
          usageCount: _store.cachedTags![existingIndex].usageCount,
        );
        await _store.saveTags();
      }
      return _store.cachedTags![existingIndex];
    }

    final newTag = TagInfo(
      name: normalizedName,
      colorValue: colorValue ?? 0xFF1976D2,
      usageCount: 0,
    );
    _store.cachedTags!.add(newTag);
    await _store.saveTags();

    return newTag;
  }

  Future<bool> updateTagColor(String tagName, int colorValue) async {
    _store.cachedTags ??= await _store.loadTags();

    final normalizedName = tagName.toLowerCase().trim();
    final index = _store.cachedTags!.indexWhere((t) => t.name == normalizedName);

    if (index == -1) return false;

    _store.cachedTags![index] = TagInfo(
      name: normalizedName,
      colorValue: colorValue,
      usageCount: _store.cachedTags![index].usageCount,
    );
    await _store.saveTags();

    return true;
  }

  Future<bool> deleteTag(String tagName) async {
    try {
      final normalizedName = tagName.toLowerCase().trim();

      final files = await _fileService.getAllFiles();
      for (final file in files) {
        if (file.hasTag(normalizedName)) {
          await removeTagFromFile(file.id, normalizedName);
        }
      }

      _store.cachedTags ??= await _store.loadTags();
      _store.cachedTags!.removeWhere((t) => t.name == normalizedName);
      await _store.saveTags();

      return true;
    } catch (e) {
      debugPrint('Error deleting tag: $e');
      return false;
    }
  }

  // ---- Favorites ----

  Future<VaultedFile?> toggleFavorite(String fileId) async {
    final file = await _fileService.getFileById(fileId);
    if (file == null) return null;

    final favoritesAlbum = await _albumService.getAlbumById('favorites');
    if (favoritesAlbum != null) {
      if (file.isFavorite) {
        await _albumService.removeFileFromAlbum(fileId, 'favorites');
      } else {
        await _albumService.addFileToAlbum(fileId, 'favorites');
      }
    } else {
      final updatedFile = file.toggleFavorite();
      await _fileService.updateFile(updatedFile);
      return updatedFile;
    }

    return await _fileService.getFileById(fileId);
  }

  Future<List<VaultedFile>> getFavoriteFiles() async {
    final files = await _fileService.getAllFiles();
    return files.where((f) => f.isFavorite).toList();
  }
}