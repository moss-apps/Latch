import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../../models/vaulted_file.dart';
import '../encryption_service.dart';
import '../sync_profile_service.dart';
import '../sync_service.dart';

/// Immutable snapshot of the encrypted vault, ready to push to a latchd
/// pairing receiver. Blob bytes are the on-disk encrypted vault files,
/// keyed by their sha256 hex digest — the same semantics as the sync push
/// phase ([SyncService]) — so manifest content hashes always match the
/// pushed blobs. Files missing on disk keep their stored remoteHash and
/// are reported to the desktop as unavailable.
class DesktopVaultSnapshot {
  DesktopVaultSnapshot({
    required this.fileCount,
    required this.totalBytes,
    required this.manifestBytes,
    required this.blobs,
    required this.keybundle,
  });

  /// Live (non-deleted) files represented by the manifest.
  final int fileCount;

  /// Total ciphertext size of [blobs].
  final int totalBytes;

  /// Encrypted manifest bytes (RemoteManifest v2, GCM envelope).
  final Uint8List manifestBytes;

  /// sha256 hex digest -> encrypted file bytes.
  final Map<String, Uint8List> blobs;

  /// Wrapped-key bundle for the desktop, or null for legacy unwrapped
  /// vaults (which cannot be backed up until migrated).
  final Map<String, dynamic>? keybundle;

  bool get keyWrapped => keybundle != null;

  static Future<DesktopVaultSnapshot> fromLiveVault({
    required List<VaultedFile> files,
    required EncryptionService crypto,
    required String deviceId,
  }) async {
    final masterKey = await crypto.getMasterKey();
    final keybundle = await crypto.exportKeybundle();

    // Reading and hashing every vault file would freeze the UI isolate on
    // real vaults, so the heavy pass runs on a worker isolate. Deleted
    // entries and files missing on disk keep their stored remoteHash and
    // are reported to the desktop as unavailable.
    final entries = [
      for (final f in files) (path: f.vaultPath, deleted: f.syncedDeleted),
    ];
    final result = await Isolate.run(() {
      var totalBytes = 0;
      final blobs = <String, Uint8List>{};
      final hashes = List<String?>.filled(entries.length, null);
      for (var i = 0; i < entries.length; i++) {
        final e = entries[i];
        if (e.deleted) continue;
        Uint8List? bytes;
        try {
          final onDisk = File(e.path);
          if (onDisk.existsSync()) bytes = onDisk.readAsBytesSync();
        } catch (_) {
          bytes = null;
        }
        if (bytes == null) continue;
        final hash = SyncService.sha256Hex(bytes);
        blobs[hash] = bytes;
        totalBytes += bytes.length;
        hashes[i] = hash;
      }
      return (blobs: blobs, hashes: hashes, totalBytes: totalBytes);
    });

    final adjusted = <VaultedFile>[
      for (var i = 0; i < files.length; i++)
        (result.hashes[i] != null && files[i].remoteHash != result.hashes[i])
            ? files[i].copyWith(remoteHash: result.hashes[i])
            : files[i],
    ];

    final manifest = SyncService.buildManifest(
      adjusted,
      deviceId: deviceId,
      now: DateTime.now().toUtc(),
    );
    final manifestBytes = SyncService.encryptManifest(manifest, masterKey);
    final liveCount = adjusted.where((f) => !f.syncedDeleted).length;

    return DesktopVaultSnapshot(
      fileCount: liveCount,
      totalBytes: result.totalBytes,
      manifestBytes: manifestBytes,
      blobs: result.blobs,
      keybundle: keybundle,
    );
  }
}

/// Progress of an in-flight push: [sent] of [total] blobs, [bytes] total.
class DesktopPushProgress {
  const DesktopPushProgress(this.sent, this.total, this.bytes);
  final int sent;
  final int total;
  final int bytes;
}

/// What the receiver reports about the backup already on the computer.
class ReceiverInfo {
  const ReceiverInfo({
    required this.host,
    required this.hasManifest,
    required this.blobCount,
  });
  final String host;
  final bool hasManifest;
  final int blobCount;
}

/// Result of a completed push.
class DesktopPushReport {
  const DesktopPushReport({
    required this.pushed,
    required this.alreadyPresent,
    required this.bytes,
  });
  final int pushed;
  final int alreadyPresent;
  final int bytes;
}

/// The user cancelled the push.
class PushCancelledException implements Exception {
  @override
  String toString() => 'push cancelled';
}

/// The receiver rejected the bearer token (expired or regenerated code).
class PushRejectedException implements Exception {
  @override
  String toString() => 'the computer rejected this pairing code';
}

/// The vault predates key wrapping and cannot be backed up.
class LegacyVaultException implements Exception {
  @override
  String toString() => 'vault key is not wrapped (legacy vault)';
}

/// Transport-level failure reaching the receiver.
class DesktopUnreachableException implements Exception {
  DesktopUnreachableException(this.cause);
  final Object cause;
  @override
  String toString() => 'desktop unreachable: $cause';
}

/// Pushes an encrypted vault snapshot to a latchd pairing receiver.
///
/// Protocol (desktop-backup spec, flipped architecture): the desktop hosts
/// a token-gated HTTP receiver while its pairing window is open. The phone
/// diffs against the receiver's existing blobs ([GET /info]), then uploads
/// the wrapped key, the missing blobs, and finally the manifest — the
/// manifest landing is the completion signal that triggers the desktop's
/// verify pass.
class DesktopPushClient {
  DesktopPushClient() {
    _http.connectionTimeout = const Duration(seconds: 5);
  }

  final _http = HttpClient();
  static final RegExp _tokenHex = RegExp(r'^[0-9a-f]{64}$');

  void close() => _http.close(force: true);

  /// Parse a pairing link of the form `http://<ip>:<port>/#<token>`.
  /// Returns the receiver base URI and the token, or null when malformed.
  static (Uri, String)? parsePairingUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.scheme != 'http') return null;
    if (uri.host.isEmpty || uri.port == 0) return null;
    final token = (uri.fragment.startsWith('#'))
        ? uri.fragment.substring(1)
        : uri.fragment;
    if (!_tokenHex.hasMatch(token)) return null;
    return (
      Uri(scheme: 'http', host: uri.host, port: uri.port),
      token,
    );
  }

  /// Asks the receiver for its state without sending anything. Throws
  /// [PushRejectedException] or [DesktopUnreachableException].
  Future<ReceiverInfo> check({required Uri base, required String token}) async {
    try {
      final info = await _getInfo(base, token);
      return ReceiverInfo(
        host: (info['host'] as String?) ?? '',
        hasManifest: info['hasManifest'] == true,
        blobCount: (info['hashes'] as List? ?? const []).length,
      );
    } on PushRejected {
      throw PushRejectedException();
    } on SocketException catch (e) {
      throw DesktopUnreachableException(e);
    } on HttpException catch (e) {
      throw DesktopUnreachableException(e);
    }
  }

  /// Runs the full push. Throws [PushRejectedException],
  /// [LegacyVaultException], [PushCancelledException] or
  /// [DesktopUnreachableException].
  Future<DesktopPushReport> push({
    required Uri base,
    required String token,
    required DesktopVaultSnapshot snapshot,
    void Function(DesktopPushProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!snapshot.keyWrapped) throw LegacyVaultException();
    try {
      final info = await _getInfo(base, token);
      final remoteHashes = (info['hashes'] as List? ?? const [])
          .whereType<String>()
          .toSet();
      final missing = snapshot.blobs.keys
          .where((sha) => !remoteHashes.contains(sha))
          .toList()
        ..sort();

      await _putJson(base, '/keybundle', token, snapshot.keybundle!);

      var sent = 0;
      var bytes = 0;
      for (final sha in missing) {
        if (isCancelled?.call() ?? false) throw const PushCancelled();
        final blob = snapshot.blobs[sha]!;
        await _putBytes(base, '/blob/$sha', token, blob);
        sent++;
        bytes += blob.length;
        onProgress?.call(
          DesktopPushProgress(sent, missing.length, bytes),
        );
      }

      await _putBytes(base, '/manifest', token, snapshot.manifestBytes);
      return DesktopPushReport(
        pushed: sent,
        alreadyPresent: snapshot.blobs.length - sent,
        bytes: bytes,
      );
    } on PushRejected {
      throw PushRejectedException();
    } on PushCancelled {
      throw PushCancelledException();
    } on SocketException catch (e) {
      throw DesktopUnreachableException(e);
    } on HttpException catch (e) {
      throw DesktopUnreachableException(e);
    }
  }

  Future<Map<String, dynamic>> _getInfo(Uri base, String token) async {
    final res = await _run('GET', base.resolve('/info'), token);
    if (res.statusCode == HttpStatus.unauthorized) {
      await res.drain<void>();
      throw const PushRejected();
    }
    if (res.statusCode != HttpStatus.ok) {
      await res.drain<void>();
      throw HttpException('GET /info -> ${res.statusCode}');
    }
    final body = await res.transform(utf8.decoder).join();
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } on FormatException {
      throw const HttpException('receiver sent a malformed /info body');
    }
  }

  Future<void> _putJson(
      Uri base, String path, String token, Map<String, dynamic> json) async {
    final res = await _run(
      'PUT',
      base.resolve(path),
      token,
      body: Uint8List.fromList(utf8.encode(jsonEncode(json))),
      contentType: ContentType.json,
    );
    await res.drain<void>();
    if (res.statusCode == HttpStatus.unauthorized) throw const PushRejected();
    if (res.statusCode != HttpStatus.ok) {
      throw HttpException('PUT $path -> ${res.statusCode}');
    }
  }

  Future<void> _putBytes(
      Uri base, String path, String token, Uint8List bytes) async {
    final res = await _run(
      'PUT',
      base.resolve(path),
      token,
      body: bytes,
      contentType: ContentType.binary,
    );
    await res.drain<void>();
    if (res.statusCode == HttpStatus.unauthorized) throw const PushRejected();
    if (res.statusCode != HttpStatus.ok) {
      throw HttpException('PUT $path -> ${res.statusCode}');
    }
  }

  Future<HttpClientResponse> _run(
    String method,
    Uri uri,
    String token, {
    Uint8List? body,
    ContentType? contentType,
  }) async {
    final HttpClientRequest req;
    switch (method) {
      case 'GET':
        req = await _http.openUrl('GET', uri);
      case 'PUT':
        req = await _http.openUrl('PUT', uri);
      default:
        throw ArgumentError('unsupported method $method');
    }
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    if (contentType != null) {
      req.headers.contentType = contentType;
    }
    if (body != null) {
      req.contentLength = body.length;
      req.add(body);
    }
    return req.close();
  }
}

/// Internal transport-level rejection marker, unwrapped into
/// [PushRejectedException] by [DesktopPushClient].
class PushRejected implements Exception {
  const PushRejected();
}

/// Internal transport-level cancellation marker, unwrapped into
/// [PushCancelledException] by [DesktopPushClient.push].
class PushCancelled implements Exception {
  const PushCancelled();
}

/// Convenience: resolve the device id for snapshot building.
Future<String> desktopLinkDeviceId() =>
    SyncProfileService.instance.getDeviceId();
