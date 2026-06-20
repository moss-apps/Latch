import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

class _Argon2Args {
  final String credential;
  final Uint8List salt;
  final int iterations;
  final int memoryPowerOf2;
  final int lanes;
  final int keyLength;
  const _Argon2Args(
    this.credential,
    this.salt,
    this.iterations,
    this.memoryPowerOf2,
    this.lanes,
    this.keyLength,
  );
}

Uint8List _computeArgon2id(_Argon2Args args) {
  final params = Argon2Parameters(
    Argon2Parameters.ARGON2_id,
    args.salt,
    desiredKeyLength: args.keyLength,
    iterations: args.iterations,
    memoryPowerOf2: args.memoryPowerOf2,
    lanes: args.lanes,
    version: Argon2Parameters.ARGON2_VERSION_13,
  );
  final generator = Argon2BytesGenerator()..init(params);
  return generator.process(Uint8List.fromList(utf8.encode(args.credential)));
}

Future<Uint8List> computeArgon2idHash(
  String credential,
  Uint8List salt, {
  int iterations = 3,
  int memoryPowerOf2 = 14,
  int lanes = 1,
  int keyLength = 32,
}) {
  return compute(
    _computeArgon2id,
    _Argon2Args(
      credential,
      salt,
      iterations,
      memoryPowerOf2,
      lanes,
      keyLength,
    ),
  );
}
