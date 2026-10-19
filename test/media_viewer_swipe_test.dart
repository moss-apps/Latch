import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/vaulted_file.dart';
import 'package:locker/providers/vault_providers.dart';
import 'package:locker/screens/media_viewer_screen.dart';
import 'package:locker/services/crypto_isolate_pool.dart';
import 'package:locker/services/vault_service.dart';

class _FakeVaultService extends VaultService {
  final Map<String, int> decryptCalls = {};
  final Map<String, Completer<File?>> pending = {};

  @override
  Future<File?> getVaultedFile(
    String fileId, {
    bool isDecoy = false,
    Function(int processed, int total)? onProgress,
    CancelToken? cancelToken,
  }) {
    decryptCalls.update(fileId, (count) => count + 1, ifAbsent: () => 1);
    return (pending[fileId] ??= Completer<File?>()).future;
  }

  @override
  Future<VaultedFile?> updateFile(VaultedFile updatedFile) async => updatedFile;
}

VaultedFile _encryptedImage(String id) => VaultedFile(
      id: id,
      originalName: '$id.png',
      vaultPath: '/vault/$id.enc',
      type: VaultedFileType.image,
      mimeType: 'image/png',
      fileSize: 68,
      dateAdded: DateTime.utc(2024),
      isEncrypted: true,
      encryptionIv: 'iv',
    );

VaultedFile _encryptedVideo(String id) => VaultedFile(
      id: id,
      originalName: '$id.mp4',
      vaultPath: '/vault/$id.enc',
      type: VaultedFileType.video,
      mimeType: 'video/mp4',
      fileSize: 100,
      dateAdded: DateTime.utc(2024),
      isEncrypted: true,
      encryptionIv: 'iv',
    );

void main() {
  testWidgets(
      'swiping to an encrypted image shares its in-flight decryption job',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('latch_swipe_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final decrypted = File('${dir.path}/a.png');
    decrypted.writeAsBytesSync(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8'
      '/x8AAusB9Y9Z4YwAAAAASUVORK5CYII=',
    ));

    final first = _encryptedImage('first');
    final second = _encryptedImage('second');
    final service = _FakeVaultService();

    await tester.pumpWidget(ProviderScope(
      overrides: [vaultServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        home: MediaViewerScreen(
          initialFile: first,
          files: [first, second],
          initialIndex: 0,
          initialDecryptedFile: decrypted,
        ),
      ),
    ));
    await tester.pump();

    // Opening the first file prefetches its neighbour.
    expect(service.decryptCalls[second.id], 1);

    // Moving to the neighbour builds its page and fires onPageChanged. Both
    // paths must attach to the prefetch instead of starting a competing job.
    tester.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(1);
    await tester.pump();

    expect(service.decryptCalls[second.id], 1);
  });

  testWidgets('a failed swiped video shows a retry action', (tester) async {
    final dir = Directory.systemTemp.createTempSync('latch_video_swipe_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final decrypted = File('${dir.path}/a.png');
    decrypted.writeAsBytesSync(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8'
      '/x8AAusB9Y9Z4YwAAAAASUVORK5CYII=',
    ));

    final first = _encryptedImage('first');
    final second = _encryptedVideo('second');
    final service = _FakeVaultService();

    await tester.pumpWidget(ProviderScope(
      overrides: [vaultServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        home: MediaViewerScreen(
          initialFile: first,
          files: [first, second],
          initialIndex: 0,
          initialDecryptedFile: decrypted,
        ),
      ),
    ));
    await tester.pump();

    tester.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(1);
    await tester.pump();
    expect(service.decryptCalls[second.id], 1);

    service.pending[second.id]!.complete(null);
    await tester.pump();
    await tester.pump();

    expect(find.text('Could not decrypt this video.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(service.decryptCalls[second.id], 2);
  });
}
