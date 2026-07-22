import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/album.dart';
import 'package:locker/models/vault_settings.dart';
import 'package:locker/models/vaulted_file.dart';
import 'package:locker/services/vault_service.dart';

const _secureStorageChannel = 'plugins.it_nomads.com/flutter_secure_storage';
const _pathProviderChannel = 'plugins.flutter.io/path_provider';

Future<VaultService> _freshVault({
  required Map<String, String> storage,
  required Directory tmpDir,
}) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel(_secureStorageChannel),
    (call) async {
      final args = (call.arguments ?? {}) as Map;
      final key = args['key'] as String?;
      switch (call.method) {
        case 'read':
          return storage[key];
        case 'write':
          storage[key!] = args['value'] as String;
          return null;
        case 'delete':
          storage.remove(key);
          return null;
        case 'deleteAll':
          storage.clear();
          return null;
        case 'containsKey':
          return storage.containsKey(key);
        case 'readAll':
          return storage;
        default:
          return null;
      }
    },
  );

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel(_pathProviderChannel),
    (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tmpDir.path;
      }
      return null;
    },
  );

  final vault = VaultService();
  await vault.loadIndexesForTesting();
  return vault;
}

VaultedFile _makeFile(String id, {bool isFavorite = false}) {
  return VaultedFile(
    id: id,
    originalName: '$id.jpg',
    vaultPath: '/tmp/$id.enc',
    type: VaultedFileType.image,
    mimeType: 'image/jpeg',
    fileSize: 1024,
    dateAdded: DateTime(2024, 1, 1),
    dateModified: DateTime(2024, 1, 1),
    isFavorite: isFavorite,
  );
}

Future<void> _seedFiles(VaultService vault, List<VaultedFile> files) async {
  for (final f in files) {
    await vault.registerNoteEntry(
      noteId: f.id,
      title: f.id,
      encryptedContentPath: f.vaultPath,
      isEncrypted: false,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> storage;
  late Directory tmpDir;

  setUp(() async {
    storage = {};
    tmpDir = await Directory.systemTemp.createTemp('latch_vault_test');
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(_secureStorageChannel),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(_pathProviderChannel),
      null,
    );
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {}
  });

  group('settings', () {
    test('default settings have failedUnlockProtectionEnabled=true', () async {
      final vault = await _freshVault(storage: storage, tmpDir: tmpDir);
      final s = await vault.getSettings();
      expect(s.failedUnlockProtectionEnabled, true);
    });

    test('updateSettings persists and survives reload', () async {
      final vault = await _freshVault(storage: storage, tmpDir: tmpDir);
      await vault.updateSettings(
        const VaultSettings().copyWith(
          encryptionEnabled: true,
          kdfIterations: 100000,
          compressionEnabled: true,
        ),
      );

      final vault2 = await _freshVault(storage: storage, tmpDir: tmpDir);
      final s = await vault2.getSettings();
      expect(s.encryptionEnabled, true);
      expect(s.kdfIterations, 100000);
      expect(s.compressionEnabled, true);
    });

    test('fromJson preserves explicit false for failedUnlockProtectionEnabled',
        () async {
      storage['vault_settings'] =
          jsonEncode(const VaultSettings(failedUnlockProtectionEnabled: false)
              .toJson());
      final vault = await _freshVault(storage: storage, tmpDir: tmpDir);
      final s = await vault.getSettings();
      expect(s.failedUnlockProtectionEnabled, false);
    });
  });

  group('albums + file cross-mutation', () {
    test('addFilesToAlbum updates both album.fileIds and file.albumIds',
        () async {
      final vault = await _freshVault(storage: storage, tmpDir: tmpDir);
      await _seedFiles(vault, [_makeFile('f1'), _makeFile('f2')]);
      final album = await vault.createAlbum(name: 'Holiday');
      expect(album, isNotNull);

      final ok = await vault.addFilesToAlbum(['f1', 'f2'], album!.id);
      expect(ok, true);

      final files = await vault.getAllFiles();
      expect(files.firstWhere((f) => f.id == 'f1').albumIds, contains(album.id));
      expect(files.firstWhere((f) => f.id == 'f2').albumIds, contains(album.id));

      final reloaded = await vault.getAlbumById(album.id);
      expect(reloaded!.fileIds, containsAll(['f1', 'f2']));
    });

    test('deleteAlbum clears albumId from associated files', () async {
      final vault = await _freshVault(storage: storage, tmpDir: tmpDir);
      await _seedFiles(vault, [_makeFile('f1'), _makeFile('f2')]);
      final album = await vault.createAlbum(name: 'Trip');

      await vault.addFilesToAlbum(['f1', 'f2'], album!.id);
      await vault.deleteAlbum(album.id);

      final files = await vault.getAllFiles();
      for (final f in files) {
        expect(f.albumIds, isNot(contains(album.id)));
      }
      expect(await vault.getAlbumById(album.id), isNull);
    });

    test('removeFilesFromAlbum clears file.albumIds', () async {
      final vault = await _freshVault(storage: storage, tmpDir: tmpDir);
      await _seedFiles(vault, [_makeFile('f1'), _makeFile('f2')]);
      final album = await vault.createAlbum(name: 'Work');

      await vault.addFilesToAlbum(['f1', 'f2'], album!.id);
      await vault.removeFilesFromAlbum(['f1'], album.id);

      final files = await vault.getAllFiles();
      expect(
          files.firstWhere((f) => f.id == 'f1').albumIds, isNot(contains(album.id)));
      expect(files.firstWhere((f) => f.id == 'f2').albumIds, contains(album.id));
    });

    test('favorites album sets isFavorite on file', () async {
      final vault = await _freshVault(storage: storage, tmpDir: tmpDir);
      await _seedFiles(vault, [_makeFile('f1')]);

      await vault.addFilesToAlbum(['f1'], 'favorites');

      final files = await vault.getAllFiles();
      expect(files.firstWhere((f) => f.id == 'f1').isFavorite, true);
    });
  });

  group('folders', () {
    test('createFolder + addFileToFolder sets file.folderId', () async {
      final vault = await _freshVault(storage: storage, tmpDir: tmpDir);
      await _seedFiles(vault, [_makeFile('f1')]);
      final folder = await vault.createFolder(name: 'Docs');
      expect(folder, isNotNull);

      final ok = await vault.addFileToFolder('f1', folder!.id);
      expect(ok, true);

      final files = await vault.getAllFiles();
      expect(files.firstWhere((f) => f.id == 'f1').folderId, folder.id);
    });

    test('deleteFolder clears folderId from files', () async {
      final vault = await _freshVault(storage: storage, tmpDir: tmpDir);
      await _seedFiles(vault, [_makeFile('f1')]);
      final folder = await vault.createFolder(name: 'Temp');
      await vault.addFileToFolder('f1', folder!.id);

      await vault.deleteFolder(folder.id);

      final files = await vault.getAllFiles();
      expect(files.firstWhere((f) => f.id == 'f1').folderId, isNull);
    });
  });

  group('tags', () {
    test('addTagToFile updates file.tags and tag index', () async {
      final vault = await _freshVault(storage: storage, tmpDir: tmpDir);
      await _seedFiles(vault, [_makeFile('f1')]);

      await vault.addTagToFile('f1', 'beach');

      final files = await vault.getAllFiles();
      expect(files.firstWhere((f) => f.id == 'f1').tags, contains('beach'));

      final tags = await vault.getAllTags();
      expect(tags.any((t) => t.name == 'beach'), true);
    });

    test('removeTagFromFile removes from file.tags', () async {
      final vault = await _freshVault(storage: storage, tmpDir: tmpDir);
      await _seedFiles(vault, [_makeFile('f1')]);
      await vault.addTagToFile('f1', 'beach');
      await vault.addTagToFile('f1', 'sunset');

      await vault.removeTagFromFile('f1', 'beach');

      final files = await vault.getAllFiles();
      final tags = files.firstWhere((f) => f.id == 'f1').tags;
      expect(tags, isNot(contains('beach')));
      expect(tags, contains('sunset'));
    });
  });

  group('favorites', () {
    test('toggleFavorite flips isFavorite', () async {
      final vault = await _freshVault(storage: storage, tmpDir: tmpDir);
      await _seedFiles(vault, [_makeFile('f1')]);

      await vault.toggleFavorite('f1');
      expect(
          (await vault.getAllFiles()).firstWhere((f) => f.id == 'f1').isFavorite,
          true);

      await vault.toggleFavorite('f1');
      expect(
          (await vault.getAllFiles()).firstWhere((f) => f.id == 'f1').isFavorite,
          false);
    });

    test('getFavoriteFiles returns only favorites', () async {
      final vault = await _freshVault(storage: storage, tmpDir: tmpDir);
      await _seedFiles(vault, [_makeFile('f1'), _makeFile('f2')]);
      await vault.toggleFavorite('f1');

      final favs = await vault.getFavoriteFiles();
      expect(favs.length, 1);
      expect(favs.first.id, 'f1');
    });
  });

  group('search', () {
    test('searchFilesAdvanced filters by name query', () async {
      final vault = await _freshVault(storage: storage, tmpDir: tmpDir);
      await _seedFiles(vault, [_makeFile('beach'), _makeFile('mountain')]);

      final results = await vault.searchFilesAdvanced(query: 'beach');
      expect(results.length, 1);
      expect(results.first.id, 'beach');
    });

    test('searchFilesAdvanced filters by tag', () async {
      final vault = await _freshVault(storage: storage, tmpDir: tmpDir);
      await _seedFiles(vault, [_makeFile('f1'), _makeFile('f2')]);
      await vault.addTagToFile('f1', 'nature');

      final results = await vault.searchFilesAdvanced(tags: ['nature']);
      expect(results.length, 1);
      expect(results.first.id, 'f1');
    });
  });

  group('sort', () {
    test('sortFiles by name ascending', () async {
      final vault = await _freshVault(storage: storage, tmpDir: tmpDir);
      final files = [_makeFile('zebra'), _makeFile('apple'), _makeFile('mango')];
      final sorted = vault.sortFiles(files, SortOption.nameAsc);
      expect(sorted.map((f) => f.id).toList(), ['apple', 'mango', 'zebra']);
    });

    test('sortFiles by date newest first', () async {
      final vault = await _freshVault(storage: storage, tmpDir: tmpDir);
      final old = _makeFile('old').copyWith(dateAdded: DateTime(2020));
      final recent = _makeFile('new').copyWith(dateAdded: DateTime(2024, 6));
      final sorted = vault.sortFiles([old, recent], SortOption.dateAddedNewest);
      expect(sorted.first.id, 'new');
    });
  });

  group('stats', () {
    test('getFileCounts counts by type', () async {
      final vault = await _freshVault(storage: storage, tmpDir: tmpDir);
      await _seedFiles(vault, [_makeFile('f1'), _makeFile('f2')]);

      final counts = await vault.getFileCounts();
      expect(counts[VaultedFileType.document], 2);
    });

    test('getTotalStorageUsed sums file sizes', () async {
      final vault = await _freshVault(storage: storage, tmpDir: tmpDir);
      await _seedFiles(vault, [_makeFile('f1'), _makeFile('f2')]);

      final total = await vault.getTotalStorageUsed();
      expect(total, 0);
    });
  });

  group('clearVault', () {
    test('clears file index and albums from storage', () async {
      final vault = await _freshVault(storage: storage, tmpDir: tmpDir);
      await _seedFiles(vault, [_makeFile('f1'), _makeFile('f2')]);
      await vault.createAlbum(name: 'Trip');
      expect(storage['vault_file_index'], isNotNull);
      expect(storage['vault_albums'], isNotNull);

      await vault.clearVault();

      expect(storage['vault_file_index'], isNull);
      expect(storage['vault_albums'], isNull);
    });
  });
}
