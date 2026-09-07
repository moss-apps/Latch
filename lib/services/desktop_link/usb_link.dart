import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// The phone found no latchd session on the cable: unplugged, USB
/// debugging off, or the `adb reverse` route missing.
class UsbNoRouteException implements Exception {
  const UsbNoRouteException(this.detail);
  final String detail;
  @override
  String toString() => 'no USB route: $detail';
}

/// The desktop owner tapped Deny.
class UsbDeniedException implements Exception {
  const UsbDeniedException();
  @override
  String toString() => 'denied on the computer';
}

/// Nobody tapped Allow before the wait ran out.
class UsbApprovalTimeoutException implements Exception {
  const UsbApprovalTimeoutException();
  @override
  String toString() => 'USB approval timed out';
}

/// The desktop session is in the other mode (push vs restore).
class UsbModeMismatchException implements Exception {
  const UsbModeMismatchException(this.message);
  final String message;
  @override
  String toString() => 'USB mode mismatch: $message';
}

/// The user backed out while waiting.
class UsbCancelledException implements Exception {
  const UsbCancelledException();
  @override
  String toString() => 'USB connect cancelled';
}

/// Tap-to-approve USB connect (P6.4r). The phone probes its own loopback —
/// reachable only through `adb reverse`, which already proves physical
/// possession of an adb-authorized device — announces itself, and waits
/// for the desktop owner to tap Allow. Returns the session base + token,
/// after which the normal bearer flow ([DesktopPushClient] /
/// [DesktopRestoreClient]) takes over. Nothing is typed.
class UsbLink {
  UsbLink({HttpClient? http}) : _http = http ?? HttpClient();

  final HttpClient _http;

  /// Ports probed on the phone's loopback: the desktop's default pairing
  /// port plus its preferred range. A session on an ephemeral fallback
  /// port is not discoverable — the UI falls back to manual entry there.
  static final List<int> defaultPorts = [
    7801,
    for (var p = 7810; p <= 7820; p++) p,
  ];

  void close() => _http.close(force: true);

  /// "samsung SM-A065F", "Pixel 8" — what the desktop approval prompt
  /// shows. Never leaves the cable.
  static Future<String> deviceLabel() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        final name = '${a.manufacturer} ${a.model}'.trim();
        return name.isEmpty ? 'Android phone' : name;
      }
      if (Platform.isIOS) {
        final i = await info.iosInfo;
        final name = i.name.isEmpty ? i.model : i.name;
        return name.isEmpty ? 'iPhone' : name;
      }
    } catch (_) {
      // Model name is a nicety; the handshake works without it.
    }
    return 'USB phone';
  }

  /// Probes [ports] for a latchd session, then waits for the desktop
  /// owner to approve. [mode] is 'push' or 'restore' and must match the
  /// desktop session. [onSessionFound] fires once a session answers, so
  /// the UI can switch from "looking" to "tap Allow on the computer".
  Future<(Uri, String)> connect({
    required String mode,
    required String deviceLabel,
    List<int>? ports,
    Duration pollInterval = const Duration(seconds: 2),
    Duration approveTimeout = const Duration(minutes: 4),
    void Function()? onSessionFound,
    bool Function()? isCancelled,
  }) async {
    bool cancelled() => isCancelled?.call() ?? false;
    final targets = ports ?? defaultPorts;
    final found = await Future.wait(
      [for (final port in targets) _hello(port, mode, deviceLabel)],
    );
    final answered = found.whereType<_Hello>().toList();
    for (final h in answered) {
      if (h.status == _Hello.approved) return (h.base, h.token!);
    }
    final pending = answered.where((h) => h.status == _Hello.pending);
    if (pending.isNotEmpty) {
      onSessionFound?.call();
      return _waitForApproval(
        pending.first.base,
        mode: mode,
        deviceLabel: deviceLabel,
        pollInterval: pollInterval,
        approveTimeout: approveTimeout,
        isCancelled: isCancelled,
      );
    }
    for (final h in answered) {
      if (h.status == _Hello.denied) throw const UsbDeniedException();
    }
    for (final h in answered) {
      if (h.status == _Hello.mismatch) {
        throw UsbModeMismatchException(
          h.error!.isEmpty ? 'wrong session mode on the computer' : h.error!,
        );
      }
    }
    if (cancelled()) throw const UsbCancelledException();
    throw const UsbNoRouteException(
      'nothing answered on the cable — check the cable, USB debugging, '
      'and the adb reverse route',
    );
  }

  Future<(Uri, String)> _waitForApproval(
    Uri base, {
    required String mode,
    required String deviceLabel,
    required Duration pollInterval,
    required Duration approveTimeout,
    bool Function()? isCancelled,
  }) async {
    final deadline = DateTime.now().add(approveTimeout);
    var consecutiveFailures = 0;
    while (true) {
      if (isCancelled?.call() ?? false) throw const UsbCancelledException();
      if (DateTime.now().isAfter(deadline)) {
        throw const UsbApprovalTimeoutException();
      }
      await Future<void>.delayed(pollInterval);
      if (isCancelled?.call() ?? false) throw const UsbCancelledException();
      final h = await _hello(base.port, mode, deviceLabel);
      if (h == null) {
        // Cable wiggled loose mid-wait: a few misses before giving up.
        if (++consecutiveFailures >= 3) {
          throw const UsbNoRouteException(
            'USB connection lost — check the cable is seated and USB '
            'debugging is still on, then try again',
          );
        }
        continue;
      }
      consecutiveFailures = 0;
      switch (h.status) {
        case _Hello.approved:
          return (h.base, h.token!);
        case _Hello.pending:
          continue;
        case _Hello.denied:
          throw const UsbDeniedException();
        case _Hello.mismatch:
          throw UsbModeMismatchException(
            h.error!.isEmpty ? 'wrong session mode on the computer' : h.error!,
          );
      }
    }
  }

  /// One handshake attempt against 127.0.0.1:[port]. Null means nothing
  /// latchd-like there (refused, timeout, or a stranger's 404).
  Future<_Hello?> _hello(int port, String mode, String device) async {
    final base = Uri(scheme: 'http', host: '127.0.0.1', port: port);
    try {
      final req = await _http
          .postUrl(base.resolve('/usb-hello'))
          .timeout(const Duration(seconds: 2));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'device': device, 'mode': mode}));
      final res = await req.close().timeout(const Duration(seconds: 2));
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 2));
      if (res.statusCode == HttpStatus.notFound) return null;
      final json = jsonDecode(body) as Map<String, dynamic>;
      final status = json['status'] as String?;
      if (res.statusCode == HttpStatus.ok && status == 'approved') {
        final token = json['token'] as String?;
        if (token == null || token.isEmpty) return null;
        return _Hello(base: base, status: _Hello.approved, token: token);
      }
      if (res.statusCode == HttpStatus.ok && status == 'pending') {
        return _Hello(base: base, status: _Hello.pending);
      }
      if (res.statusCode == HttpStatus.conflict) {
        return _Hello(
          base: base,
          status: _Hello.mismatch,
          error: (json['error'] as String?) ?? '',
        );
      }
      if (res.statusCode == HttpStatus.forbidden) {
        return _Hello(base: base, status: _Hello.denied);
      }
      return null;
    } on SocketException {
      return null;
    } on HttpException {
      return null;
    } on TimeoutException {
      return null;
    } on FormatException {
      return null;
    }
  }
}

class _Hello {
  const _Hello({required this.base, required this.status, this.token, this.error});

  static const approved = 'approved';
  static const pending = 'pending';
  static const denied = 'denied';
  static const mismatch = 'mismatch';

  final Uri base;
  final String status;
  final String? token;
  final String? error;
}
