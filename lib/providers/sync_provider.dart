import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sync_profile.dart';
import '../services/encryption_service.dart';
import '../services/remote/server_errors.dart';
import '../services/sync_profile_service.dart';
import '../services/sync_service.dart';
import 'vault_providers.dart';

/// Sync UI status.
enum SyncStatus { idle, syncing, success, error }

/// Observable sync state surfaced to the settings screen.
class SyncState {
  final SyncStatus status;
  final DateTime? lastSync;
  final String? error;
  final SyncProgress? progress;
  /// Human summary of the last completed run (e.g. "2 pushed · 1 pulled"),
  /// including a conflict count if both sides changed. Cleared on the next run.
  final String? message;

  /// Wall-clock time the last successful run took.
  final Duration? duration;

  const SyncState({
    this.status = SyncStatus.idle,
    this.lastSync,
    this.error,
    this.progress,
    this.message,
    this.duration,
  });

  bool get isSyncing => status == SyncStatus.syncing;

  SyncState copyWith({
    SyncStatus? status,
    DateTime? lastSync,
    String? error,
    SyncProgress? progress,
    String? message,
    Duration? duration,
  }) =>
      SyncState(
        status: status ?? this.status,
        lastSync: lastSync ?? this.lastSync,
        error: error,
        progress: progress ?? this.progress,
        message: message ?? this.message,
        duration: duration ?? this.duration,
      );
}

/// Riverpod-constructed [SyncService] — NOT a singleton (locked decision #5).
/// Shares [VaultStore]/[EncryptionService] state with the rest of the app.
final syncServiceProvider = Provider<SyncService>((ref) {
  final vault = ref.read(vaultServiceProvider);
  return SyncService(vault.store, EncryptionService.instance);
});

/// Drives sync + exposes status. The connectivity guard (locked decision #4,
/// reusing connectivity_plus) lives here so [SyncService.runSync] stays pure.
class SyncNotifier extends Notifier<SyncState> {
  @override
  SyncState build() => const SyncState();

  Future<void> syncNow() async {
    final settings = await ref.read(vaultServiceProvider).getSettings();
    final profileId = settings.syncProfileId;
    if (profileId == null || !settings.syncEnabled) {
      state = const SyncState(
        status: SyncStatus.error,
        error: 'Sync is not configured. Add a server profile first.',
      );
      return;
    }

    final profile = await SyncProfileService.instance.getProfile(profileId);
    if (profile == null) {
      state = const SyncState(
        status: SyncStatus.error,
        error: 'Sync profile not found.',
      );
      return;
    }

    if (profile.wifiOnly) {
      final results = await Connectivity().checkConnectivity();
      final onWifi = results.any((r) => r == ConnectivityResult.wifi);
      if (!onWifi) {
        state = const SyncState(
          status: SyncStatus.error,
          error: 'Waiting for Wi-Fi.',
        );
        return;
      }
    }

    final password =
        await SyncProfileService.instance.getPassword(profile.id) ?? '';
    final deviceId = await SyncProfileService.instance.getDeviceId();

    state = SyncState(
      status: SyncStatus.syncing,
      progress: const SyncProgress(),
    );

    try {
      final service = ref.read(syncServiceProvider);
      final sw = Stopwatch()..start();
      final result = await service.syncNow(
        profile: profile,
        password: password,
        deviceId: deviceId,
      );
      sw.stop();

      // Persist refreshed remoteHash/modifiedAt so the next run dedups.
      final vault = ref.read(vaultServiceProvider);
      vault.store.cachedFiles = result.refreshedLocal;
      await vault.store.saveFileIndex();
      await SyncProfileService.instance
          .saveProfile(profile.copyWith(lastSyncedAt: result.completedAt));

      state = SyncState(
        status: SyncStatus.success,
        lastSync: result.completedAt,
        message: _summarize(result),
        duration: sw.elapsed,
      );
    } catch (e) {
      state = SyncState(status: SyncStatus.error, error: describeServerError(e));
    }
  }

  void clearError() {
    state = const SyncState();
  }

  /// One-line summary of a completed run for the status card. Conflicts are
  /// surfaced here (S3.2) since LWW still resolves them silently.
  static String _summarize(SyncResult r) {
    final parts = <String>[];
    if (r.blobsPushed > 0) parts.add('${r.blobsPushed} pushed');
    if (r.blobsPulled > 0) parts.add('${r.blobsPulled} pulled');
    if (r.blobsDeleted > 0) parts.add('${r.blobsDeleted} reaped');
    if (r.blobsSkipped > 0) parts.add('${r.blobsSkipped} skipped');
    if (r.plan.conflicts.isNotEmpty) {
      parts.add('${r.plan.conflicts.length} conflict'
          '${r.plan.conflicts.length == 1 ? '' : 's'}');
    }
    return parts.isEmpty ? 'Up to date' : parts.join(' · ');
  }
}

final syncProvider =
    NotifierProvider<SyncNotifier, SyncState>(SyncNotifier.new);

/// All stored sync profiles (for the settings screen list). Refreshed by
/// invalidating after a save/delete.
final syncProfilesProvider =
    FutureProvider<List<SyncProfile>>((ref) async {
  return SyncProfileService.instance.listProfiles();
});
