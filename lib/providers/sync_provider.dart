import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sync_conflict.dart';
import '../models/sync_profile.dart';
import '../services/diagnostics.dart';
import '../services/encryption_service.dart';
import '../services/remote/server_errors.dart';
import '../services/sensitive_isolate.dart';
import '../services/sync_control.dart';
import '../services/sync_profile_service.dart';
import '../services/sync_service.dart';
import 'vault_providers.dart';

enum SyncStatus {
  idle,
  syncing,
  cancelling,
  cancelled,
  success,
  needsReview,
  error
}

class SyncState {
  final SyncStatus status;
  final DateTime? lastSync;
  final String? error;
  final String? diagnosticId;
  final SyncProgress? progress;
  final String? message;
  final Duration? duration;
  final List<SyncConflict> conflicts;

  const SyncState(
      {this.status = SyncStatus.idle,
      this.lastSync,
      this.error,
      this.diagnosticId,
      this.progress,
      this.message,
      this.duration,
      this.conflicts = const []});

  bool get isSyncing =>
      status == SyncStatus.syncing || status == SyncStatus.cancelling;
}

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
      ref.read(vaultServiceProvider).store, EncryptionService.instance);
});

class SyncNotifier extends Notifier<SyncState> {
  bool _busy = false;
  bool _alive = true;
  SyncControl? _control;

  @override
  SyncState build() {
    ref.onDispose(() {
      _alive = false;
      _control?.cancel();
    });
    return const SyncState();
  }

  bool _current(int generation) =>
      _alive && EncryptionService.instance.isCurrentSession(generation);

  Future<void> loadPending() async {
    if (_busy) return;
    final generation = EncryptionService.instance.cacheGeneration;
    try {
      final settings = await ref.read(vaultServiceProvider).getSettings();
      if (!_current(generation)) return;
      final id = settings.syncProfileId;
      if (id == null) return;
      final profile = await SyncProfileService.instance.getProfile(id);
      if (profile == null || !_current(generation)) return;
      final conflicts =
          await ref.read(syncServiceProvider).pendingConflicts(profile);
      if (!_current(generation) || _busy) return;
      state = SyncState(
          status: conflicts.isEmpty ? SyncStatus.idle : SyncStatus.needsReview,
          conflicts: conflicts);
    } catch (e, st) {
      final id = Diagnostics.failure('sync.loadState', e, st);
      if (_current(generation) && !_busy) {
        state = SyncState(
            status: SyncStatus.error,
            error: describeServerError(e),
            diagnosticId: id);
      }
    }
  }

  Future<void> choose(String id, ConflictChoice choice) async {
    if (_busy) return;
    _busy = true;
    final generation = EncryptionService.instance.cacheGeneration;
    final previous = state;
    state = SyncState(
        status: SyncStatus.syncing,
        progress: const SyncProgress(phase: SyncPhase.committing),
        conflicts: previous.conflicts);
    try {
      final settings = await ref.read(vaultServiceProvider).getSettings();
      if (!_current(generation)) return;
      final profileId = settings.syncProfileId;
      if (profileId == null) return;
      final profile = await SyncProfileService.instance.getProfile(profileId);
      if (profile == null || !_current(generation)) return;
      await ref.read(syncServiceProvider).chooseConflict(profile, id, choice);
    } catch (e, st) {
      final errorId = Diagnostics.failure('sync.resolve', e, st);
      if (_current(generation)) {
        state = SyncState(
            status: SyncStatus.error,
            error: describeServerError(e),
            diagnosticId: errorId,
            conflicts: state.conflicts);
      }
      return;
    } finally {
      _busy = false;
      if (_current(generation) && state.isSyncing) state = previous;
    }
    if (_current(generation)) await syncNow();
  }

  void cancel() {
    if (!_busy || _control?.committing == true) return;
    _control?.cancel();
    state = SyncState(
        status: SyncStatus.cancelling,
        progress: state.progress,
        conflicts: state.conflicts);
  }

  Future<void> syncNow() async {
    if (_busy) return;
    _busy = true;
    final control = _control = SyncControl();
    final generation = EncryptionService.instance.cacheGeneration;
    final stopwatch = Stopwatch()..start();
    state = SyncState(
        status: SyncStatus.syncing,
        progress: const SyncProgress(phase: SyncPhase.connecting),
        conflicts: state.conflicts);
    Diagnostics.event(
        'sync.start', {'run': DateTime.now().millisecondsSinceEpoch});
    try {
      final settings = await ref.read(vaultServiceProvider).getSettings();
      if (!_current(generation)) return;
      control.check();
      final profileId = settings.syncProfileId;
      if (profileId == null || !settings.syncEnabled) {
        state = const SyncState(
            status: SyncStatus.error,
            error: 'Add a server and enable sync to get started.');
        return;
      }
      final profile = await SyncProfileService.instance.getProfile(profileId);
      if (!_current(generation)) return;
      if (profile == null) {
        state = const SyncState(
            status: SyncStatus.error,
            error: 'Choose a server in your sync settings.');
        return;
      }
      if (profile.wifiOnly) {
        final connections = await Connectivity().checkConnectivity();
        if (!_current(generation)) return;
        if (!connections.contains(ConnectivityResult.wifi)) {
          state = const SyncState(
              status: SyncStatus.error,
              error: 'Connect to Wi-Fi, then try syncing again.');
          return;
        }
      }
      final password =
          await SyncProfileService.instance.getPassword(profile.id) ?? '';
      final deviceId = await SyncProfileService.instance.getDeviceId();
      if (!_current(generation)) return;
      control.check();
      final service = ref.read(syncServiceProvider);
      SyncPhase? phase;
      final throttle = Stopwatch()..start();
      final result = await service.syncNow(
          profile: profile,
          password: password,
          deviceId: deviceId,
          control: control,
          onProgress: (progress) {
            if (!_current(generation)) return;
            if (phase != progress.phase) {
              Diagnostics.event('sync.phase', {'phase': progress.phase.name});
            } else if (throttle.elapsedMilliseconds < 100) {
              return;
            }
            phase = progress.phase;
            throttle.reset();
            state = SyncState(
                status: control.cancelled
                    ? SyncStatus.cancelling
                    : SyncStatus.syncing,
                progress: progress,
                conflicts: state.conflicts);
          });
      if (!_current(generation)) return;
      await service.complete(profile, result, generation);
      if (!_current(generation)) return;
      await SyncProfileService.instance
          .saveProfile(profile.copyWith(lastSyncedAt: result.completedAt));
      if (!_current(generation)) return;
      ref.invalidate(vaultNotifierProvider);
      ref.invalidate(filteredFilesProvider);
      ref.invalidate(fileByIdProvider);
      ref.invalidate(totalStorageProvider);
      ref.invalidate(syncProfilesProvider);
      state = SyncState(
          status: result.checkpoint.conflicts.isEmpty
              ? SyncStatus.success
              : SyncStatus.needsReview,
          lastSync: result.completedAt,
          message: _summarize(result),
          duration: stopwatch.elapsed,
          conflicts: result.checkpoint.conflicts);
      Diagnostics.event('sync.finished', {
        'milliseconds': stopwatch.elapsedMilliseconds,
        'conflicts': result.checkpoint.conflicts.length
      });
    } catch (e, st) {
      if (e is SyncCancelled) {
        Diagnostics.event('sync.cancelled', {});
        if (_current(generation)) {
          state = SyncState(
              status: SyncStatus.cancelled,
              message: 'Sync stopped. You can safely try again.',
              conflicts: state.conflicts);
        }
      } else {
        final id = e is SyncWorkerFailure
            ? e.diagnosticId
            : Diagnostics.failure('sync.failed', e, st);
        if (_current(generation)) {
          state = SyncState(
              status: SyncStatus.error,
              error:
                  e is SyncWorkerFailure ? e.message : describeServerError(e),
              diagnosticId: id,
              conflicts: state.conflicts);
        }
      }
    } finally {
      _control = null;
      _busy = false;
    }
  }

  void clearError() => state = SyncState(conflicts: state.conflicts);

  static String _summarize(SyncResult result) {
    final parts = <String>[
      if (result.blobsPushed > 0) '${result.blobsPushed} uploaded',
      if (result.blobsReused > 0) '${result.blobsReused} already backed up',
      if (result.blobsPulled > 0) '${result.blobsPulled} downloaded',
      if (result.filesDeleted > 0) '${result.filesDeleted} deletions saved',
      if (result.blobsSkipped > 0)
        '${result.blobsSkipped} unavailable on this device',
      if (result.plan.conflicts.isNotEmpty)
        '${result.plan.conflicts.length} need review',
    ];
    return parts.isEmpty ? 'Up to date' : parts.join(' · ');
  }
}

final syncProvider =
    NotifierProvider<SyncNotifier, SyncState>(SyncNotifier.new);
final syncProfilesProvider = FutureProvider<List<SyncProfile>>((ref) async {
  try {
    return await SyncProfileService.instance.listProfiles();
  } catch (e, st) {
    final id = Diagnostics.failure('sync.profiles', e, st);
    throw SyncWorkerFailure(
        'Your server settings couldn’t be loaded. Try again.', id);
  }
});
