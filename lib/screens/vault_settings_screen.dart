import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/theme_provider.dart';
import '../providers/vault_providers.dart';
import '../services/auth_service.dart';
import '../services/auto_kill_service.dart';
import '../services/screenshot_protection_service.dart';
import '../services/vault_service.dart';
import '../themes/app_colors.dart';
import 'accent_color_picker_screen.dart';
import 'change_security_screen.dart';
import 'encryption_settings_screen.dart';
import 'local_backup_screen.dart';
import 'privacy_policy_screen.dart';

class VaultSettingsScreen extends ConsumerStatefulWidget {
  const VaultSettingsScreen({super.key});

  @override
  ConsumerState<VaultSettingsScreen> createState() =>
      _VaultSettingsScreenState();
}

class _VaultSettingsScreenState extends ConsumerState<VaultSettingsScreen> {
  static const List<int> _autoKillDelayOptions = [0, 5, 10, 30, 60];
  static const List<int> _lockoutAttemptOptions = [3, 5, 7, 10];
  static const List<int> _lockoutDurationOptions = [30, 60, 300, 900, 1800, 3600, 7200];
  static const List<int> _wipeAttemptOptions = [10, 15, 20, 30];

  late Future<PackageInfo> _packageInfoFuture;
  AppUpdateInfo? _updateInfo;
  bool _isScanning = false;
  bool _hasScanned = false;

  @override
  void initState() {
    super.initState();
    _packageInfoFuture = PackageInfo.fromPlatform();
  }

  Future<void> _scanForUpdate() async {
    if (!Platform.isAndroid) return;
    setState(() => _isScanning = true);
    try {
      _updateInfo = await InAppUpdate.checkForUpdate();
    } catch (_) {
      _updateInfo = null;
    }
    if (mounted) {
      setState(() {
        _isScanning = false;
        _hasScanned = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(vaultSettingsProvider);

    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Settings',
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
          final autoKillSupported = AutoKillService.isSupported;
          final screenshotProtectionSupported =
              ScreenshotProtectionService.isSupported;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              _buildSectionTitle(context, 'Security'),
              ListTile(
                leading:
                    Icon(Icons.security_outlined, color: context.accentColor),
                title: const Text(
                  'Change Security',
                  style: TextStyle(fontFamily: 'ProductSans'),
                ),
                subtitle: Text(
                  'Change password, PIN, or biometric',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 12,
                    color: context.textTertiary,
                  ),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ChangeSecurityScreen(),
                    ),
                  );
                },
                contentPadding: EdgeInsets.zero,
              ),
              ListTile(
                leading: Icon(
                  Icons.enhanced_encryption_outlined,
                  color: context.accentColor,
                ),
                title: const Text(
                  'Encryption Settings',
                  style: TextStyle(fontFamily: 'ProductSans'),
                ),
                subtitle: Text(
                  'Algorithm, KDF iterations, re-encryption',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 12,
                    color: context.textTertiary,
                  ),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const EncryptionSettingsScreen(),
                    ),
                  );
                },
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: const Text(
                  'Encrypt New Files',
                  style: TextStyle(fontFamily: 'ProductSans'),
                ),
                subtitle: Text(
                  'AES-256 encryption for all new imports',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 12,
                    color: context.textTertiary,
                  ),
                ),
                value: settings.encryptionEnabled,
                onChanged: (value) async {
                  await _saveVaultSettings(
                    settings.copyWith(encryptionEnabled: value),
                  );
                },
                activeThumbColor: context.accentColor,
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: const Text(
                  'Secure Delete',
                  style: TextStyle(fontFamily: 'ProductSans'),
                ),
                subtitle: Text(
                  'Overwrite files before deletion',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 12,
                    color: context.textTertiary,
                  ),
                ),
                value: settings.secureDelete,
                onChanged: (value) async {
                  await _saveVaultSettings(
                    settings.copyWith(secureDelete: value),
                  );
                },
                activeThumbColor: context.accentColor,
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: const Text(
                  'In-App Screenshot Protection',
                  style: TextStyle(fontFamily: 'ProductSans'),
                ),
                subtitle: Text(
                  screenshotProtectionSupported
                      ? 'Blocks screenshots and app previews while Latch is open'
                      : 'Available on supported Android devices',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 12,
                    color: context.textTertiary,
                  ),
                ),
                value: settings.screenshotProtectionEnabled,
                onChanged: screenshotProtectionSupported
                    ? (value) async {
                        await _saveVaultSettings(
                          settings.copyWith(
                            screenshotProtectionEnabled: value,
                          ),
                        );
                      }
                    : null,
                activeThumbColor: context.accentColor,
                contentPadding: EdgeInsets.zero,
              ),
              _buildSecurityOptionDropdown(
                context: context,
                title: 'Auto-Kill Delay',
                subtitle: autoKillSupported
                    ? 'How long Latch waits after going to the background before it closes itself'
                    : 'Available on supported Android devices',
                value: settings.autoKillDelaySeconds,
                options: _autoKillDelayOptions,
                labelBuilder: _autoKillDelayLabel,
                enabled: autoKillSupported,
                onChanged: (value) async {
                  if (value == null) return;
                  await _saveVaultSettings(
                    settings.copyWith(autoKillDelaySeconds: value),
                  );
                },
              ),
              const SizedBox(height: 20),
              Divider(color: context.borderColor),
              const SizedBox(height: 20),
              _buildSectionTitle(context, 'Appearance'),
              _buildThemeToggle(context, ref),
              _buildAccentColorOption(context, ref),
              const SizedBox(height: 20),
              Divider(color: context.borderColor),
              const SizedBox(height: 20),
              _buildSectionTitle(context, 'Storage'),
              ListTile(
                leading:
                    Icon(Icons.backup_outlined, color: context.accentColor),
                title: const Text(
                  'Local Backup',
                  style: TextStyle(fontFamily: 'ProductSans'),
                ),
                subtitle: Text(
                  'Save vault as ZIP to a folder',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 12,
                    color: context.textTertiary,
                  ),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LocalBackupScreen(),
                    ),
                  );
                },
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: const Text(
                  'Compress Media',
                  style: TextStyle(fontFamily: 'ProductSans'),
                ),
                subtitle: Text(
                  'Reduce file size for images and videos',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 12,
                    color: context.textTertiary,
                  ),
                ),
                value: settings.compressionEnabled,
                onChanged: (value) async {
                  await _saveVaultSettings(
                    settings.copyWith(compressionEnabled: value),
                  );
                },
                activeThumbColor: context.accentColor,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 20),
              Divider(color: context.borderColor),
              const SizedBox(height: 20),
              _buildSectionTitle(context, 'Unlock Protection'),
              SwitchListTile(
                title: const Text(
                  'Failed Unlock Protection',
                  style: TextStyle(fontFamily: 'ProductSans'),
                ),
                subtitle: Text(
                  'Adds a cooldown after repeated wrong PIN, password, or biometric attempts',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 12,
                    color: context.textTertiary,
                  ),
                ),
                value: settings.failedUnlockProtectionEnabled,
                onChanged: (value) async {
                  await _toggleFailedUnlockProtection(settings, value);
                },
                activeThumbColor: context.accentColor,
                contentPadding: EdgeInsets.zero,
              ),
              if (settings.failedUnlockProtectionEnabled) ...[
                _buildSecurityOptionDropdown(
                  context: context,
                  title: 'Attempts Before Cooldown',
                  subtitle:
                      'How many failed unlocks are allowed before access is paused',
                  value: settings.maxFailedAttemptsBeforeLockout,
                  options: _lockoutAttemptOptions,
                  labelBuilder: (value) => value.toString(),
                  onChanged: (value) async {
                    if (value == null) return;
                    await _saveUnlockProtectionSettings(
                      settings.copyWith(maxFailedAttemptsBeforeLockout: value),
                    );
                  },
                ),
                _buildSecurityOptionDropdown(
                  context: context,
                  title: 'Cooldown Timer',
                  subtitle:
                      'How long unlock stays disabled after the cooldown threshold is hit',
                  value: settings.lockoutDurationSeconds,
                  options: _lockoutDurationOptions,
                  labelBuilder: _lockoutDurationLabel,
                  onChanged: (value) async {
                    if (value == null) return;
                    await _saveUnlockProtectionSettings(
                      settings.copyWith(lockoutDurationSeconds: value),
                    );
                  },
                ),
                SwitchListTile(
                  title: const Text(
                    'Wipe Vault At Hard Limit',
                    style: TextStyle(fontFamily: 'ProductSans'),
                  ),
                  subtitle: Text(
                    'Permanently erases real and decoy vault files after too many failed unlocks',
                    style: TextStyle(
                      fontFamily: 'ProductSans',
                      fontSize: 12,
                      color: context.textTertiary,
                    ),
                  ),
                  value: settings.wipeVaultOnMaxFailedAttempts,
                  onChanged: (value) async {
                    await _toggleVaultWipeProtection(settings, value);
                  },
                  activeThumbColor: AppColors.error,
                  contentPadding: EdgeInsets.zero,
                ),
                if (settings.wipeVaultOnMaxFailedAttempts) ...[
                  _buildSecurityOptionDropdown(
                    context: context,
                    title: 'Attempts Before Wipe',
                    subtitle:
                        'Latch erases all vault files when this failed-attempt total is reached',
                    value: settings.maxFailedAttemptsBeforeWipe,
                    options: _wipeAttemptOptions,
                    labelBuilder: (value) => value.toString(),
                    onChanged: (value) async {
                      if (value == null) return;
                      await _saveUnlockProtectionSettings(
                        settings.copyWith(maxFailedAttemptsBeforeWipe: value),
                      );
                    },
                  ),
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Text(
                      'Warning: wiping the vault is permanent and cannot be undone.',
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        fontSize: 12,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 20),
              Divider(color: context.borderColor),
              const SizedBox(height: 20),
              _buildSectionTitle(context, 'Support'),
              ListTile(
                leading: Icon(Icons.favorite_outline, color: context.accentColor),
                title: const Text('Donate', style: TextStyle(fontFamily: 'ProductSans')),
                subtitle: Text('Support development via Ko-fi', style: TextStyle(fontFamily: 'ProductSans', fontSize: 12, color: context.textTertiary)),
                trailing: Icon(Icons.open_in_new, color: context.textTertiary),
                onTap: () async {
                  final url = Uri.parse('https://ko-fi.com/ultraelectronica');
                  try {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Could not open donation page')),
                      );
                    }
                  }
                },
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 20),
              Divider(color: context.borderColor),
              const SizedBox(height: 20),
              _buildSectionTitle(context, 'Update'),
              if (_isScanning)
                ListTile(
                  leading: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.accentColor,
                    ),
                  ),
                  title: const Text('Scanning...',
                      style: TextStyle(fontFamily: 'ProductSans')),
                  subtitle: Text(
                    'Checking the Play Store for updates',
                    style: TextStyle(
                      fontFamily: 'ProductSans',
                      fontSize: 12,
                      color: context.textTertiary,
                    ),
                  ),
                  contentPadding: EdgeInsets.zero,
                )
              else if (_hasScanned &&
                  _updateInfo != null &&
                  _updateInfo!.updateAvailability ==
                      UpdateAvailability.updateAvailable)
                ListTile(
                  leading: Icon(Icons.system_update,
                      color: context.accentColor),
                  title: const Text('Update Available',
                      style: TextStyle(fontFamily: 'ProductSans')),
                  subtitle: Text(
                    'A new version is available on the Play Store',
                    style: TextStyle(
                      fontFamily: 'ProductSans',
                      fontSize: 12,
                      color: context.textTertiary,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showUpdateDialog(),
                  contentPadding: EdgeInsets.zero,
                )
              else if (_hasScanned)
                ListTile(
                  leading: Icon(Icons.check_circle_outline,
                      color: context.accentColor),
                  title: const Text('Up to Date',
                      style: TextStyle(fontFamily: 'ProductSans')),
                  subtitle: Text(
                    'No updates available',
                    style: TextStyle(
                      fontFamily: 'ProductSans',
                      fontSize: 12,
                      color: context.textTertiary,
                    ),
                  ),
                  contentPadding: EdgeInsets.zero,
                )
              else
                ListTile(
                  leading: Icon(Icons.system_update,
                      color: context.accentColor),
                  title: const Text('Scan for Updates',
                      style: TextStyle(fontFamily: 'ProductSans')),
                  subtitle: Text(
                    'No update scan yet',
                    style: TextStyle(
                      fontFamily: 'ProductSans',
                      fontSize: 12,
                      color: context.textTertiary,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _scanForUpdate(),
                  contentPadding: EdgeInsets.zero,
                ),
              const SizedBox(height: 20),
              Divider(color: context.borderColor),
              const SizedBox(height: 20),
              _buildSectionTitle(context, 'About'),
              FutureBuilder<PackageInfo>(
                future: _packageInfoFuture,
                builder: (context, snapshot) {
                  final version = snapshot.data?.version ?? '...';
                  return Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.info_outline,
                            color: context.accentColor),
                        title: const Text('Version',
                            style: TextStyle(fontFamily: 'ProductSans')),
                        subtitle: Text(
                          version,
                          style: TextStyle(
                            fontFamily: 'ProductSans',
                            fontSize: 12,
                            color: context.textTertiary,
                          ),
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                      ListTile(
                        leading: Icon(Icons.description_outlined,
                            color: context.accentColor),
                        title: const Text('License',
                            style: TextStyle(fontFamily: 'ProductSans')),
                        subtitle: Text(
                          'MIT License',
                          style: TextStyle(
                            fontFamily: 'ProductSans',
                            fontSize: 12,
                            color: context.textTertiary,
                          ),
                        ),
                        onTap: () => _showLicenseDialog(),
                        contentPadding: EdgeInsets.zero,
                      ),
                      ListTile(
                        leading: Icon(Icons.privacy_tip_outlined,
                            color: context.accentColor),
                        title: const Text('Privacy Policy',
                            style: TextStyle(fontFamily: 'ProductSans')),
                        subtitle: Text(
                          'How we handle your data',
                          style: TextStyle(
                            fontFamily: 'ProductSans',
                            fontSize: 12,
                            color: context.textTertiary,
                          ),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const PrivacyPolicyScreen(),
                            ),
                          );
                        },
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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

  Future<void> _saveVaultSettings(VaultSettings settings) async {
    await ref.read(vaultServiceProvider).updateSettings(settings);
    await AutoKillService.setDelaySeconds(settings.autoKillDelaySeconds);
    await ScreenshotProtectionService.setEnabled(
      settings.screenshotProtectionEnabled,
    );
    ref.invalidate(vaultSettingsProvider);
  }

  Future<void> _saveUnlockProtectionSettings(VaultSettings settings) async {
    await _saveVaultSettings(settings);
    await AuthService().resetUnlockAttempts();
  }

  Future<void> _toggleFailedUnlockProtection(
    VaultSettings settings,
    bool enabled,
  ) async {
    await _saveUnlockProtectionSettings(
      settings.copyWith(failedUnlockProtectionEnabled: enabled),
    );
  }

  Future<void> _toggleVaultWipeProtection(
    VaultSettings settings,
    bool enabled,
  ) async {
    if (enabled) {
      final confirmed = await _confirmDangerousWipeProtection();
      if (confirmed != true) return;
    }

    await _saveUnlockProtectionSettings(
      settings.copyWith(wipeVaultOnMaxFailedAttempts: enabled),
    );
  }

  Future<bool?> _confirmDangerousWipeProtection() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(dialogContext).scaffoldBackgroundColor,
        title: const Text(
          'Enable Vault Wipe?',
          style: TextStyle(fontFamily: 'ProductSans'),
        ),
        content: const Text(
          'When the failed-attempt limit is reached, Latch will permanently erase the real and decoy vault files on this device. This cannot be undone.',
          style: TextStyle(fontFamily: 'ProductSans'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  }

  void _showLicenseDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(dialogContext).scaffoldBackgroundColor,
        title: const Text(
          'MIT License',
          style: TextStyle(fontFamily: 'ProductSans'),
        ),
        content: const SingleChildScrollView(
          child: Text(
            'MIT License\n\n'
            'Copyright (c) 2025 ultraelectronica\n\n'
            'Permission is hereby granted, free of charge, to any person '
            'obtaining a copy of this software and associated documentation '
            'files (the "Software"), to deal in the Software without '
            'restriction, including without limitation the rights to use, '
            'copy, modify, merge, publish, distribute, sublicense, and/or '
            'sell copies of the Software, and to permit persons to whom the '
            'Software is furnished to do so, subject to the following '
            'conditions:\n\n'
            'The above copyright notice and this permission notice shall be '
            'included in all copies or substantial portions of the Software.\n\n'
            'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, '
            'EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES '
            'OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND '
            'NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT '
            'HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, '
            'WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING '
            'FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR '
            'OTHER DEALINGS IN THE SOFTWARE.',
            style: TextStyle(fontFamily: 'ProductSans'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showUpdateDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(dialogContext).scaffoldBackgroundColor,
        title: const Text('Update Available',
            style: TextStyle(fontFamily: 'ProductSans')),
        content: const Text(
          'A new version is available on the Play Store. Update now?',
          style: TextStyle(fontFamily: 'ProductSans'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              InAppUpdate.performImmediateUpdate();
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityOptionDropdown({
    required BuildContext context,
    required String title,
    required String subtitle,
    required int value,
    required List<int> options,
    required String Function(int value) labelBuilder,
    bool enabled = true,
    required ValueChanged<int?> onChanged,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: const TextStyle(fontFamily: 'ProductSans'),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontFamily: 'ProductSans',
          fontSize: 12,
          color: context.textTertiary,
        ),
      ),
      trailing: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          borderRadius: BorderRadius.circular(12),
          items: options
              .map(
                (option) => DropdownMenuItem<int>(
                  value: option,
                  child: Text(
                    labelBuilder(option),
                    style: const TextStyle(fontFamily: 'ProductSans'),
                  ),
                ),
              )
              .toList(),
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }

  String _lockoutDurationLabel(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    }

    if (seconds < 3600) {
      final minutes = seconds ~/ 60;
      return minutes == 1 ? '1 min' : '$minutes min';
    }

    final hours = seconds ~/ 3600;
    return hours == 1 ? '1 hr' : '$hours hr';
  }

  String _autoKillDelayLabel(int seconds) {
    if (seconds == 0) return 'Instant';
    return _lockoutDurationLabel(seconds);
  }

  Widget _buildThemeToggle(BuildContext context, WidgetRef ref) {
    final isDarkMode = ref.watch(isDarkModeProvider);

    return SwitchListTile(
      title: const Text(
        'Dark Mode',
        style: TextStyle(fontFamily: 'ProductSans'),
      ),
      subtitle: Text(
        isDarkMode ? 'Eye-friendly dark theme' : 'Clean light theme',
        style: TextStyle(
          fontFamily: 'ProductSans',
          fontSize: 12,
          color: context.textTertiary,
        ),
      ),
      secondary: Icon(
        isDarkMode ? Icons.dark_mode : Icons.light_mode,
        color: context.accentColor,
      ),
      value: isDarkMode,
      onChanged: (_) {
        ref.read(themeModeProvider.notifier).toggleTheme();
      },
      activeThumbColor: context.accentColor,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildAccentColorOption(BuildContext context, WidgetRef ref) {
    final accentColor = ref.watch(accentColorProvider);

    return ListTile(
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accentColor.getColor(
                context.isDarkMode ? Brightness.dark : Brightness.light,
              ),
              accentColor.getVariantColor(
                context.isDarkMode ? Brightness.dark : Brightness.light,
              ),
            ],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: context.isDarkMode
                ? Colors.white.withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: 0.1),
            width: 1.5,
          ),
        ),
      ),
      title: const Text(
        'Accent Color',
        style: TextStyle(fontFamily: 'ProductSans'),
      ),
      subtitle: Text(
        accentColor.name,
        style: TextStyle(
          fontFamily: 'ProductSans',
          fontSize: 12,
          color: context.textTertiary,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const AccentColorPickerScreen(),
          ),
        );
      },
      contentPadding: EdgeInsets.zero,
    );
  }
}
