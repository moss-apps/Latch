import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

import 'package:locker/utils/argon2_isolate.dart';

void main() {
  group('Argon2id KWK derivation', () {
    test('is deterministic — same credential + salt → same KWK', () async {
      final salt = Uint8List.fromList(List.generate(32, (i) => i));
      final kwk1 = await computeArgon2idHash(
        'testPassword123',
        salt,
        iterations: 1,
        memoryPowerOf2: 10,
      );
      final kwk2 = await computeArgon2idHash(
        'testPassword123',
        salt,
        iterations: 1,
        memoryPowerOf2: 10,
      );
      expect(base64Encode(kwk1), equals(base64Encode(kwk2)));
    });

    test('different credentials produce different KWKs', () async {
      final salt = Uint8List.fromList(List.generate(32, (i) => i));
      final kwk1 = await computeArgon2idHash(
        'password1',
        salt,
        iterations: 1,
        memoryPowerOf2: 10,
      );
      final kwk2 = await computeArgon2idHash(
        'password2',
        salt,
        iterations: 1,
        memoryPowerOf2: 10,
      );
      expect(base64Encode(kwk1), isNot(equals(base64Encode(kwk2))));
    });

    test('different salts produce different KWKs', () async {
      final salt1 = Uint8List.fromList(List.generate(32, (i) => i));
      final salt2 = Uint8List.fromList(List.generate(32, (i) => i + 100));
      final kwk1 = await computeArgon2idHash(
        'samePassword',
        salt1,
        iterations: 1,
        memoryPowerOf2: 10,
      );
      final kwk2 = await computeArgon2idHash(
        'samePassword',
        salt2,
        iterations: 1,
        memoryPowerOf2: 10,
      );
      expect(base64Encode(kwk1), isNot(equals(base64Encode(kwk2))));
    });

    test('produces 32-byte key', () async {
      final salt = Uint8List.fromList(List.generate(32, (i) => i));
      final kwk = await computeArgon2idHash(
        'test',
        salt,
        iterations: 1,
        memoryPowerOf2: 10,
      );
      expect(kwk.length, equals(32));
    });
  });

  group('Key wrap/unwrap (AES-256-GCM)', () {
    Uint8List wrapKey(Uint8List masterKey, Uint8List kwk, Uint8List iv) {
      final cipher = GCMBlockCipher(AESEngine());
      cipher.init(
        true,
        AEADParameters(KeyParameter(kwk), 128, iv, Uint8List(0)),
      );
      return cipher.process(masterKey);
    }

    Uint8List unwrapKey(Uint8List wrappedKey, Uint8List kwk, Uint8List iv) {
      final cipher = GCMBlockCipher(AESEngine());
      cipher.init(
        false,
        AEADParameters(KeyParameter(kwk), 128, iv, Uint8List(0)),
      );
      return cipher.process(wrappedKey);
    }

    test('wrap then unwrap returns original master key', () async {
      final masterKey = Uint8List.fromList(
        List.generate(32, (i) => i * 7 + 3),
      );
      final salt = Uint8List.fromList(List.generate(32, (i) => i));
      final kwk = await computeArgon2idHash(
        'mySecretPassword',
        salt,
        iterations: 1,
        memoryPowerOf2: 10,
      );
      final iv = Uint8List.fromList(List.generate(16, (i) => i + 50));

      final wrappedKey = wrapKey(masterKey, kwk, iv);
      final unwrappedKey = unwrapKey(wrappedKey, kwk, iv);

      expect(base64Encode(unwrappedKey), equals(base64Encode(masterKey)));
    });

    test('unwrap with wrong KWK fails (GCM authentication)', () async {
      final masterKey = Uint8List.fromList(
        List.generate(32, (i) => i * 7 + 3),
      );
      final salt = Uint8List.fromList(List.generate(32, (i) => i));
      final kwkCorrect = await computeArgon2idHash(
        'correctPassword',
        salt,
        iterations: 1,
        memoryPowerOf2: 10,
      );
      final kwkWrong = await computeArgon2idHash(
        'wrongPassword',
        salt,
        iterations: 1,
        memoryPowerOf2: 10,
      );
      final iv = Uint8List.fromList(List.generate(16, (i) => i + 50));

      final wrappedKey = wrapKey(masterKey, kwkCorrect, iv);

      expect(
        () => unwrapKey(wrappedKey, kwkWrong, iv),
        throwsA(isA<Object>()),
      );
    });

    test('unwrap with tampered wrapped key fails', () async {
      final masterKey = Uint8List.fromList(
        List.generate(32, (i) => i * 7 + 3),
      );
      final salt = Uint8List.fromList(List.generate(32, (i) => i));
      final kwk = await computeArgon2idHash(
        'password',
        salt,
        iterations: 1,
        memoryPowerOf2: 10,
      );
      final iv = Uint8List.fromList(List.generate(16, (i) => i + 50));

      final wrappedKey = wrapKey(masterKey, kwk, iv);
      final tamperedKey = Uint8List.fromList(wrappedKey);
      tamperedKey[0] ^= 0xFF;

      expect(
        () => unwrapKey(tamperedKey, kwk, iv),
        throwsA(isA<Object>()),
      );
    });
  });
}
