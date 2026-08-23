import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/services/note_service.dart';

const _secureStorageChannel = 'plugins.it_nomads.com/flutter_secure_storage';
const _pathProviderChannel = 'plugins.flutter.io/path_provider';

Map<String, dynamic> _noteJson(String id, {String? path}) {
  return {
    'id': id,
    'title': 'note $id',
    'encryptedContentPath': path ?? '/tmp/real/.locker_vault/notes/$id.enc',
    'iv': '',
    'keyDerivationSalt': '',
    'kdfIterations': 100000,
    'folderId': null,
    'isPinned': false,
    'isMarkdown': false,
    'isEncrypted': false,
    'encryptionAlgorithm': 'aes256Gcm',
    'createdAt': '2024-01-01T00:00:00.000',
    'updatedAt': '2024-01-01T00:00:00.000',
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> storage;
  late Directory tmpDir;

  setUp(() async {
    storage = {};
    tmpDir = await Directory.systemTemp.createTemp('locker_notes_test');

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

    NoteService.instance.clearCache();
  });

  test('legacy shared index splits into real and decoy indexes', () async {
    storage['locker_notes_index'] = jsonEncode([
      _noteJson('real1'),
      _noteJson('decoy1',
          path: '/tmp/x/.locker_decoy/notes/decoy1.enc'),
    ]);

    final real = await NoteService.instance.loadNotes(isDecoy: false);
    expect(real.map((n) => n.id), ['real1']);

    NoteService.instance.clearCache();
    final decoy = await NoteService.instance.loadNotes(isDecoy: true);
    expect(decoy.map((n) => n.id), ['decoy1']);
  });

  test('malformed entry is skipped, index not wiped by next save', () async {
    storage['locker_notes_index'] = jsonEncode([
      _noteJson('good1'),
      'garbage-entry',
    ]);

    final notes = await NoteService.instance.loadNotes(isDecoy: false);
    expect(notes.map((n) => n.id), ['good1']);

    await NoteService.instance.togglePin(notes.first);
    NoteService.instance.clearCache();

    final reloaded = await NoteService.instance.loadNotes(isDecoy: false);
    expect(reloaded.map((n) => n.id), ['good1']);
    expect(reloaded.first.isPinned, isTrue);
  });

  test('decoy folders stored separately from real folders', () async {
    await NoteService.instance.createFolder('real', isDecoy: false);
    await NoteService.instance.createFolder('decoy', isDecoy: true);
    NoteService.instance.clearCache();

    final real = await NoteService.instance.loadFolders(isDecoy: false);
    final decoy = await NoteService.instance.loadFolders(isDecoy: true);
    expect(real.map((f) => f.name), ['real']);
    expect(decoy.map((f) => f.name), ['decoy']);
  });
}
