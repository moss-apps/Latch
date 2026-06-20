import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:locker/services/encryption_service.dart';
import 'package:pointycastle/export.dart';

void main() {
  final key = Uint8List.fromList(List.generate(32, (i) => i));
  final iv = Uint8List.fromList(List.generate(16, (i) => i + 100));
  final plaintext = Uint8List.fromList(
      utf8.encode('Latch vault test plaintext — round trip!'));

  group('AES-256-GCM round-trip', () {
    test('encrypt then decryptDataGcm returns original', () async {
      final gcm = GCMBlockCipher(AESEngine())
        ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
      final encrypted = gcm.process(plaintext);

      final result = await EncryptionService.instance.decryptDataGcm(
        encrypted,
        base64Encode(iv),
        customKey: key,
      );

      expect(result.success, true);
      expect(result.data, plaintext);
    });

    test('tampered ciphertext fails GCM authentication', () async {
      final gcm = GCMBlockCipher(AESEngine())
        ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
      final encrypted = gcm.process(plaintext);

      encrypted[0] ^= 0xFF;

      final result = await EncryptionService.instance.decryptDataGcm(
        encrypted,
        base64Encode(iv),
        customKey: key,
      );

      expect(result.success, false);
    });

    test('file-based GCM round-trip (encryptBytesStreamedGcm → decryptStreamedFileToMemoryGcm)',
        () async {
      final tmpDir = await Directory.systemTemp.createTemp('latch_gcm_test');
      final encPath = '${tmpDir.path}/test.enc';

      final encResult = await EncryptionService.instance
          .encryptBytesStreamedGcm(plaintext, encPath, derivedKey: key);

      expect(encResult.success, true);
      expect(encResult.iv, isNotNull);

      final decResult = await EncryptionService.instance
          .decryptStreamedFileToMemoryGcm(
        encPath,
        encResult.iv!,
        derivedKey: key,
      );

      expect(decResult.success, true);
      expect(decResult.data, plaintext);

      await tmpDir.delete(recursive: true);
    });
  });

  group('AES-256-CTR round-trip', () {
    test('encrypt then decrypt returns original', () {
      final ctr = CTRStreamCipher(AESEngine())
        ..init(true, ParametersWithIV(KeyParameter(key), iv));
      final encrypted = ctr.process(plaintext);

      final decCtr = CTRStreamCipher(AESEngine())
        ..init(false, ParametersWithIV(KeyParameter(key), iv));
      final decrypted = decCtr.process(encrypted);

      expect(decrypted, plaintext);
    });
  });
}
