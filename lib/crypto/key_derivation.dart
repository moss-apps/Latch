import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

import '../utils/argon2_isolate.dart';

/// Key derivation + random byte generation. Stateless; PBKDF2 runs on the
/// calling isolate (cheap for single keys) or, for bulk work, via
/// [deriveFileKeyAsync] on a background isolate. Argon2id delegates to the
/// shared isolate helper.
class KeyDerivation {
  KeyDerivation._();

  static const int keySize = 32; // 256 bits
  static const int ivSize = 16; // 128 bits

  /// Cryptographically secure random bytes.
  static Uint8List randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  /// Random 128-bit IV.
  static Uint8List generateIV() => randomBytes(ivSize);

  /// Random 256-bit salt for per-file key derivation.
  static Uint8List generateFileSalt() => randomBytes(32);

  /// Derive a per-file key from the master key + salt using PBKDF2/HMAC-SHA256.
  static Uint8List deriveFileKey(
    Uint8List masterKey,
    Uint8List salt,
    int iterations,
  ) {
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, keySize));
    return pbkdf2.process(masterKey);
  }

  /// Same as [deriveFileKey] but on a background isolate (for bulk work).
  static Future<Uint8List> deriveFileKeyAsync(
    Uint8List masterKey,
    Uint8List salt,
    int iterations,
  ) {
    return compute(_pbkdf2Isolate, _Pbkdf2Params(masterKey, salt, iterations));
  }

  /// Derive a key from a password using PBKDF2/HMAC-SHA256.
  static Uint8List deriveKeyFromPassword(
    String password, {
    Uint8List? salt,
    int iterations = 100000,
  }) {
    salt ??= randomBytes(16);
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, keySize));
    return pbkdf2.process(Uint8List.fromList(utf8.encode(password)));
  }

  /// Argon2id key-derivation (KWK derivation) on a background isolate.
  static Future<Uint8List> argon2id(
    String credential,
    Uint8List salt, {
    int iterations = 3,
    int memoryPowerOf2 = 14,
    int lanes = 1,
    int keyLength = keySize,
  }) {
    return computeArgon2idHash(
      credential,
      salt,
      iterations: iterations,
      memoryPowerOf2: memoryPowerOf2,
      lanes: lanes,
      keyLength: keyLength,
    );
  }

  static Uint8List _pbkdf2Isolate(_Pbkdf2Params params) {
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(params.salt, params.iterations, keySize));
    return pbkdf2.process(params.masterKey);
  }
}

class _Pbkdf2Params {
  final Uint8List masterKey;
  final Uint8List salt;
  final int iterations;
  const _Pbkdf2Params(this.masterKey, this.salt, this.iterations);
}
