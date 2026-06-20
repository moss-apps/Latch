import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

class _Pbkdf2Args {
  final String credential;
  final Uint8List salt;
  final int iterations;
  final int keyLength;
  const _Pbkdf2Args(this.credential, this.salt, this.iterations, this.keyLength);
}

String _computePbkdf2(_Pbkdf2Args args) {
  final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(args.salt, args.iterations, args.keyLength));
  final hash =
      pbkdf2.process(Uint8List.fromList(utf8.encode(args.credential)));
  return base64Encode(hash);
}

Future<String> computePbkdf2Hash(
  String credential,
  Uint8List salt, {
  int iterations = 600000,
  int keyLength = 32,
}) {
  return compute(
    _computePbkdf2,
    _Pbkdf2Args(credential, salt, iterations, keyLength),
  );
}
