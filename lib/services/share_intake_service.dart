import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/shared_file_ref.dart';

/// Tracks files shared into Latch from other apps.
///
/// Lives outside the provider scope so pending references survive the subtree
/// recreation that happens on every lock. Only URI references and metadata are
/// kept here; plaintext staging copies live under the app cache directory and
/// are purged whenever the session locks or the process restarts.
class ShareIntakeService extends ChangeNotifier {
  ShareIntakeService._();

  static final ShareIntakeService instance = ShareIntakeService._();

  static const MethodChannel _channel =
      MethodChannel('com.mossapps.locker/share_intake');
  static const String _stagingFolder = 'share_staging';

  final List<SharedFileRef> _pending = [];
  String? _deferredSignature;
  Future<List<StagedShareFile>>? _inFlight;
  bool _initialized = false;

  List<SharedFileRef> get pending => List.unmodifiable(_pending);

  bool get hasPending => _pending.isNotEmpty;

  /// Stable identity of the current batch; used to avoid re-opening the review
  /// screen after the user has explicitly deferred it.
  String get signature => _pending.map((item) => item.id).join(',');

  String? get deferredSignature => _deferredSignature;

  bool get isDeferred =>
      _deferredSignature != null && _deferredSignature == signature;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler(_handleNativeCall);

    await purgeStaging();
    try {
      final response = await _channel.invokeMethod<Object?>('getPendingShare');
      _mergePayload(response);
    } on MissingPluginException {
      // Non-Android platform; share intake stays empty.
    } catch (error) {
      debugPrint('[ShareIntake] Failed to load pending share: $error');
    }
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onShareReceived') {
      _mergePayload(call.arguments);
    }
    return null;
  }

  void _mergePayload(Object? payload) {
    if (payload is! Map) return;
    final rawItems = payload['items'];
    if (rawItems is! List) return;

    var changed = false;
    for (final raw in rawItems) {
      final ref = SharedFileRef.fromMap(raw);
      if (ref == null) continue;
      if (_pending.any((item) => item.id == ref.id)) continue;
      _pending.add(ref);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Copies the pending share references into [destinationDir] using the
  /// native content resolver. Returns one result per pending item, including
  /// per-item failures.
  Future<List<StagedShareFile>> stage({required String destinationDir}) {
    final refs = List<SharedFileRef>.of(_pending);
    if (refs.isEmpty) return Future.value(const []);

    final operation = _stageInternal(refs, destinationDir);
    _inFlight = operation;
    return operation.whenComplete(() {
      if (identical(_inFlight, operation)) _inFlight = null;
    });
  }

  Future<List<StagedShareFile>> _stageInternal(
    List<SharedFileRef> refs,
    String destinationDir,
  ) async {
    try {
      final response = await _channel.invokeMethod<Object?>('stageShare', {
        'destinationDir': destinationDir,
        'items': [
          for (final ref in refs)
            {'id': ref.id, 'uri': ref.uri, 'name': ref.name},
        ],
      });

      final staged = <String, StagedShareFile>{};
      if (response is Map && response['staged'] is List) {
        for (final raw in response['staged'] as List) {
          final id = raw is Map ? raw['id'] : null;
          if (id is! String) continue;
          final ref = refs.where((item) => item.id == id).firstOrNull;
          if (ref == null) continue;
          final parsed = StagedShareFile.fromMap(raw, ref);
          if (parsed != null) staged[id] = parsed;
        }
      }

      return [
        for (final ref in refs)
          staged[ref.id] ?? StagedShareFile.failure(ref, 'File could not be read'),
      ];
    } on MissingPluginException {
      return [for (final ref in refs) StagedShareFile.failure(ref, 'Sharing is unavailable on this platform')];
    } catch (error) {
      debugPrint('[ShareIntake] Staging failed: $error');
      return [for (final ref in refs) StagedShareFile.failure(ref, 'Failed to stage shared file')];
    }
  }

  /// Drops the given references after their outcome has been reported.
  Future<void> consume(Iterable<String> ids) async {
    final idList = ids.toList();
    if (idList.isEmpty) return;
    _pending.removeWhere((item) => idList.contains(item.id));
    if (isDeferred) _deferredSignature = signature;
    notifyListeners();
    try {
      await _channel.invokeMethod<Object?>('consumeShare', {'ids': idList});
    } catch (error) {
      debugPrint('[ShareIntake] Failed to consume share ids: $error');
    }
  }

  /// Drops every pending reference. Used when the user explicitly discards.
  Future<void> clearAll() async {
    if (_pending.isEmpty && _deferredSignature == null) return;
    _pending.clear();
    _deferredSignature = null;
    notifyListeners();
    try {
      await _channel.invokeMethod<Object?>('clearShare');
    } catch (error) {
      debugPrint('[ShareIntake] Failed to clear share queue: $error');
    }
  }

  /// Marks the current batch as deferred so the review screen does not
  /// immediately reopen after the user backs out.
  void deferCurrent() {
    if (_pending.isEmpty) return;
    _deferredSignature = signature;
    notifyListeners();
  }

  Future<void> onSessionLocked() async {
    _deferredSignature = null;
    await purgeStaging();
  }

  /// Clears singleton state between tests.
  @visibleForTesting
  Future<void> resetForTesting() async {
    _pending.clear();
    _deferredSignature = null;
    _inFlight = null;
    _initialized = false;
    await purgeStaging();
  }

  /// Removes every staged copy. Deletes first so a locked session drops
  /// plaintext immediately even if a native copy is still running, then waits
  /// for the in-flight staging to finish and deletes anything it recreated.
  Future<void> purgeStaging() async {
    await _deleteStagingRoot();
    final inFlight = _inFlight;
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {}
      await _deleteStagingRoot();
    }
  }

  Future<void> _deleteStagingRoot() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final root = Directory('${tempDir.path}/$_stagingFolder');
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    } catch (error) {
      debugPrint('[ShareIntake] Failed to purge staging: $error');
    }
  }

  /// Prepares a per-session staging directory under the app cache.
  Future<Directory> prepareStagingDirectory(int generation) async {
    final tempDir = await getTemporaryDirectory();
    final dir = Directory('${tempDir.path}/$_stagingFolder/$generation');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
