import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locker/services/desktop_link/usb_link.dart';

/// Stub latchd USB handshake: pending until [approveAfter] hellos, then
/// approved with [token]. Wrong modes get 409, [deny] forces 403.
class StubUsb {
  StubUsb._(this._server, this.token);

  final HttpServer _server;
  final String token;

  int hellos = 0;
  int approveAfter = 0;
  bool deny = false;
  String expectMode = 'push';
  String? lastDevice;

  static Future<StubUsb> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final stub = StubUsb._(server, 'c' * 64);
    server.listen(stub._handle);
    return stub;
  }

  int get port => _server.port;
  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    if (req.method == 'POST' && req.uri.path == '/usb-hello') {
      final body = await req.fold<List<int>>([], (acc, c) => acc..addAll(c));
      final json = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
      lastDevice = json['device'] as String?;
      if (json['mode'] != expectMode) {
        _json(req, HttpStatus.conflict, {
          'error': 'the computer is in "push" mode — switch and try again',
        });
        return;
      }
      if (deny) {
        _json(req, HttpStatus.forbidden, {'status': 'denied'});
        return;
      }
      hellos++;
      if (hellos > approveAfter) {
        _json(req, HttpStatus.ok, {'status': 'approved', 'token': token});
      } else {
        _json(req, HttpStatus.ok, {'status': 'pending'});
      }
      return;
    }
    _json(req, HttpStatus.notFound, {'error': 'not found'});
  }

  void _json(HttpRequest req, int status, Map<String, dynamic> body) {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    req.response.close();
  }
}

/// A bound-then-closed port: guaranteed connection-refused on loopback.
Future<int> deadPort() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  await server.close(force: true);
  return port;
}

void main() {
  late StubUsb stub;
  late UsbLink link;

  setUp(() async {
    stub = await StubUsb.start();
    link = UsbLink();
  });

  tearDown(() async {
    link.close();
    await stub.close();
  });

  test('immediate approval returns base + token', () async {
    final (base, token) = await link.connect(
      mode: 'push',
      deviceLabel: 'Test Phone',
      ports: [stub.port],
    );
    expect(base.host, '127.0.0.1');
    expect(base.port, stub.port);
    expect(token, stub.token);
    expect(stub.lastDevice, 'Test Phone');
  });

  test('pending then approved reports the session first', () async {
    stub.approveAfter = 2;
    var found = false;
    final (base, token) = await link.connect(
      mode: 'push',
      deviceLabel: 'Test Phone',
      ports: [stub.port],
      pollInterval: const Duration(milliseconds: 10),
      onSessionFound: () => found = true,
    );
    expect(token, stub.token);
    expect(base.port, stub.port);
    expect(found, isTrue);
    expect(stub.hellos, greaterThan(2));
  });

  test('mode mismatch maps to UsbModeMismatchException', () async {
    stub.expectMode = 'restore';
    expect(
      () => link.connect(
        mode: 'push',
        deviceLabel: 'Test Phone',
        ports: [stub.port],
      ),
      throwsA(isA<UsbModeMismatchException>()),
    );
  });

  test('deny maps to UsbDeniedException', () async {
    stub.deny = true;
    expect(
      () => link.connect(
        mode: 'push',
        deviceLabel: 'Test Phone',
        ports: [stub.port],
      ),
      throwsA(isA<UsbDeniedException>()),
    );
  });

  test('nothing listening maps to UsbNoRouteException', () async {
    final port = await deadPort();
    expect(
      () => link.connect(
        mode: 'push',
        deviceLabel: 'Test Phone',
        ports: [port],
      ),
      throwsA(isA<UsbNoRouteException>()),
    );
  });

  test('approval wait times out', () async {
    stub.approveAfter = 1 << 30;
    expect(
      () => link.connect(
        mode: 'push',
        deviceLabel: 'Test Phone',
        ports: [stub.port],
        pollInterval: const Duration(milliseconds: 10),
        approveTimeout: const Duration(milliseconds: 50),
      ),
      throwsA(isA<UsbApprovalTimeoutException>()),
    );
  });

  test('deviceLabel never throws', () async {
    expect(await UsbLink.deviceLabel(), isNotEmpty);
  });
}
