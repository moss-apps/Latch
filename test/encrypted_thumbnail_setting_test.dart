import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/vault_settings.dart';
import 'package:locker/models/vaulted_file.dart';
import 'package:locker/providers/vault_providers.dart';
import 'package:locker/services/vault_service.dart';
import 'package:locker/widgets/encrypted_thumbnail.dart';

class _FakeVaultService extends VaultService {
  int thumbnailCalls = 0;

  @override
  Future<Uint8List?> getThumbnailBytes(VaultedFile file) async {
    thumbnailCalls++;
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final file = VaultedFile(
    id: 'photo',
    originalName: 'photo.jpg',
    vaultPath: '/tmp/photo.jpg.enc',
    type: VaultedFileType.image,
    mimeType: 'image/jpeg',
    fileSize: 10,
    dateAdded: DateTime.utc(2024),
    isEncrypted: true,
    encryptionIv: 'iv',
  );

  Future<_FakeVaultService> pumpThumbnail(
    WidgetTester tester, {
    required bool hideEncryptedThumbnails,
  }) async {
    final service = _FakeVaultService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultServiceProvider.overrideWithValue(service),
          vaultSettingsProvider.overrideWith(
            (_) async => VaultSettings(
              hideEncryptedThumbnails: hideEncryptedThumbnails,
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 100,
              height: 100,
              child: EncryptedThumbnail(file: file),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return service;
  }

  testWidgets('hidden encrypted thumbnails show a type icon without decrypting',
      (tester) async {
    final service = await pumpThumbnail(tester, hideEncryptedThumbnails: true);

    expect(find.byIcon(Icons.image), findsOneWidget);
    expect(service.thumbnailCalls, 0);
  });

  testWidgets('visible encrypted thumbnails still request decrypted bytes',
      (tester) async {
    final service = await pumpThumbnail(tester, hideEncryptedThumbnails: false);

    expect(service.thumbnailCalls, 1);
  });

  test('hideEncryptedThumbnails survives settings JSON round-trip', () {
    final settings =
        const VaultSettings().copyWith(hideEncryptedThumbnails: true);

    expect(
      VaultSettings.fromJson(settings.toJson()).hideEncryptedThumbnails,
      isTrue,
    );
    expect(
      VaultSettings.fromJson(const VaultSettings().toJson())
          .hideEncryptedThumbnails,
      isFalse,
    );
  });
}
