import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/album.dart';
import 'package:locker/models/vault_folder.dart';
import 'package:locker/models/vault_settings.dart';
import 'package:locker/models/vaulted_file.dart';
import 'package:locker/services/local_store.dart';
import 'package:locker/services/vault_service.dart';
import 'package:locker/services/vault_store.dart';

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

class _FakePBStore implements LocalStore {
  _FakePBStore({List<VaultedFile>? files}) : _files = files ?? [];

  Object? loadError;
  Object? saveError;
  List<VaultedFile> _files;

  @override
  List<VaultedFile>? cachedFiles;

  @override
  Future<List<VaultedFile>> loadFileIndex({
    bool isDecoy = false,
    bool forceReload = false,
  }) async {
    if (loadError != null) throw loadError!;
    return List.of(_files);
  }

  @override
  Future<void> saveFileIndex({bool isDecoy = false}) async {
    if (saveError != null) throw saveError!;
    _files = List.of(cachedFiles ?? const []);
  }

  @override
  List<Album>? cachedAlbums;
  @override
  List<VaultFolder>? cachedFolders;
  @override
  List<TagInfo>? cachedTags;
  @override
  Future<List<Album>> loadAlbums({bool forceReload = false}) async => [];
  @override
  Future<void> saveAlbums() async {}
  @override
  Future<List<VaultFolder>> loadFolders({bool forceReload = false}) async =>
      [];
  @override
  Future<void> saveFolders() async {}
  @override
  Future<List<TagInfo>> loadTags({bool forceReload = false}) async => [];
  @override
  Future<void> saveTags() async {}
  @override
  Future<void> reloadAll() async {}
  @override
  Future<void> wipe({bool isDecoy = false}) async {}
}

VaultedFile _pbEraFile(String id, Directory tmpDir, {int size = 10}) {
  final path = '${tmpDir.path}/$id';
  File(path).writeAsStringSync('blob-$id');
  return VaultedFile(
    id: id,
    originalName: '$id.jpg',
    vaultPath: path,
    type: VaultedFileType.image,
    mimeType: 'image/jpeg',
    fileSize: size,
    dateAdded: DateTime(2024, 1, 1),
  );
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

  group('mergeFileLists', () {
    test('base wins by id, unseen extras appended', () {
      final base = [_makeFile('a'), _makeFile('b')];
      final extra = [_makeFile('b'), _makeFile('c')];

      final merged = VaultStore.mergeFileLists(base, extra);

      expect(merged.map((f) => f.id), ['a', 'b', 'c']);
      expect(merged[1], same(base[1]));
    });
  });

  group('PB fallback divergence', () {
    test('PB load failure surfaces legacy entries instead of empty PB view',
        () async {
      final vault = await _freshVault(storage: storage, tmpDir: tmpDir);
      final legacy = _pbEraFile('legacy1', tmpDir);
      storage['vault_file_index'] =
          jsonEncode([legacy.toJson()].map((f) => f).toList());

      final pb = _FakePBStore()..loadError = Exception('sidecar down');
      vault.store.pbStore = pb;

      final files = await vault.store.loadFileIndex(forceReload: true);

      expect(files.map((f) => f.id), ['legacy1']);
    });

    test('PB save failure writes legacy union, drops blobless zombies',
        () async {
      final vault = await _freshVault(storage: storage, tmpDir: tmpDir);
      final survivor = _pbEraFile('survivor', tmpDir); // blob on disk
      final ghost = _makeFile('ghost'); // vaultPath /tmp/ghost.enc, no blob
      storage['vault_file_index'] = jsonEncode([survivor, ghost].map((f) => f.toJson()).toList());

      final pb = _FakePBStore()
        ..loadError = Exception('sidecar down')
        ..saveError = Exception('sidecar down');
      vault.store.pbStore = pb;

      vault.store.cachedFiles = [_pbEraFile('fresh', tmpDir)];
      await vault.store.saveFileIndex();

      final stored = (jsonDecode(storage['vault_file_index']!) as List)
          .map((j) => VaultedFile.fromJson(j as Map<String, dynamic>))
          .map((f) => f.id)
          .toSet();
      expect(stored, {'fresh', 'survivor'});
    });

    test('save after outage heals PB-only rows before reconcile', () async {
      final vault = await _freshVault(storage: storage, tmpDir: tmpDir);
      final pbOnly = _pbEraFile('pbonly', tmpDir);
      final pb = _FakePBStore(files: [pbOnly])..loadError = Exception('down');
      vault.store.pbStore = pb;

      // Outage load: cache = legacy only, divergence flagged.
      await vault.store.loadFileIndex(forceReload: true);
      expect(vault.store.cachedFiles!.map((f) => f.id), isEmpty);

      // Sidecar recovers; a new hide lands in the cache.
      pb.loadError = null;
      vault.store.cachedFiles!.add(_pbEraFile('newhide', tmpDir));

      await vault.store.saveFileIndex();

      // Reconcile must NOT have deleted the PB-only row.
      expect(
        vault.store.cachedFiles!.map((f) => f.id).toSet(),
        {'pbonly', 'newhide'},
      );
      final pbSaved = await pb.loadFileIndex(forceReload: true);
      expect(pbSaved.map((f) => f.id).toSet(), {'pbonly', 'newhide'});
    });

    test('healLegacyDivergence resurrects legacy-only rows into PB',
        () async {
      final vault = await _freshVault(storage: storage, tmpDir: tmpDir);
      final lostWhileDown = _pbEraFile('lost', tmpDir);
      storage['vault_file_index'] =
          jsonEncode([lostWhileDown.toJson()].map((f) => f).toList());

      final pb = _FakePBStore();
      vault.store.pbStore = pb;

      await vault.store.healLegacyDivergence();

      final healed = await pb.loadFileIndex(forceReload: true);
      expect(healed.map((f) => f.id), ['lost']);
    });
  });
}
