import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'pb_client.dart';

/// Parses the sidecar's stdout handshake:
/// `LOCKER_PB_PORT=<n>`, `LOCKER_PB_TOKEN=<64-hex>`, `LOCKER_PB_READY=1`.
/// Any other line is ignored defensively (the contract says handshake-only,
/// but stdout is not guaranteed to stay silent forever).
class PbHandshakeParser {
  static const _portPrefix = 'LOCKER_PB_PORT=';
  static const _tokenPrefix = 'LOCKER_PB_TOKEN=';
  static const _readyLine = 'LOCKER_PB_READY=1';

  int? port;
  String? token;
  bool _ready = false;

  bool get isComplete => port != null && token != null && _ready;

  /// Feed one stdout line; returns true once the handshake is complete.
  bool feed(String line) {
    if (line.startsWith(_portPrefix)) {
      port = int.tryParse(line.substring(_portPrefix.length).trim());
    } else if (line.startsWith(_tokenPrefix)) {
      token = line.substring(_tokenPrefix.length).trim();
    } else if (line.startsWith(_readyLine)) {
      _ready = true;
    }
    return isComplete;
  }
}

/// Owns the PocketBase sidecar process: binary discovery (nativeLibraryDir),
/// spawn, handshake, health-wait, graceful stop.
///
/// Lifecycle: start() after vault unlock (non-decoy), stop() on lock/exit.
/// Hard process kills are recovered by a pid-file sweep on the next start —
/// Android does not reliably deliver an exit callback to Dart.
class PocketBaseRuntime {
  PocketBaseRuntime._();

  static final PocketBaseRuntime instance = PocketBaseRuntime._();

  static const _channel = MethodChannel('com.mossapps.locker/pb');
  static const _binaryName = 'libpocketbase.so';
  static const _pidFileName = 'sidecar.pid';

  Process? _process;
  PbClient? _client;
  bool _starting = false;
  AppLifecycleListener? _lifecycleListener;

  /// Client for the running sidecar; null while stopped or starting.
  /// P3's DAO layer consumes this.
  PbClient? get client => _client;

  bool get isRunning => _client != null;

  /// Spawn the sidecar and wait until it is healthy. No-op if already up.
  /// Throws on failure — callers that can tolerate a missing PB (the legacy
  /// store is still active until P4) should catch and log.
  Future<void> start() async {
    if (!Platform.isAndroid) return; // binary is arm64 ELF, Android-only
    if (isRunning || _starting) return;
    _starting = true;
    Process? proc;
    try {
      final nativeLibDir =
          await _channel.invokeMethod<String>('getNativeLibraryDir');
      final binary = '$nativeLibDir/$_binaryName';
      if (nativeLibDir == null || !await File(binary).exists()) {
        throw StateError(
          'PocketBase binary missing at $binary (run `make pb` before build)',
        );
      }

      final pbDir =
          '${(await getApplicationSupportDirectory()).path}/pocketbase';
      await Directory(pbDir).create(recursive: true);
      await _sweepOrphan(pbDir);

      proc = await Process.start(binary, [
        '--dir=$pbDir',
        '--http=127.0.0.1:0',
      ]);

      final parser = PbHandshakeParser();
      final ready = Completer<void>();
      final subs = <StreamSubscription>[
        proc.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          if (parser.feed(line) && !ready.isCompleted) ready.complete();
        }),
        proc.stderr.listen((_) {}),
      ];
      unawaited(proc.exitCode.then((code) async {
        if (!ready.isCompleted) {
          ready.completeError(
              StateError('sidecar exited before READY (code $code)'));
          return;
        }
        debugPrint('[PB] sidecar exited (code $code)');
        await _cleanup(pbDir, subs);
      }));

      await ready.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('no READY handshake within 15s'),
      );

      final client = PbClient(port: parser.port!, token: parser.token!);
      await _waitForHealth(client);

      await File('$pbDir/$_pidFileName').writeAsString('${proc.pid}');
      _process = proc;
      _client = client;
      _lifecycleListener ??= AppLifecycleListener(onDetach: () => unawaited(stop()));
      debugPrint('[PB] sidecar up: pid=${proc.pid} port=${parser.port}');
    } catch (e) {
      _client = null;
      if (proc != null) {
        proc.kill(ProcessSignal.sigterm);
        await proc.exitCode.catchError((_) => -1);
      }
      rethrow;
    } finally {
      _starting = false;
    }
  }

  /// Graceful stop: SIGTERM, wait for exit, drop the client.
  Future<void> stop() async {
    final p = _process;
    _process = null;
    _client?.close();
    _client = null;
    if (p != null) {
      p.kill(ProcessSignal.sigterm);
      await p.exitCode.catchError((_) => -1);
    }
  }

  /// Kill a sidecar left behind by a previous run whose process died without
  /// dispose. Signaling a recycled pid can only ever hit a process owned by
  /// our app uid, so worst case is a failed kill we ignore.
  Future<void> _sweepOrphan(String pbDir) async {
    final pidFile = File('$pbDir/$_pidFileName');
    try {
      final pid = int.tryParse((await pidFile.readAsString()).trim());
      if (pid != null && pid > 0) {
        Process.killPid(pid, ProcessSignal.sigterm);
        debugPrint('[PB] swept orphaned sidecar pid $pid');
      }
    } catch (_) {
      // no pid file or unreadable — nothing to sweep
    }
    try {
      await pidFile.delete();
    } catch (_) {}
  }

  Future<void> _waitForHealth(PbClient client) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      try {
        if (await client.health()) return;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw TimeoutException('sidecar healthy-wait failed within 5s');
  }

  Future<void> _cleanup(String pbDir, List<StreamSubscription> subs) async {
    _process = null;
    _client?.close();
    _client = null;
    for (final s in subs) {
      await s.cancel();
    }
    try {
      await File('$pbDir/$_pidFileName').delete();
    } catch (_) {}
  }
}
