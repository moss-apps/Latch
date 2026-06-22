import 'dart:typed_data';

import 'aes_gcm_cipher.dart';

/// Master-key wrapping: protects the vault master key with a key-wrapping key
/// (KWK) derived from the user credential, using AES-256-GCM so a wrong
/// credential fails authentication rather than silently producing garbage.
///
/// Stateless and pure — the credential-derived KWK and storage I/O live in
/// `EncryptionService`. This module only does the AEAD wrap/unwrap.
class KeyWrap {
  KeyWrap._();

  /// Wrap [masterKey] under [kwk] with the given [iv]. Returns
  /// ciphertext+tag.
  static Uint8List wrap(Uint8List masterKey, Uint8List kwk, Uint8List iv) {
    return AesGcmCipher.process(kwk, iv, masterKey, true);
  }

  /// Unwrap a wrapped key under [kwk] with the given [iv]. Throws if the GCM
  /// tag does not verify (wrong KWK / tampered wrapped key).
  static Uint8List unwrap(Uint8List wrappedKey, Uint8List kwk, Uint8List iv) {
    return AesGcmCipher.process(kwk, iv, wrappedKey, false);
  }
}
