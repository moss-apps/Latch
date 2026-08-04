import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/sync_profile.dart';
import '../providers/sync_provider.dart';
import '../providers/vault_providers.dart';
import '../services/remote/webdav_store.dart';
import '../services/sync_profile_service.dart';
import '../themes/app_colors.dart';

/// Connection settings + sync status for the local-server sync feature
/// (docs/local_server_sync.md). One profile per vault (v1).
class SyncSettingsScreen extends ConsumerStatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  ConsumerState<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends ConsumerState<SyncSettingsScreen> {
  final _urlController = TextEditingController();
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  final _basePathController = TextEditingController(text: '/locker');

  SyncDirection _direction = SyncDirection.pushOnly;
  bool _wifiOnly = true;
  bool _enabled = false;
  bool _isTesting = false;
  bool _loading = true;
  String? _activeProfileId;

  @override
  void initState() {
    super.initState();
    _loadActiveProfile();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    _basePathController.dispose();
    super.dispose();
  }

  Future<void> _loadActiveProfile() async {
    final settings = await ref.read(vaultServiceProvider).getSettings();
    String? id = settings.syncProfileId;
    SyncProfile? profile;
    if (id != null) profile = await SyncProfileService.instance.getProfile(id);
    profile ??= (await SyncProfileService.instance.listProfiles()).firstOrNull;

    if (profile != null) {
      _activeProfileId = profile.id;
      _urlController.text = profile.serverUrl;
      _userController.text = profile.username ?? '';
      _basePathController.text = profile.basePath;
      _direction = profile.direction;
      _wifiOnly = profile.wifiOnly;
      _enabled = profile.enabled;
    }
    if (mounted) setState(() => _loading = false);
  }

  bool get _isPlainHttp =>
      _urlController.text.trim().toLowerCase().startsWith('http://');

  SyncProfile _profileFromForm() => SyncProfile(
        id: _activeProfileId ?? const Uuid().v4(),
        serverUrl: _urlController.text.trim(),
        username: _userController.text.trim().isEmpty
            ? null
            : _userController.text.trim(),
        basePath:
            _basePathController.text.trim().isEmpty
                ? '/locker'
                : _basePathController.text.trim(),
        direction: _direction,
        wifiOnly: _wifiOnly,
        enabled: _enabled,
      );

  Future<void> _testConnection() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _snack('Enter a server URL first');
      return;
    }
    setState(() => _isTesting = true);
    try {
      final password = _passwordController.text.isNotEmpty
          ? _passwordController.text
          : (_activeProfileId == null
              ? ''
              : await SyncProfileService.instance
                      .getPassword(_activeProfileId!) ??
                  '');
      final store = WebDAVStore(
        baseUrl: url,
        username: _userController.text.trim(),
        password: password,
        basePath:
            _basePathController.text.trim().isEmpty
                ? '/locker'
                : _basePathController.text.trim(),
      );
      await store.testConnection();
      _snack('Connected ✓');
    } catch (e) {
      _snack('Connection failed: $e');
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _save() async {
    if (_urlController.text.trim().isEmpty) {
      _snack('Server URL is required');
      return;
    }
    final profile = _profileFromForm();
    await SyncProfileService.instance.saveProfile(profile);
    if (_passwordController.text.isNotEmpty) {
      await SyncProfileService.instance
          .savePassword(profile.id, _passwordController.text);
      _passwordController.clear();
    }
    _activeProfileId = profile.id;

    // Activate this profile in vault settings.
    final settings = await ref.read(vaultServiceProvider).getSettings();
    await ref.read(vaultServiceProvider).updateSettings(
          settings.copyWith(syncEnabled: profile.enabled, syncProfileId: profile.id),
        );
    ref.invalidate(vaultSettingsProvider);
    ref.invalidate(syncProfilesProvider);
    if (mounted) _snack('Saved');
  }

  Future<void> _syncNow() async {
    await ref.read(syncProvider.notifier).syncNow();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(syncProvider);

    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Server Sync',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: context.accentColor),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _buildStatusCard(context, syncState),
                const SizedBox(height: 20),
                _sectionTitle(context, 'Server'),
                _textField(
                  controller: _urlController,
                  label: 'Server URL',
                  hint: 'https://nas.local/dav',
                  keyboardType: TextInputType.url,
                  onChanged: (_) => setState(() {}),
                ),
                if (_isPlainHttp) _plainHttpWarning(context),
                _textField(
                  controller: _userController,
                  label: 'Username (optional)',
                  hint: 'app-password user',
                ),
                _textField(
                  controller: _passwordController,
                  label: 'Password',
                  hint: _activeProfileId == null
                      ? 'app password'
                      : 'leave blank to keep current',
                  obscure: true,
                ),
                _textField(
                  controller: _basePathController,
                  label: 'Base path',
                  hint: '/locker',
                ),
                const SizedBox(height: 8),
                InputDecorator(
                  decoration: _inputDecoration('Direction'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<SyncDirection>(
                      value: _direction,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(
                          value: SyncDirection.pushOnly,
                          child: Text('Push only (backup)',
                              style: TextStyle(fontFamily: 'ProductSans')),
                        ),
                        DropdownMenuItem(
                          value: SyncDirection.twoWay,
                          child: Text('Two-way',
                              style: TextStyle(fontFamily: 'ProductSans')),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _direction = v ?? _direction),
                    ),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Wi-Fi only',
                      style: TextStyle(fontFamily: 'ProductSans')),
                  subtitle: Text(
                    'Skip sync on mobile data',
                    style: _subStyle(context),
                  ),
                  value: _wifiOnly,
                  onChanged: (v) => setState(() => _wifiOnly = v),
                  activeThumbColor: context.accentColor,
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  title: const Text('Enabled',
                      style: TextStyle(fontFamily: 'ProductSans')),
                  subtitle: Text(
                    'Use this profile as the active sync target',
                    style: _subStyle(context),
                  ),
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                  activeThumbColor: context.accentColor,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isTesting ? null : _testConnection,
                        child: _isTesting
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: context.accentColor),
                              )
                            : const Text('Test Connection',
                                style: TextStyle(fontFamily: 'ProductSans')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _save,
                        child: const Text('Save',
                            style: TextStyle(fontFamily: 'ProductSans')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Divider(color: context.borderColor),
                const SizedBox(height: 20),
                _sectionTitle(context, 'Sync'),
                Text(
                  'Push-only backup ships the vault as encrypted blobs to your '
                  'server. Two-way restore is a later phase.',
                  style: _subStyle(context),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: syncState.isSyncing
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.backgroundColor),
                          )
                        : const Icon(Icons.sync),
                    label: Text(
                        syncState.isSyncing ? 'Syncing…' : 'Sync Now',
                        style: const TextStyle(fontFamily: 'ProductSans')),
                    onPressed: syncState.isSyncing ? null : _syncNow,
                  ),
                ),
                if (syncState.status == SyncStatus.error &&
                    syncState.error != null) ...[
                  const SizedBox(height: 12),
                  _errorBanner(context, syncState.error!),
                ],
              ],
            ),
    );
  }

  Widget _buildStatusCard(BuildContext context, SyncState s) {
    final (label, color) = switch (s.status) {
      SyncStatus.idle => ('Idle', context.textTertiary),
      SyncStatus.syncing => ('Syncing…', context.accentColor),
      SyncStatus.success => ('Up to date', Colors.green),
      SyncStatus.error => ('Error', AppColors.error),
    };
    final last = s.lastSync;
    final progress = s.progress;
    String? detail;
    if (s.isSyncing && progress != null && progress.total > 0) {
      detail = '${progress.phase.name} ${progress.completed}/${progress.total}';
    } else if (last != null) {
      detail = 'Last sync ${_formatDate(last)}';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(s.status == SyncStatus.success
              ? Icons.cloud_done_outlined
              : s.status == SyncStatus.error
                  ? Icons.error_outline
                  : Icons.cloud_sync_outlined, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontFamily: 'ProductSans',
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary)),
                if (detail != null)
                  Text(detail, style: _subStyle(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _plainHttpWarning(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 8, bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.18)),
        ),
        child: Text(
          'This URL is unencrypted. Credentials and data travel in plain text '
          'over the network. Only use on a trusted LAN.',
          style: TextStyle(
              fontFamily: 'ProductSans', fontSize: 12, color: AppColors.error),
        ),
      );

  Widget _errorBanner(BuildContext context, String msg) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.18)),
        ),
        child: Text(msg,
            style: TextStyle(
                fontFamily: 'ProductSans', fontSize: 12, color: AppColors.error)),
      );

  Widget _sectionTitle(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title,
            style: TextStyle(
                fontFamily: 'ProductSans',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: context.textPrimary)),
      );

  TextStyle _subStyle(BuildContext context) => TextStyle(
        fontFamily: 'ProductSans',
        fontSize: 12,
        color: context.textTertiary,
      );

  InputDecoration _inputDecoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontFamily: 'ProductSans'),
        border: const OutlineInputBorder(),
      );

  Widget _textField({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool obscure = false,
    TextInputType? keyboardType,
    void Function(String)? onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            labelStyle: const TextStyle(fontFamily: 'ProductSans'),
            hintStyle: const TextStyle(fontFamily: 'ProductSans'),
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) => onChanged?.call(v),
        ),
      );

  String _formatDate(DateTime d) {
    final local = d.toLocal();
    return '${local.day}/${local.month}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
