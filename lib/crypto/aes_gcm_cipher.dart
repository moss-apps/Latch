import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Stateless AES-256-GCM primitives. No I/O, no storage — give it a key and IV
/// and it encrypts/decrypts bytes. The GCM tag is 128 bits (16 bytes) and is
/// appended to the ciphertext by pointycastle's one-shot [process].
class AesGcmCipher {
  AesGcmCipher._();

  static const int tagBits = 128;

  /// Build an initialised GCM cipher. [forEncryption] true = encrypt.
  static GCMBlockCipher cipher(
    Uint8List key,
    Uint8List iv,
    bool forEncryption,
  ) {
    final c = GCMBlockCipher(AESEngine())
      ..init(forEncryption, AEADParameters(KeyParameter(key), tagBits, iv, Uint8List(0)));
    return c;
  }

  /// One-shot encrypt/decrypt. Returns ciphertext+tag (encrypt) or plaintext
  /// (decrypt). Throws [InvalidCipherTextException] on decrypt if the tag does
  /// not verify — callers must treat that as authentication failure.
  static Uint8List process(
    Uint8List key,
    Uint8List iv,
    Uint8List data,
    bool forEncryption,
  ) {
    return cipher(key, iv, forEncryption).process(data);
  }
}
