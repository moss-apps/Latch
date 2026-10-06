import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/file_to_vault.dart';
import 'package:locker/models/vaulted_file.dart';
import 'package:locker/services/file_import_service.dart';
import 'package:locker/services/share_intake_service.dart';
import 'package:locker/services/vault_service.dart';

const _shareChannelName = 'com.mossapps.locker/share_intake';
const _secureStorageChannel = 'plugins.it_nomads.com/flutter_secure_storage';
const _pathProviderChannel = 'plugins.flutter.io/path_provider';

Map<String, Object?> _shareItem(
  String id, {
  String? name,
  String? mimeType,
  int? size,
}) =>
    {
      'id': id,
      'uri': 'content://share/$id',
      'name': name ?? '$id.txt',
      'mimeType': mimeType ?? 'text/plain',
      'size': size ?? 10,
    };

Map<String, Object?> _stagedItem(String id, String path, {int size = 4}) => {
      'id': id,
      'path': path,
      'name': '$id.txt',
      'mimeType': 'text/plain',
      'size': size,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = ShareIntakeService.instance;
  const shareChannel = MethodChannel(_shareChannelName);
  const codec = StandardMethodCodec();

  late Directory tmpDir;
  late Map<String, String> storage;
  late List<MethodCall> shareCalls;
  Map<String, Object?> pendingPayload = const {'items': <Object?>[]};
  Future<Object?> Function(Map<Object?, Object?> args)? stageHandler;

  Future<void> pushShare(Map<String, Object?> payload) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      _shareChannelName,
      codec.encodeMethodCall(MethodCall('onShareReceived', payload)),
      (_) {},
    );
  }

  void installMocks() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    messenger.setMockMethodCallHandler(
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

    messenger.setMockMethodCallHandler(
      const MethodChannel(_pathProviderChannel),
      (call) async {
        if (call.method == 'getApplicationDocumentsDirectory' ||
            call.method == 'getTemporaryDirectory') {
          return tmpDir.path;
        }
        return null;
      },
    );

    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      shareCalls.add(call);
      switch (call.method) {
        case 'getPendingShare':
          return pendingPayload;
        case 'stageShare':
          final handler = stageHandler;
          if (handler == null) return {'staged': <Object?>[]};
          return handler((call.arguments as Map).cast<Object?, Object?>());
        case 'consumeShare':
        case 'clearShare':
          return true;
        default:
          return null;
      }
    });
  }

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('latch_share_test');
    storage = {};
    shareCalls = [];
    pendingPayload = const {'items': <Object?>[]};
    stageHandler = null;
    installMocks();
    await service.resetForTesting();
  });

  tearDown(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel(_secureStorageChannel), null);
    messenger.setMockMethodCallHandler(
        const MethodChannel(_pathProviderChannel), null);
    messenger.setMockMethodCallHandler(shareChannel, null);
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
  });

  group('queue', () {
    test('initialize pulls pending items and later pushes dedupe by id',
        () async {
      pendingPayload = {
        'items': [_shareItem('a'), _shareItem('b')]
      };
      await service.initialize();
      expect(service.pending.map((e) => e.id), ['a', 'b']);

      await pushShare({
        'items': [_shareItem('a'), _shareItem('c', mimeType: 'image/png')]
      });
      expect(service.pending.map((e) => e.id), ['a', 'b', 'c']);
      expect(service.pending.last.mimeType, 'image/png');

      await pushShare({
        'items': [_shareItem('c')]
      });
      expect(service.pending.map((e) => e.id), ['a', 'b', 'c']);
    });

    test('deferring survives identical pushes but new shares lift it',
        () async {
      pendingPayload = {
        'items': [_shareItem('a')]
      };
      await service.initialize();
      service.deferCurrent();
      expect(service.isDeferred, isTrue);

      await pushShare({
        'items': [_shareItem('a')]
      });
      expect(service.isDeferred, isTrue);

      await pushShare({
        'items': [_shareItem('b')]
      });
      expect(service.isDeferred, isFalse);
      expect(service.pending.length, 2);
    });

    test('consume removes only the reported ids and tells the platform',
        () async {
      pendingPayload = {
        'items': [_shareItem('a'), _shareItem('b'), _shareItem('c')]
      };
      await service.initialize();
      await service.consume(['a', 'c']);
      expect(service.pending.map((e) => e.id), ['b']);
      final consumeCall =
          shareCalls.lastWhere((c) => c.method == 'consumeShare');
      expect((consumeCall.arguments as Map)['ids'], ['a', 'c']);
    });

    test('clearAll empties the queue and drops deferral', () async {
      pendingPayload = {
        'items': [_shareItem('a')]
      };
      await service.initialize();
      service.deferCurrent();
      await service.clearAll();
      expect(service.hasPending, isFalse);
      expect(service.deferredSignature, isNull);
      expect(shareCalls.any((c) => c.method == 'clearShare'), isTrue);
    });
  });

  group('staging', () {
    test('stage parses successes and per-item failures', () async {
      pendingPayload = {
        'items': [_shareItem('a'), _shareItem('b')]
      };
      await service.initialize();
      final dir = await service.prepareStagingDirectory(7);
      expect(dir.path.endsWith('share_staging/7'), isTrue);

      stageHandler = (args) async {
        final destination = args['destinationDir'] as String;
        final file = File('$destination/a_staged.txt')
          ..writeAsStringSync('data');
        return {
          'staged': [
            _stagedItem('a', file.path, size: 4),
            {'id': 'b', 'error': 'Source revoked'},
          ],
        };
      };

      final results = await service.stage(destinationDir: dir.path);
      expect(results.length, 2);
      final a = results.firstWhere((r) => r.ref.id == 'a');
      final b = results.firstWhere((r) => r.ref.id == 'b');
      expect(a.ok, isTrue);
      expect(File(a.path!).readAsStringSync(), 'data');
      expect(b.ok, isFalse);
      expect(b.error, 'Source revoked');
    });

    test('unreadable item without a native entry fails gracefully', () async {
      pendingPayload = {
        'items': [_shareItem('a')]
      };
      await service.initialize();
      final dir = await service.prepareStagingDirectory(1);
      stageHandler = (args) async => {'staged': <Object?>[]};
      final results = await service.stage(destinationDir: dir.path);
      expect(results.single.ok, isFalse);
      expect(results.single.error, 'File could not be read');
    });

    test('missing platform support fails every item', () async {
      pendingPayload = {
        'items': [_shareItem('a')]
      };
      await service.initialize();
      final dir = await service.prepareStagingDirectory(1);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, null);

      final results = await service.stage(destinationDir: dir.path);
      expect(results.single.ok, isFalse);
      expect(results.single.error, 'Sharing is unavailable on this platform');

      installMocks();
    });

    test('purgeStaging waits for in-flight copies and removes late files',
        () async {
      pendingPayload = {
        'items': [_shareItem('late')]
      };
      await service.initialize();
      final dir = await service.prepareStagingDirectory(1);

      final gate = Completer<void>();
      stageHandler = (args) async {
        await gate.future;
        final destination = Directory(args['destinationDir'] as String)
          ..createSync(recursive: true);
        final file = File('${destination.path}/late.txt')
          ..writeAsStringSync('late');
        return {
          'staged': [_stagedItem('late', file.path)]
        };
      };

      final stageFuture = service.stage(destinationDir: dir.path);
      final purgeFuture = service.purgeStaging();
      gate.complete();
      await stageFuture;
      await purgeFuture;

      expect(Directory('${tmpDir.path}/share_staging').existsSync(), isFalse);
    });

    test('lock clears deferral and staging but keeps refs', () async {
      pendingPayload = {
        'items': [_shareItem('a')]
      };
      await service.initialize();
      final dir = await service.prepareStagingDirectory(1);
      File('${dir.path}/x.txt').writeAsStringSync('x');
      service.deferCurrent();

      await service.onSessionLocked();

      expect(service.isDeferred, isFalse);
      expect(service.pending.length, 1);
      expect(Directory('${tmpDir.path}/share_staging').existsSync(), isFalse);
    });
  });

  group('prepared import', () {
    test('importPreparedFiles stores new files and skips repeats', () async {
      await VaultService.instance.loadIndexesForTesting();
      final source = File('${tmpDir.path}/shared.txt')
        ..writeAsStringSync('hello latch');
      final fileToVault = FileToVault(
        sourcePath: source.path,
        originalName: 'shared.txt',
        type: VaultedFileType.document,
        mimeType: 'text/plain',
        encrypt: false,
      );

      final first = await FileImportService.instance
          .importPreparedFiles(files: [fileToVault]);
      expect(first.success, isTrue, reason: first.error ?? '');
      expect(first.importedCount, 1);
      expect(first.importedFiles.single.originalName, 'shared.txt');

      final second = await FileImportService.instance
          .importPreparedFiles(files: [fileToVault]);
      expect(second.success, isFalse);
      expect(second.skippedDuplicates, 1);
      expect(second.error, 'All shared files already exist in vault');
    });
  });
}
