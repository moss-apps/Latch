import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/encryption_algorithm.dart';
import '../providers/vault_providers.dart';
import '../services/vault_service.dart';
import '../themes/app_colors.dart';

class EncryptionSettingsScreen extends ConsumerStatefulWidget {
  const EncryptionSettingsScreen({super.key});

  @override
  ConsumerState<EncryptionSettingsScreen> createState() =>
      _EncryptionSettingsScreenState();
}

class _EncryptionSettingsScreenState
    extends ConsumerState<EncryptionSettingsScreen> {
  static const List<int> _kdfIterationOptions = [100000, 200000, 500000];
  bool _isReEncrypting = false;

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(vaultSettingsProvider);
    final reEncryptProgress = ref.watch(reEncryptProvider);

    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Encryption Settings',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: settingsAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: context.accentColor),
        ),
        error: (_, __) => Center(
          child: Text(
            'Failed to load settings',
            style: TextStyle(
              fontFamily: 'ProductSans',
              color: context.textPrimary,
            ),
          ),
        ),
        data: (settings) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              _buildSectionTitle(context, 'Encryption Algorithm'),
              const SizedBox(height: 8),
              ...EncryptionAlgorithm.values.map(
                (algo) => _buildAlgorithmCard(context, settings, algo),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle(context, 'KDF Iterations'),
              const SizedBox(height: 8),
              Text(
                'Higher values are more secure but slower. Changes apply to new credentials only.',
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  fontSize: 12,
                  color: context.textTertiary,
                ),
              ),
              const SizedBox(height: 12),
              ..._kdfIterationOptions.map(
                (iterations) => _buildIterationOption(
                  context,
                  settings,
                  iterations,
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle(context, 'Re-Encrypt Vault'),
              const SizedBox(height: 8),
              Text(
                'Re-encrypt all files using the selected algorithm. This may take a while for large vaults.',
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  fontSize: 12,
                  color: context.textTertiary,
                ),
              ),
              const SizedBox(height: 12),
              if (reEncryptProgress.isInProgress && _isReEncrypting)
                _buildProgressBar(context, reEncryptProgress),
              if (reEncryptProgress.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    reEncryptProgress.error!,
                    style: const TextStyle(
                      fontFamily: 'ProductSans',
                      color: Colors.red,
                      fontSize: 12,
                    ),
                  ),
                ),
              FilledButton.icon(
                onPressed: _isReEncrypting
                    ? null
                    : () => _confirmReEncrypt(context, settings),
                icon: const Icon(Icons.sync),
                label: const Text(
                  'Re-Encrypt All Files',
                  style: TextStyle(fontFamily: 'ProductSans'),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: context.accentColor,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle(context, 'Current Configuration'),
              const SizedBox(height: 8),
              _buildInfoCard(context, settings),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title,
        style: TextStyle(
          fontFamily: 'ProductSans',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: context.textPrimary,
        ),
      ),
    );
  }

  Widget _buildAlgorithmCard(
    BuildContext context,
    VaultSettings settings,
    EncryptionAlgorithm algo,
  ) {
    final isSelected = settings.encryptionAlgorithm == algo;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: isSelected
          ? context.accentColor.withValues(alpha: 0.15)
          : context.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: context.accentColor, width: 2)
            : BorderSide(color: context.dividerColor),
      ),
      child: ListTile(
        leading: Icon(
          algo == EncryptionAlgorithm.aes256Gcm
              ? Icons.verified_user_outlined
              : Icons.lock_outline,
          color: isSelected ? context.accentColor : context.textSecondary,
        ),
        title: Text(
          algo.displayName,
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? context.accentColor : context.textPrimary,
          ),
        ),
        subtitle: Text(
          algo.description,
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontSize: 12,
            color: context.textTertiary,
          ),
        ),
        trailing: isSelected
            ? Icon(Icons.check_circle, color: context.accentColor)
            : null,
        onTap: () => _selectAlgorithm(settings, algo),
      ),
    );
  }

  Widget _buildIterationOption(
    BuildContext context,
    VaultSettings settings,
    int iterations,
  ) {
    final isSelected = settings.kdfIterations == iterations;
    final label = iterations == 100000
        ? '${(iterations / 1000).round()}K (Default)'
        : '${(iterations / 1000).round()}K';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: isSelected
          ? context.accentColor.withValues(alpha: 0.15)
          : context.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: context.accentColor, width: 2)
            : BorderSide(color: context.dividerColor),
      ),
      child: ListTile(
        title: Text(
          label,
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? context.accentColor : context.textPrimary,
          ),
        ),
        trailing: isSelected
            ? Icon(Icons.check_circle, color: context.accentColor)
            : null,
        onTap: () => _selectIterations(settings, iterations),
      ),
    );
  }

  Widget _buildProgressBar(BuildContext context, ReEncryptProgress progress) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: progress.total > 0
                ? progress.current / progress.total
                : null,
            backgroundColor: context.dividerColor,
            color: context.accentColor,
          ),
          const SizedBox(height: 4),
          Text(
            progress.total > 0
                ? 'Re-encrypting ${progress.current}/${progress.total} files...'
                : 'Re-encrypting...',
            style: TextStyle(
              fontFamily: 'ProductSans',
              fontSize: 12,
              color: context.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, VaultSettings settings) {
    return Card(
      elevation: 0,
      color: context.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow(
              context,
              'Algorithm',
              settings.encryptionAlgorithm.displayName,
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              context,
              'KDF Iterations',
              settings.kdfIterations.toLocaleString(),
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              context,
              'Encryption',
              settings.encryptionEnabled ? 'Enabled' : 'Disabled',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
        ),
      ],
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
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textPrimary,
          ),
        ),
        content: Text(
          'New files will use ${algo.displayName}. Existing files keep their current algorithm until you re-encrypt the vault.',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textSecondary,
          ),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surfaceColor,
        title: Text(
          'Re-Encrypt Vault',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textPrimary,
          ),
        ),
        content: Text(
          'This will re-encrypt all encrypted files using ${settings.encryptionAlgorithm.displayName}. This cannot be undone and may take a while. Make sure your device has sufficient battery.',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textSecondary,
          ),
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
              backgroundColor: Colors.red,
            ),
            child: const Text('Re-Encrypt'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isReEncrypting = true);
      await ref.read(reEncryptProvider.notifier).reEncryptVault(
            settings.encryptionAlgorithm,
          );
      if (mounted) {
        setState(() => _isReEncrypting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Re-encryption complete',
              style: TextStyle(fontFamily: 'ProductSans'),
            ),
          ),
        );
      }
    }
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