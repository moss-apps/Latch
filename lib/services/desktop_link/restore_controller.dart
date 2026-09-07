import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/foundation.dart';

import '../../models/remote_manifest.dart';
import '../../models/vaulted_file.dart';
import '../encryption_service.dart';
import '../sync_service.dart';
import '../vault_store.dart';
import 'transfer_client.dart'
    show DesktopUnreachableException, PushRejectedException, PushRejected;

/// What a restore-authorized latchd session is currently serving (GET /info).
class RestoreSourceInfo {
  RestoreSourceInfo({
    required this.host,
    required this.mode,
    required this.hasManifest,
    required this.hasKeybundle,
    required this.blobCount,
  });

  final String host;
  final String mode;
  final bool hasManifest;
  final bool hasKeybundle;
  final int blobCount;

  bool get isRestoreSession => mode == 'restore';
}

class RestoreProgress {
  const RestoreProgress(this.restored, this.total, this.bytes);

  final int restored;
  final int total;
  final int bytes;
}

class DesktopRestoreReport {
  const DesktopRestoreReport({
    required this.restored,
    required this.skipped,
    required this.bytes,
    required this.fileCount,
  });

  /// Entries pulled + written to the vault.
  final int restored;

  /// Entries whose blob was absent from the snapshot — left untouched.
  final int skipped;

  final int bytes;

  /// Live entries the snapshot contains.
  final int fileCount;
}

/// Result of importing a snapshot: the refreshed file index + stats.
class RestoreImportResult {
  const RestoreImportResult(this.files, this.report);

  final List<VaultedFile> files;
  final DesktopRestoreReport report;
}

/// Thrown from [RestoreController] work when [isCancelled] turned true.
class RestoreCancelledException implements Exception {
  const RestoreCancelledException();
}

/// Internal cancellation marker used inside the import loop.
class RestoreCancelled implements Exception {
  const RestoreCancelled();
}

/// Pulls a snapshot out of a restore-authorized latchd session (the GET set:
/// `/manifest`, `/blob/<sha>`, `/keybundle`). Transport-level failures map to
/// the same exception family as [DesktopPushClient].
class DesktopRestoreClient {
  DesktopRestoreClient({HttpClient? http}) : _http = http ?? HttpClient();

  final HttpClient _http;

  /// Asks the receiver for its state without pulling anything. Throws
  /// [PushRejectedException] or [DesktopUnreachableException].
  Future<RestoreSourceInfo> check({
    required Uri base,
    required String token,
  }) async {
    try {
      final info =
          (await _getJson(base, '/info', token, orNull404: false))!;
      return RestoreSourceInfo(
        host: (info['host'] as String?) ?? '',
        mode: (info['mode'] as String?) ?? 'push',
        hasManifest: info['hasManifest'] == true,
        hasKeybundle: info['hasKeybundle'] == true,
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

  /// The wrapped-key bundle, or null when the backup carries none.
  Future<Map<String, dynamic>?> fetchKeybundle({
    required Uri base,
    required String token,
  }) async {
    try {
      final body = await _getJson(base, '/keybundle', token, orNull404: true);
      return body;
    } on PushRejected {
      throw PushRejectedException();
    } on SocketException catch (e) {
      throw DesktopUnreachableException(e);
    } on HttpException catch (e) {
      throw DesktopUnreachableException(e);
    }
  }

  /// The encrypted manifest. A backup without a manifest is fatal — there is
  /// nothing to restore.
  Future<Uint8List> fetchManifest({
    required Uri base,
    required String token,
  }) async {
    try {
      final bytes = await _getBytes(base, '/manifest', token, orNull404: false);
      return bytes!;
    } on PushRejected {
      throw PushRejectedException();
    } on SocketException catch (e) {
      throw DesktopUnreachableException(e);
    } on HttpException catch (e) {
      throw DesktopUnreachableException(e);
    }
  }

  /// The sha256 hex of a blob names its path in the GET set
  /// (`/blob/<sha>`), so [sha] must be a 64-character hex string.
  Future<Uint8List?> fetchBlob({
    required Uri base,
    required String token,
    required String sha,
  }) async {
    try {
      return await _getBytes(base, '/blob/$sha', token, orNull404: true);
    } on PushRejected {
      throw PushRejectedException();
    } on SocketException catch (e) {
      throw DesktopUnreachableException(e);
    } on HttpException catch (e) {
      throw DesktopUnreachableException(e);
    }
  }

  Future<Map<String, dynamic>?> _getJson(
    Uri base,
    String path,
    String token, {
    required bool orNull404,
  }) async {
    final res = await _run(base.resolve(path), token);
    if (res.statusCode == HttpStatus.unauthorized) {
      await res.drain<void>();
      throw const PushRejected();
    }
    if (orNull404 && res.statusCode == HttpStatus.notFound) {
      await res.drain<void>();
      return null;
    }
    if (res.statusCode != HttpStatus.ok) {
      await res.drain<void>();
      throw HttpException('GET $path -> ${res.statusCode}');
    }
    final body = await res.transform(utf8.decoder).join();
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } on FormatException {
      throw HttpException('receiver sent a malformed $path body');
    }
  }

  Future<Uint8List?> _getBytes(
    Uri base,
    String path,
    String token, {
    required bool orNull404,
  }) async {
    final res = await _run(base.resolve(path), token);
    if (res.statusCode == HttpStatus.unauthorized) {
      await res.drain<void>();
      throw const PushRejected();
    }
    if (orNull404 && res.statusCode == HttpStatus.notFound) {
      await res.drain<void>();
      return null;
    }
    if (res.statusCode != HttpStatus.ok) {
      await res.drain<void>();
      throw HttpException('GET $path -> ${res.statusCode}');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in res) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<HttpClientResponse> _run(Uri uri, String token) async {
    final req = await _http.openUrl('GET', uri);
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    return req.close();
  }

  void close() {
    _http.close();
  }
}

/// Orchestrates phone-side restores (P6.3). Both modes pull the manifest +
/// blobs through the same import path as the WebDAV pull phase
/// ([SyncService.runSync]): per-blob sha256 verification, then wholesale
/// replacement of what the snapshot contains. Entries whose blob is absent
/// from the snapshot are left untouched.
class RestoreController {
  RestoreController(this._store, this._crypto);

  final VaultStore _store;
  final EncryptionService _crypto;

  /// Mode 1 — restore into an existing unlocked vault. The existing master
  /// key is kept; the desktop keybundle is IGNORED (the snapshot's manifest
  /// must decrypt under the local key).
  Future<DesktopRestoreReport> restoreIntoVault({
    required DesktopRestoreClient client,
    required Uri base,
    required String token,
    void Function(RestoreProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final masterKey = await _crypto.getMasterKey();
    return _pull(
      client: client,
      base: base,
      token: token,
      masterKey: masterKey,
      existing: await _store.loadFileIndex(),
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }

  /// Mode 2 — restore-before-setup (fresh install, no vault). Installs the
  /// received keybundle after verifying [originalPassword] (unwrap success
  /// is the proof), then imports the manifest under that key. Setup resumes
  /// around this via [RestoreSetupScreen].
  Future<DesktopRestoreReport> restoreFresh({
    required DesktopRestoreClient client,
    required Uri base,
    required String token,
    required Map<String, dynamic> keybundle,
    required String originalPassword,
    void Function(RestoreProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final masterKey =
        await _crypto.installRestoredKeybundle(keybundle, originalPassword);
    return _pull(
      client: client,
      base: base,
      token: token,
      masterKey: masterKey,
      existing: const [],
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }

  Future<DesktopRestoreReport> _pull({
    required DesktopRestoreClient client,
    required Uri base,
    required String token,
    required Uint8List masterKey,
    required List<VaultedFile> existing,
    void Function(RestoreProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final dir = await _store.ensureVaultDirectory();
    final manifestBytes = await client.fetchManifest(base: base, token: token);
    final manifest = SyncService.decryptManifest(manifestBytes, masterKey);
    try {
      final result = await importSnapshot(
        manifest: manifest,
        fetchBlob: (sha) => client.fetchBlob(base: base, token: token, sha: sha),
        vaultRoot: dir.path,
        existingFiles: existing,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
      _store.cachedFiles = result.files;
      await _store.saveFileIndex();
      return result.report;
    } on RestoreCancelled {
      throw const RestoreCancelledException();
    }
  }

  /// Pure import: pull every live entry's blob, verify its sha256, write it
  /// into the vault, and rebuild the file index. Mirrors the runSync pull
  /// semantics: replace-by-id (old ciphertext removed only when the path
  /// changed), append when new, skip when the blob is absent. Throws
  /// [RestoreCancelled] via cancellation and [StateError] on hash mismatch.
  static Future<RestoreImportResult> importSnapshot({
    required RemoteManifest manifest,
    required Future<Uint8List?> Function(String shaHex) fetchBlob,
    required String vaultRoot,
    required List<VaultedFile> existingFiles,
    void Function(RestoreProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final live = manifest.entries
        .where((e) => !e.deleted && e.contentHash != null)
        .toList();
    final refreshed = List<VaultedFile>.from(existingFiles);
    var restored = 0;
    var skipped = 0;
    var bytes = 0;

    for (final e in live) {
      if (isCancelled?.call() ?? false) throw const RestoreCancelled();
      final hash = e.contentHash!;
      final blob = await fetchBlob(hash);
      if (blob == null) {
        skipped++;
        continue;
      }
      final actual = SyncService.sha256Hex(blob);
      if (actual != hash) {
        throw StateError('Blob hash mismatch for ${e.originalName ?? e.id}');
      }
      final vp = SyncService.vaultPathFor(vaultRoot: vaultRoot, entry: e);
      await File(vp).parent.create(recursive: true);
      await File(vp).writeAsBytes(blob);
      bytes += blob.length;
      restored++;
      final idx = refreshed.indexWhere((f) => f.id == e.id);
      if (idx >= 0) {
        final old = refreshed[idx];
        if (old.vaultPath != vp) {
          final oldFile = File(old.vaultPath);
          if (await oldFile.exists()) await oldFile.delete();
        }
        refreshed[idx] = SyncService.vaultedFileFromEntry(e, vaultPath: vp);
      } else {
        refreshed.add(SyncService.vaultedFileFromEntry(e, vaultPath: vp));
      }
      onProgress?.call(RestoreProgress(restored, live.length, bytes));
    }

    return RestoreImportResult(
      refreshed,
      DesktopRestoreReport(
        restored: restored,
        skipped: skipped,
        bytes: bytes,
        fileCount: live.length,
      ),
    );
  }
}
