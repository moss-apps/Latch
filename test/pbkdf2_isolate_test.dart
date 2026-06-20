import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:locker/utils/pbkdf2_isolate.dart';
import 'package:pointycastle/export.dart';

void main() {
  group('PBKDF2-HMAC-SHA256', () {
    test('computePbkdf2Hash is deterministic', () async {
      final salt = Uint8List.fromList(List.generate(16, (i) => i));

      final hash1 = await computePbkdf2Hash(
        'password123',
        salt,
        iterations: 10000,
      );
      final hash2 = await computePbkdf2Hash(
        'password123',
        salt,
        iterations: 10000,
      );

      expect(hash1, hash2);
    });

    test('different passwords produce different hashes', () async {
      final salt = Uint8List.fromList(List.generate(16, (i) => i));

      final hash1 = await computePbkdf2Hash(
        'password123',
        salt,
        iterations: 10000,
      );
      final hash2 = await computePbkdf2Hash(
        'password456',
        salt,
        iterations: 10000,
      );

      expect(hash1, isNot(hash2));
    });

    test('different salts produce different hashes', () async {
      final salt1 = Uint8List.fromList(List.generate(16, (i) => i));
      final salt2 = Uint8List.fromList(List.generate(16, (i) => i + 1));

      final hash1 = await computePbkdf2Hash(
        'password123',
        salt1,
        iterations: 10000,
      );
      final hash2 = await computePbkdf2Hash(
        'password123',
        salt2,
        iterations: 10000,
      );

      expect(hash1, isNot(hash2));
    });

    test('matches direct pointycastle computation', () async {
      final salt = Uint8List.fromList(utf8.encode('saltsaltsaltsalt'));
      const password = 'testPassword';
      const iterations = 10000;

      final isolateHash = await computePbkdf2Hash(
        password,
        salt,
        iterations: iterations,
      );

      final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
        ..init(Pbkdf2Parameters(salt, iterations, 32));
      final directHash = base64Encode(
        pbkdf2.process(Uint8List.fromList(utf8.encode(password))),
      );

      expect(isolateHash, directHash);
    });
  });
}
