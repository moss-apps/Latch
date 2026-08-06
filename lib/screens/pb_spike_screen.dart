// THROWAWAY — P0 spike. Delete once P2's PocketBaseRuntime lands.
//
// Exercises the embedded PocketBase sidecar end to end: discover the bundled .so
// via nativeLibraryDir, spawn it on loopback, parse the port+token it prints,
// then hit /api/health over loopback (with + without token). The "no token"
// request must 401 (token gate works); the "with token" request must 200.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class PbSpikeScreen extends StatefulWidget {
  const PbSpikeScreen({super.key});

  @override
  State<PbSpikeScreen> createState() => _PbSpikeScreenState();
}

class _PbSpikeScreenState extends State<PbSpikeScreen> {
  static const _channel = MethodChannel('com.mossapps.locker/pb');
  static const _binaryName = 'libpocketbase.so';
  static const _tokenHeader = 'X-Locker-Token';

  final _log = <String>[];
  Process? _process;
  String? _port;
  String? _token;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _say(String line) {
    if (!mounted) return;
    setState(() => _log.add(line));
  }

  Future<void> _run() async {
    try {
      if (!Platform.isAndroid) {
        _say('P0 spike is Android-only (binary is arm64 ELF). Aborting.');
        return;
      }

      final nativeLibDir =
          await _channel.invokeMethod<String>('getNativeLibraryDir');
      if (nativeLibDir == null) {
        _say('nativeLibraryDir is null — binary not bundled?');
        return;
      }
      final binary = '$nativeLibDir/$_binaryName';
      if (!await File(binary).exists()) {
        _say(
            'binary missing: $binary  (run `make pb` before building the apk)');
        return;
      }

      final dataDir = (await getApplicationSupportDirectory()).path;
      final pbDir = '$dataDir/pocketbase';
      await Directory(pbDir).create(recursive: true);

      _say('spawn: $binary --dir=$pbDir --http=127.0.0.1:0');
      final proc = await Process.start(binary, [
        '--dir=$pbDir',
        '--http=127.0.0.1:0',
      ]);
      _process = proc;
      setState(() => _running = true);

      final ready = Completer<void>();
      proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _say('stdout: $line');
        if (line.startsWith('LOCKER_PB_PORT=')) {
          _port = line.substring('LOCKER_PB_PORT='.length).trim();
        } else if (line.startsWith('LOCKER_PB_TOKEN=')) {
          _token = line.substring('LOCKER_PB_TOKEN='.length).trim();
        } else if (line.startsWith('LOCKER_PB_READY=1') && !ready.isCompleted) {
          ready.complete();
        }
      });
      proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => _say('stderr: $line'));

      proc.exitCode.then((code) {
        _say('process exited (code $code)');
        if (!ready.isCompleted) {
          ready.completeError('process exited before READY (code $code)');
        }
        if (mounted) setState(() => _running = false);
      });

      await ready.future.timeout(const Duration(seconds: 15),
          onTimeout: () => throw TimeoutException('no READY within 15s'));

      _say('READY. port=$_port  token=${_token?.substring(0, 8)}…');

      final base = 'http://127.0.0.1:$_port';
      final noToken = await http.get(Uri.parse('$base/api/health'));
      _say('GET /api/health (no token) → ${noToken.statusCode}'
          '  [expect 401: token gate]');

      final withToken = await http.get(
        Uri.parse('$base/api/health'),
        headers: {_tokenHeader: _token!},
      );
      _say('GET /api/health (token) → ${withToken.statusCode}'
          '  body=${withToken.body}');
      _say(withToken.statusCode == 200
          ? 'P0 PASS — loopback HTTP reachable, token-gated.'
          : 'P0 FAIL — expected 200.');
    } catch (e, st) {
      _say('ERROR: $e');
      if (kDebugMode) _say(st.toString());
    }
  }

  Future<void> _stop() async {
    final p = _process;
    _process = null;
    if (p != null) {
      _say('stopping process (pid ${p.pid})');
      p.kill(ProcessSignal.sigterm);
      await p.exitCode.catchError((_) => -1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PB Spike (P0)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            icon: const Icon(Icons.power_settings_new),
            label: Text(_running ? 'Stop & re-run' : 'Re-run spike'),
            onPressed: () async {
              await _stop();
              if (!mounted) return;
              setState(_log.clear);
              await _run();
            },
          ),
          const SizedBox(height: 12),
          ..._log.map(
            (l) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: SelectableText(
                l,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
