import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/vaulted_file.dart';
import 'package:locker/providers/vault_providers.dart';
import 'package:locker/services/crypto_isolate_pool.dart';
import 'package:locker/services/file_open_service.dart';
import 'package:locker/services/vault_service.dart';

class _DecryptRequest {
  _DecryptRequest(this.fileId, this.token, this.onProgress);

  final String fileId;
  final CancelToken token;
  final Function(int, int)? onProgress;
  final result = Completer<File?>();
}

class _FakeVaultService extends VaultService {
  final requests = <_DecryptRequest>[];
  final viewed = <String>[];

  @override
  Future<File?> getVaultedFile(
    String fileId, {
    bool isDecoy = false,
    Function(int processed, int total)? onProgress,
    CancelToken? cancelToken,
  }) {
    final request = _DecryptRequest(fileId, cancelToken!, onProgress);
    requests.add(request);
    return request.result.future;
  }

  @override
  Future<VaultedFile?> updateFile(VaultedFile updatedFile) async {
    viewed.add(updatedFile.id);
    return updatedFile;
  }
}

class _DeferredFile implements File {
  final existsResult = Completer<bool>();
  bool existsCalled = false;

  @override
  Future<bool> exists() {
    existsCalled = true;
    return existsResult.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

VaultedFile _file(String id, {bool encrypted = false}) => VaultedFile(
      id: id,
      originalName: '$id.bin',
      vaultPath: '/vault/$id',
      type: VaultedFileType.other,
      mimeType: 'application/octet-stream',
      fileSize: 100,
      dateAdded: DateTime.utc(2024),
      isEncrypted: encrypted,
      encryptionIv: encrypted ? 'iv' : null,
    );

class _Harness {
  final service = _FakeVaultService();
  final opened = <String>[];
  late void Function(VaultedFile) open;

  Future<void> pump(WidgetTester tester, List<VaultedFile> files) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [vaultServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        home: Consumer(builder: (context, ref, _) {
          open = (file) {
            unawaited(FileOpenService.open(
              context,
              ref,
              file,
              currentFiles: files,
              // Exercise the shared opening flow without platform viewers.
              onUnsupported: () => opened.add(file.id),
            ));
          };
          return Scaffold(
            body: Column(children: [
              for (final file in files)
                TextButton(
                  key: ValueKey(file.id),
                  onPressed: () => open(file),
                  child: Text('Open ${file.id}'),
                ),
            ]),
          );
        }),
      ),
    ));
    addTearDown(() async {
      for (final request in service.requests) {
        if (!request.result.isCompleted) request.result.complete(null);
      }
      await tester.pump();
    });
  }
}

Future<void> _showPreparation(WidgetTester tester, VaultedFile file) async {
  await tester.tap(find.byKey(ValueKey(file.id)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.text('Preparing key…'), findsOneWidget);
}

Future<void> _cancel(WidgetTester tester) async {
  await tester.tap(find.text('Cancel'));
  await tester.pumpAndSettle();
  expect(find.text('Cancel'), findsNothing);
}

void main() {
  testWidgets('Cancel allows an unencrypted file before key preparation ends',
      (tester) async {
    final encrypted = _file('encrypted', encrypted: true);
    final plain = _file('plain');
    final harness = _Harness();
    await harness.pump(tester, [encrypted, plain]);
    await _showPreparation(tester, encrypted);
    final request = harness.service.requests.single;

    await _cancel(tester);
    expect(request.token.isCancelled, isTrue);
    expect(request.result.isCompleted, isFalse);

    await tester.tap(find.byKey(ValueKey(plain.id)));
    await tester.pump();
    expect(harness.opened, [plain.id]);
    expect(harness.service.viewed, [plain.id]);

    // Late results and progress from the cancelled request must be ignored.
    request.onProgress?.call(50, 100);
    request.result.complete(File('/cancelled-decryption'));
    await tester.pump();
    expect(harness.opened, [plain.id]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an old cancelled request cannot unlock a newer encrypted open',
      (tester) async {
    final first = _file('first', encrypted: true);
    final second = _file('second', encrypted: true);
    final plain = _file('plain');
    final harness = _Harness();
    await harness.pump(tester, [first, second, plain]);
    await _showPreparation(tester, first);
    final oldRequest = harness.service.requests.single;
    await _cancel(tester);

    await _showPreparation(tester, second);
    expect(
        harness.service.requests.map((r) => r.fileId), [first.id, second.id]);
    oldRequest.result.complete(null);
    await tester.pump();

    // Simulate a duplicate open while the newer request is still active.
    harness.open(plain);
    await tester.pump();
    expect(harness.opened, isEmpty);
    expect(find.text(second.originalName), findsOneWidget);
    expect(harness.service.requests.last.token.isCancelled, isFalse);

    await _cancel(tester);
    await tester.tap(find.byKey(ValueKey(plain.id)));
    await tester.pump();
    expect(harness.opened, [plain.id]);
  });

  testWidgets('Cancel during the decrypted-file check never opens the viewer',
      (tester) async {
    final encrypted = _file('encrypted', encrypted: true);
    final plain = _file('plain');
    final harness = _Harness();
    final decrypted = _DeferredFile();
    await harness.pump(tester, [encrypted, plain]);
    addTearDown(() {
      if (!decrypted.existsResult.isCompleted) {
        decrypted.existsResult.complete(false);
      }
    });
    await _showPreparation(tester, encrypted);
    harness.service.requests.single.result.complete(decrypted);
    await tester.pump();
    expect(decrypted.existsCalled, isTrue);

    await _cancel(tester);
    decrypted.existsResult.complete(true);
    await tester.pump();
    expect(harness.opened, isEmpty);
    expect(harness.service.viewed, isEmpty);

    await tester.tap(find.byKey(ValueKey(plain.id)));
    await tester.pump();
    expect(harness.opened, [plain.id]);
    expect(tester.takeException(), isNull);
  });
}
