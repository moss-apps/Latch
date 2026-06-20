import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../models/password_entry.dart';
import '../models/encryption_algorithm.dart';
import '../services/password_service.dart';
import 'vault_providers.dart';

final passwordServiceProvider = Provider<PasswordService>((ref) {
  return PasswordService.instance;
});

final passwordSearchQueryProvider = StateProvider<String>((ref) => '');

final selectedPasswordTagProvider = StateProvider<String?>((ref) => null);

class PasswordsNotifier extends Notifier<AsyncValue<List<PasswordEntry>>> {
  @override
  AsyncValue<List<PasswordEntry>> build() {
    loadPasswords();
    return const AsyncValue.loading();
  }

  PasswordService get _service => ref.read(passwordServiceProvider);

  bool get _isDecoy => ref.read(isDecoyModeProvider);

  Future<void> loadPasswords() async {
    state = const AsyncValue.loading();
    try {
      _service.clearCache();
      final entries = await _service.loadPasswords(isDecoy: _isDecoy);
      state = AsyncValue.data(entries);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<PasswordEntry> createPassword({
    required String title,
    required PasswordContent content,
    List<String> tags = const [],
    EncryptionAlgorithm encryptionAlgorithm = EncryptionAlgorithm.aes256Gcm,
    int kdfIterations = 100000,
    void Function(String status, {bool isEncrypting})? onProgress,
  }) async {
    final entry = await _service.createPassword(
      title: title,
      content: content,
      tags: tags,
      encryptionAlgorithm: encryptionAlgorithm,
      kdfIterations: kdfIterations,
      isDecoy: _isDecoy,
      onProgress: onProgress,
    );
    await loadPasswords();
    _refreshVault();
    return entry;
  }

  Future<PasswordEntry> updatePassword(
    PasswordEntry entry, {
    String? title,
    PasswordContent? content,
    List<String>? tags,
  }) async {
    final updated = await _service.updatePassword(
      entry,
      title: title,
      content: content,
      tags: tags,
      encryptionAlgorithm: entry.encryptionAlgorithm,
      kdfIterations: entry.kdfIterations,
      isDecoy: _isDecoy,
    );
    await loadPasswords();
    _refreshVault();
    return updated;
  }

  Future<void> deletePassword(PasswordEntry entry) async {
    await _service.deletePassword(entry, isDecoy: _isDecoy);
    await loadPasswords();
    _refreshVault();
  }

  Future<void> deletePasswords(List<PasswordEntry> entries) async {
    await _service.deletePasswords(entries, isDecoy: _isDecoy);
    await loadPasswords();
    _refreshVault();
  }

  Future<PasswordEntry> toggleFavorite(PasswordEntry entry) async {
    final toggled =
        await _service.toggleFavorite(entry, isDecoy: _isDecoy);
    await loadPasswords();
    return toggled;
  }

  void _refreshVault() {
    ref.invalidate(vaultNotifierProvider);
  }
}

final passwordsNotifierProvider =
    NotifierProvider<PasswordsNotifier, AsyncValue<List<PasswordEntry>>>(() {
  return PasswordsNotifier();
});
