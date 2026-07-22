import '../models/vault_settings.dart';
import 'vault_store.dart';

/// Settings load/save. Splits out of `VaultService`.
///
/// ponytail: tiny — just delegating the load/save to the store. Exists as a
/// separate service so Phase 4 Riverpod wiring has a clean injection point
/// and so callers don't depend on the whole VaultService for a single
/// getSettings call.
class SettingsService {
  final VaultStore _store;
  SettingsService(this._store);

  Future<VaultSettings> getSettings() => _store.loadSettings();

  Future<void> updateSettings(VaultSettings settings) async {
    _store.cachedSettings = settings;
    await _store.saveSettings();
  }
}