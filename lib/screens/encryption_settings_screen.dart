import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/encryption_algorithm.dart';
import '../models/vault_settings.dart';
import '../providers/vault_providers.dart';
import '../themes/app_colors.dart';
import 'encryption_manage_screen.dart';
import 're_encrypt_file_picker_screen.dart';

class EncryptionSettingsScreen extends ConsumerStatefulWidget {
  const EncryptionSettingsScreen({super.key});

  @override
  ConsumerState<EncryptionSettingsScreen> createState() =>
      _EncryptionSettingsScreenState();
}

class _EncryptionSettingsScreenState
    extends ConsumerState<EncryptionSettingsScreen> {
  static const List<int> _kdfIterationOptions = [100000, 300000, 600000, 1000000];

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(vaultSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Encryption Settings')),
      body: settingsAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: context.accentColor),
        ),
        error: (_, __) => Center(
          child: Text(
            'Failed to load settings',
            style: TextStyle(color: context.textPrimary),
          ),
        ),
        data: (settings) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              _sectionTitle('Encryption Algorithm'),
              ...EncryptionAlgorithm.values.map(
                (algo) => _algorithmTile(settings, algo),
              ),
              const SizedBox(height: 24),
              _sectionTitle('KDF Iterations'),
              Text(
                'Higher values are more secure but slower. Changes apply to new credentials only.',
                style: TextStyle(fontSize: 12, color: context.textTertiary),
              ),
              const SizedBox(height: 8),
              ..._kdfIterationOptions.map(
                (iterations) => _iterationTile(settings, iterations),
              ),
              const SizedBox(height: 24),
              _sectionTitle('Re-Encrypt Vault'),
              Text(
                'Re-encrypt all files using the selected algorithm. This may take a while for large vaults.',
                style: TextStyle(fontSize: 12, color: context.textTertiary),
              ),
              _tile(
                icon: Icons.sync,
                title: 'Re-Encrypt Files',
                subtitle: 'Pick files to re-encrypt now',
                onTap: () => _confirmReEncrypt(context, settings),
              ),
              const SizedBox(height: 24),
              _sectionTitle('Manage File Encryption'),
              Text(
                'Encrypt unencrypted files, or remove encryption to store files as plaintext.',
                style: TextStyle(fontSize: 12, color: context.textTertiary),
              ),
              _tile(
                icon: Icons.lock_outline,
                title: 'Encrypt',
                subtitle: 'Encrypt files that are stored as plaintext',
                onTap: () => _pushManage(settings, VaultEncryptionAction.encrypt),
              ),
              _tile(
                icon: Icons.lock_open,
                title: 'Remove Encryption',
                subtitle: 'Store encrypted files as plaintext',
                onTap: () => _pushManage(
                  settings,
                  VaultEncryptionAction.removeEncryption,
                ),
              ),
              const SizedBox(height: 24),
              _sectionTitle('Current Configuration'),
              _infoTile('Algorithm', settings.encryptionAlgorithm.displayName),
              _infoTile('KDF Iterations', settings.kdfIterations.toLocaleString()),
              _infoTile(
                'Encryption',
                settings.encryptionEnabled ? 'Enabled' : 'Disabled',
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: context.accentColor,
        ),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: context.accentColor),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: context.textTertiary),
      ),
      trailing: Icon(Icons.chevron_right, color: context.textTertiary),
      onTap: onTap,
    );
  }

  Widget _algorithmTile(VaultSettings settings, EncryptionAlgorithm algo) {
    final isSelected = settings.encryptionAlgorithm == algo;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        algo == EncryptionAlgorithm.aes256Gcm
            ? Icons.verified_user_outlined
            : Icons.lock_outline,
        color: isSelected ? context.accentColor : context.textSecondary,
      ),
      title: Text(
        algo.displayName,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          color: isSelected ? context.accentColor : context.textPrimary,
        ),
      ),
      subtitle: Text(
        algo.description,
        style: TextStyle(fontSize: 12, color: context.textTertiary),
      ),
      trailing: isSelected
          ? Icon(Icons.check_circle, color: context.accentColor)
          : null,
      onTap: () => _selectAlgorithm(settings, algo),
    );
  }

  Widget _iterationTile(VaultSettings settings, int iterations) {
    final isSelected = settings.kdfIterations == iterations;
    final label = iterations >= 1000000
        ? '${(iterations / 1000000).round()}M'
        : iterations == 100000
            ? '${(iterations / 1000).round()}K (Default)'
            : '${(iterations / 1000).round()}K';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        Icons.speed_outlined,
        color: isSelected ? context.accentColor : context.textSecondary,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          color: isSelected ? context.accentColor : context.textPrimary,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check_circle, color: context.accentColor)
          : null,
      onTap: () => _selectIterations(settings, iterations),
    );
  }

  Widget _infoTile(String label, String value) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label),
      trailing: Text(
        value,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: context.textSecondary,
        ),
      ),
    );
  }

  void _pushManage(VaultSettings settings, VaultEncryptionAction action) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EncryptionManageScreen(
          action: action,
          algorithm: settings.encryptionAlgorithm,
        ),
      ),
    );
  }

  Future<void> _selectAlgorithm(
    VaultSettings settings,
    EncryptionAlgorithm algo,
  ) async {
    if (settings.encryptionAlgorithm == algo) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surfaceColor,
        title: Text(
          'Change Encryption Algorithm',
          style: TextStyle(color: context.textPrimary),
        ),
        content: Text(
          'New files will use ${algo.displayName}. Existing files keep their current algorithm until you re-encrypt the vault.',
          style: TextStyle(color: context.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: context.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: context.accentColor,
            ),
            child: const Text('Change'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _saveVaultSettings(
        settings.copyWith(encryptionAlgorithm: algo),
      );
    }
  }

  Future<void> _selectIterations(
    VaultSettings settings,
    int iterations,
  ) async {
    if (settings.kdfIterations == iterations) return;

    await _saveVaultSettings(settings.copyWith(kdfIterations: iterations));
  }

  Future<void> _confirmReEncrypt(
    BuildContext context,
    VaultSettings settings,
  ) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReEncryptFilePickerScreen(
          targetAlgorithm: settings.encryptionAlgorithm,
        ),
      ),
    );
  }

  Future<void> _saveVaultSettings(VaultSettings settings) async {
    await ref.read(vaultServiceProvider).updateSettings(settings);
    ref.invalidate(vaultSettingsProvider);
  }
}

extension on int {
  String toLocaleString() {
    final str = toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(str[i]);
    }
    return buffer.toString();
  }
}
