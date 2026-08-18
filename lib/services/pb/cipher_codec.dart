import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../crypto/aes_gcm_cipher.dart';
import '../../crypto/key_derivation.dart';

/// Envelope/unwrap for PB secret columns: `[16-byte IV][ciphertext+tag]`,
/// base64, AES-256-GCM with the vault master key. PB never sees plaintext.
class CipherCodec {
  CipherCodec(this.key);

  final Uint8List key;

  static const int ivLength = 16;

  String seal(String plaintext) {
    final iv = KeyDerivation.randomBytes(ivLength);
    final ct = AesGcmCipher.process(
      key,
      iv,
      Uint8List.fromList(utf8.encode(plaintext)),
      true,
    );
    return base64Encode(Uint8List.fromList([...iv, ...ct]));
  }

  /// Throws (tag mismatch) on wrong key or tampered envelope — callers must
  /// treat that as authentication failure, never fall back to plaintext.
  String open(String envelope) {
    final bytes = base64Decode(envelope);
    if (bytes.length <= ivLength) {
      throw FormatException('envelope too short: ${bytes.length}B');
    }
    final pt = AesGcmCipher.process(
      key,
      bytes.sublist(0, ivLength),
      bytes.sublist(ivLength),
      false,
    );
    return utf8.decode(pt);
  }

  /// json columns carry the envelope wrapped in an object — the only json
  /// shape PB normalizes identically in both directions.
  Map<String, dynamic> sealJson(Object? value) => {'env': seal(jsonEncode(value))};

  Object? openJson(Map<String, dynamic> envelope) =>
      jsonDecode(open(envelope['env'] as String));
}

/// Deterministic PB record id for an app id. App ids (UUIDs with dashes,
/// album ids like 'recent') don't match PB's id rules, so use a 15-char
/// lowercase-hex sha256 slice — exactly PB's autogen id shape.
String pbRecordId(String appId) =>
    sha256.convert(utf8.encode(appId)).toString().substring(0, 15);
