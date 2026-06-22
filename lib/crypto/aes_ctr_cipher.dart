import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Stateless AES-256-CTR primitives. CTR is a stream cipher (no padding), so
/// [process] is its own inverse — the same call encrypts and decrypts.
class AesCtrCipher {
  AesCtrCipher._();

  /// Build an initialised CTR cipher. [forEncryption] is advisory (CTR is
  /// symmetric) but kept for symmetry with [AesGcmCipher].
  static CTRStreamCipher cipher(
    Uint8List key,
    Uint8List iv,
    bool forEncryption,
  ) {
    return CTRStreamCipher(AESEngine())
      ..init(forEncryption, ParametersWithIV<KeyParameter>(KeyParameter(key), iv));
  }

  /// Encrypt or decrypt a buffer in one shot (its own inverse).
  static Uint8List process(
    Uint8List key,
    Uint8List iv,
    Uint8List data,
    bool forEncryption,
  ) {
    return cipher(key, iv, forEncryption).process(data);
  }
}
