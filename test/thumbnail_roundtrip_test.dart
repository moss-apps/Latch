import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:locker/services/encryption_service.dart';

// Verifies the crypto invariant the encrypted-thumbnail system relies on:
// a GCM-encrypted thumb (same wire format VaultService._encryptAndStoreThumbnail
// writes) round-trips through decryptStreamedFileToMemoryGcm, and a wrong/stale
// key is rejected by GCM auth — which is what drives lazy regeneration after a
// re-encrypt changes the per-file key.
void main() {
  final key = Uint8List.fromList(List.generate(32, (i) => i));
  final wrongKey = Uint8List.fromList(List.generate(32, (i) => i + 1));
  final thumbBytes = Uint8List.fromList(List.generate(2048, (i) => i & 0xFF));

  test('encrypted thumbnail round-trips through the thumb decrypt path',
      () async {
    final tmpDir = await Directory.systemTemp.createTemp('latch_thumb_test');
    final encPath = '${tmpDir.path}/thumb.enc';

    final enc = await EncryptionService.instance
        .encryptBytesStreamedGcm(thumbBytes, encPath, derivedKey: key);
    expect(enc.success, true);
    expect(enc.iv, isNotNull);

    final dec = await EncryptionService.instance.decryptStreamedFileToMemoryGcm(
      encPath,
      enc.iv!,
      derivedKey: key,
    );
    expect(dec.success, true);
    expect(dec.data, thumbBytes);

    await tmpDir.delete(recursive: true);
  });

  test('stale thumb (wrong key) is rejected → triggers lazy regeneration',
      () async {
    final tmpDir = await Directory.systemTemp.createTemp('latch_thumb_stale');
    final encPath = '${tmpDir.path}/thumb.enc';

    final enc = await EncryptionService.instance
        .encryptBytesStreamedGcm(thumbBytes, encPath, derivedKey: key);
    expect(enc.success, true);

    final dec = await EncryptionService.instance.decryptStreamedFileToMemoryGcm(
      encPath,
      enc.iv!,
      derivedKey: wrongKey,
    );
    expect(dec.success, false);

    await tmpDir.delete(recursive: true);
  });
}
