import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/services/desktop_link/transfer_client.dart';

/// Stub latchd pairing receiver: bearer-gated /info, /keybundle,
/// /blob/&lt;sha&gt;, /manifest. Records the request order so tests can
/// assert the manifest lands last.
class StubReceiver {
  StubReceiver._(this._server, this.token);

  final HttpServer _server;
  final String token;

  final uploadedBlobs = <String, Uint8List>{};
  Map<String, dynamic>? uploadedKeybundle;
  Uint8List? uploadedManifest;
  final order = <String>[];
  final Set<String> preexistingHashes = {};
  bool hasManifest = false;
  bool rejectToken = false;

  static Future<StubReceiver> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final random = Random.secure();
    final token = List<int>.generate(32, (_) => random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final stub = StubReceiver._(server, token);
    server.listen(stub._handle);
    return stub;
  }

  Uri get base => Uri.parse('http://127.0.0.1:${_server.port}');
  String get pairingUrl => '${base.toString()}/#$token';
  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final authed = req.headers.value(HttpHeaders.authorizationHeader) ==
        'Bearer $token';
    if (rejectToken || !authed) {
      _json(req, HttpStatus.unauthorized, {'error': 'unauthorized'});
      return;
    }
    final segments = req.uri.pathSegments;
    if (req.method == 'GET' && segments.length == 1 && segments[0] == 'info') {
      _json(req, HttpStatus.ok, {
        'app': 'latchd',
        'protocol': 2,
        'hasManifest': hasManifest,
        'hashes': preexistingHashes.toList(),
      });
      return;
    }
    if (req.method == 'PUT' && segments.length == 1) {
      final body = await req.fold<List<int>>(
          [], (acc, c) => acc..addAll(c));
      final bytes = Uint8List.fromList(body);
      order.add(segments[0]);
      switch (segments[0]) {
        case 'keybundle':
          uploadedKeybundle = jsonDecode(utf8.decode(bytes))
              as Map<String, dynamic>;
          _json(req, HttpStatus.ok, {'stored': 'keybundle'});
        case 'manifest':
          uploadedManifest = bytes;
          _json(req, HttpStatus.ok, {'stored': 'manifest'});
        default:
          _json(req, HttpStatus.notFound, {'error': 'unknown route'});
      }
      return;
    }
    if (req.method == 'PUT' &&
        segments.length == 2 &&
        segments[0] == 'blob') {
      final sha = segments[1];
      final body = await req.fold<List<int>>(
          [], (acc, c) => acc..addAll(c));
      final bytes = Uint8List.fromList(body);
      if (sha256.convert(bytes).toString() != sha) {
        _json(req, HttpStatus.unprocessableEntity, {'error': 'mismatch'});
        return;
      }
      order.add('blob');
      uploadedBlobs[sha] = bytes;
      _json(req, HttpStatus.ok, {'stored': sha});
      return;
    }
    _json(req, HttpStatus.notFound, {'error': 'unknown route'});
  }

  void _json(HttpRequest req, int status, Map<String, dynamic> body) {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    req.response.close();
  }
}

DesktopVaultSnapshot snapshotOf({
  required Map<String, Uint8List> blobs,
  Map<String, dynamic>? keybundle,
  Uint8List? manifest,
}) {
  return DesktopVaultSnapshot(
    fileCount: blobs.length,
    totalBytes: blobs.values.fold<int>(0, (n, b) => n + b.length),
    manifestBytes:
        manifest ?? Uint8List.fromList(utf8.encode('manifest-bytes')),
    blobs: blobs,
    keybundle: keybundle,
  );
}

const testKeybundle = {
  'wrappedKey': 'eA==',
  'wrapSalt': 'cw==',
  'wrapIv': 'AA==',
  'argon2': {'t': 3, 'm': 16384, 'p': 1},
};

const goodToken = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  late StubReceiver receiver;
  late DesktopPushClient client;

  setUp(() async {
    receiver = await StubReceiver.start();
    client = DesktopPushClient();
  });

  tearDown(() async {
    client.close();
    await receiver.close();
  });

  group('parsePairingUrl', () {
    test('accepts http URL with #token fragment', () {
      final parsed =
          DesktopPushClient.parsePairingUrl('http://192.168.1.24:39371/#$goodToken');
      expect(parsed, isNotNull);
      final (base, token) = parsed!;
      expect(base.host, '192.168.1.24');
      expect(base.port, 39371);
      expect(token, goodToken);
    });

    test('rejects missing token, wrong scheme, garbage', () {
      expect(DesktopPushClient.parsePairingUrl('http://1.2.3.4:1/#xyz'),
          isNull);
      expect(
          DesktopPushClient.parsePairingUrl('https://1.2.3.4:1/#$goodToken'),
          isNull);
      expect(DesktopPushClient.parsePairingUrl(goodToken), isNull);
      expect(DesktopPushClient.parsePairingUrl('  '), isNull);
    });
  });

  test('check reports receiver state and honors token', () async {
    final info = await client.check(
        base: receiver.base, token: receiver.token);
    expect(info.hasManifest, isFalse);
    expect(info.blobCount, 0);

    receiver.rejectToken = true;
    expect(
      () => client.check(base: receiver.base, token: receiver.token),
      throwsA(isA<PushRejectedException>()),
    );
  });

  test('push uploads keybundle, only missing blobs, manifest last',
      () async {
    final keep = Uint8List.fromList([1, 2, 3]);
    final fresh = Uint8List.fromList([9, 8, 7, 6]);
    final keepSha = sha256.convert(keep).toString();
    final freshSha = sha256.convert(fresh).toString();
    receiver.preexistingHashes.add(keepSha);
    receiver.hasManifest = true;

    final progress = <DesktopPushProgress>[];
    final report = await client.push(
      base: receiver.base,
      token: receiver.token,
      snapshot: snapshotOf(
        blobs: {keepSha: keep, freshSha: fresh},
        keybundle: testKeybundle,
      ),
      onProgress: progress.add,
    );

    expect(report.pushed, 1);
    expect(report.alreadyPresent, 1);
    expect(report.bytes, fresh.length);
    expect(receiver.uploadedBlobs.keys, [freshSha]);
    expect(receiver.uploadedKeybundle, testKeybundle);
    expect(receiver.uploadedManifest, isNotNull);
    expect(receiver.order.last, 'manifest');
    expect(receiver.order.first, 'keybundle');
    expect(progress.length, 1);
    expect(progress.single.sent, 1);
    expect(progress.single.total, 1);
  });

  test('push is rejected when the code has expired', () async {
    receiver.rejectToken = true;
    expect(
      () => client.push(
        base: receiver.base,
        token: receiver.token,
        snapshot: snapshotOf(blobs: {}, keybundle: testKeybundle),
      ),
      throwsA(isA<PushRejectedException>()),
    );
    expect(receiver.order, isEmpty);
  });

  test('legacy vault aborts before any network traffic', () async {
    expect(
      () => client.push(
        base: receiver.base,
        token: receiver.token,
        snapshot: snapshotOf(blobs: const {}, keybundle: null),
      ),
      throwsA(isA<LegacyVaultException>()),
    );
    expect(receiver.order, isEmpty);
  });

  test('unreachable desktop maps to DesktopUnreachableException', () async {
    final deadBase = Uri.parse('http://127.0.0.1:9');
    expect(
      () => client.check(base: deadBase, token: receiver.token),
      throwsA(isA<DesktopUnreachableException>()),
    );
  });

  test('cancel flag aborts the push after the first blob', () async {
    final a = Uint8List.fromList(List<int>.filled(8, 1));
    final b = Uint8List.fromList(List<int>.filled(8, 2));
    final shaA = sha256.convert(a).toString();
    final shaB = sha256.convert(b).toString();

    var calls = 0;
    await expectLater(
      client.push(
        base: receiver.base,
        token: receiver.token,
        snapshot: snapshotOf(
          blobs: {shaA: a, shaB: b},
          keybundle: testKeybundle,
        ),
        isCancelled: () => ++calls > 1,
      ),
      throwsA(isA<PushCancelledException>()),
    );
    expect(receiver.uploadedBlobs.length, 1);
    expect(receiver.uploadedManifest, isNull);
  });
}
