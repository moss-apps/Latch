import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sync_profile.dart';
import '../services/encryption_service.dart';
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

  const SyncState({
    this.status = SyncStatus.idle,
    this.lastSync,
    this.error,
    this.progress,
  });

  bool get isSyncing => status == SyncStatus.syncing;

  SyncState copyWith({
    SyncStatus? status,
    DateTime? lastSync,
    String? error,
    SyncProgress? progress,
  }) =>
      SyncState(
        status: status ?? this.status,
        lastSync: lastSync ?? this.lastSync,
        error: error,
        progress: progress ?? this.progress,
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
      final result = await service.syncNow(
        profile: profile,
        password: password,
        deviceId: deviceId,
        onProgress: (p) => state = state.copyWith(
          status: SyncStatus.syncing,
          progress: p,
        ),
      );

      // Persist refreshed remoteHash/modifiedAt so the next run dedups.
      final vault = ref.read(vaultServiceProvider);
      vault.store.cachedFiles = result.refreshedLocal;
      await vault.store.saveFileIndex();
      await SyncProfileService.instance
          .saveProfile(profile.copyWith(lastSyncedAt: result.completedAt));

      state = SyncState(
        status: SyncStatus.success,
        lastSync: result.completedAt,
      );
    } catch (e) {
      state = SyncState(status: SyncStatus.error, error: e.toString());
    }
  }

  void clearError() {
    state = const SyncState();
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
