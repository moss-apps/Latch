import '../models/vault_settings.dart';
import 'vault_store.dart';

/// Settings load/save. Splits out of `VaultService`.
///
/// tiny — just store delegation; exists as a clean injection point.
class SettingsService {
  final VaultStore _store;
  SettingsService(this._store);

  Future<VaultSettings> getSettings() => _store.loadSettings();

  Future<void> updateSettings(VaultSettings settings) async {
    _store.cachedSettings = settings;
    await _store.saveSettings();
  }
}