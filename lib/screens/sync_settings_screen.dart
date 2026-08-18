import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/sync_profile.dart';
import '../providers/sync_provider.dart';
import '../providers/vault_providers.dart';
import '../services/remote/webdav_store.dart';
import '../services/sync_profile_service.dart';
import '../services/sync_service.dart' show SyncPhase, SyncProgress;
import '../themes/app_colors.dart';

/// Connection settings + sync status for the local-server sync feature
/// (docs/local_server_sync.md). Supports multiple profiles; exactly one is
/// "active" (the sync target), held in vault settings as [syncProfileId].
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

  /// Profile currently loaded into the editor form. Null = a fresh profile
  /// being created.
  String? _editingId;

  String? _activeId;
  bool _masterEnabled = false;

  bool _isTesting = false;
  bool _loading = true;
  bool _obscurePassword = true;
  final List<_SyncLogEntry> _log = [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
    ref.listen<SyncState>(syncProvider, _onSyncStateChanged);
  }

  /// One-shot load of settings + profiles; seeds the form with the active (or
  /// first) profile. Reactive updates afterwards come from watching the
  /// providers in [build], but form seeding only happens here and on explicit
  // user actions — never on a provider re-emit.
  Future<void> _bootstrap() async {
    final settings = await ref.read(vaultServiceProvider).getSettings();
    final profiles = await SyncProfileService.instance.listProfiles();
    _activeId = settings.syncProfileId;
    _masterEnabled = settings.syncEnabled;
    final target =
        (profiles.where((p) => p.id == _activeId).toList()).firstOrNull ??
            profiles.firstOrNull;
    _seedForm(target);
    if (mounted) setState(() => _loading = false);
  }

  void _seedForm(SyncProfile? p) {
    _editingId = p?.id;
    _urlController.text = p?.serverUrl ?? '';
    _userController.text = p?.username ?? '';
    _basePathController.text =
        p?.basePath.isEmpty == true ? '/locker' : (p?.basePath ?? '/locker');
    _passwordController.clear();
    _direction = p?.direction ?? SyncDirection.pushOnly;
    _wifiOnly = p?.wifiOnly ?? true;
  }

  void _onSyncStateChanged(SyncState? prev, SyncState next) {
    if (next.status == SyncStatus.success &&
        prev?.status != SyncStatus.success) {
      _addLog(next.message ?? 'Sync completed', ok: true);
      // Profile's lastSyncedAt was persisted by the notifier — refresh the list.
      ref.invalidate(syncProfilesProvider);
      _showSuccessSheet(next);
    } else if (next.status == SyncStatus.error &&
        prev?.status != SyncStatus.error) {
      _addLog(next.error ?? 'Sync failed', ok: false);
      _snack(next.error ?? 'Sync failed');
    }
  }

  void _showSuccessSheet(SyncState s) {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: context.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_done, color: Colors.green, size: 48),
            const SizedBox(height: 12),
            Text(
              'Sync complete',
              style: TextStyle(
                fontFamily: 'ProductSans',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: ctx.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.message ?? 'Up to date',
              textAlign: TextAlign.center,
              style: _subStyle(ctx),
            ),
            const SizedBox(height: 4),
            Text(
              'Completed in ${_formatDuration(s.duration)}',
              style: _subStyle(ctx),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done',
                    style: TextStyle(fontFamily: 'ProductSans')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addLog(String message, {required bool ok}) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, _SyncLogEntry(DateTime.now(), message, ok));
      if (_log.length > 50) _log.removeRange(50, _log.length);
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    _basePathController.dispose();
    super.dispose();
  }

  bool get _isPlainHttp =>
      _urlController.text.trim().toLowerCase().startsWith('http://');

  bool get _editingActive => _editingId != null && _editingId == _activeId;

  SyncProfile _profileFromForm() => SyncProfile(
        id: _editingId ?? const Uuid().v4(),
        serverUrl: _urlController.text.trim(),
        username: _userController.text.trim().isEmpty
            ? null
            : _userController.text.trim(),
        basePath: _basePathController.text.trim().isEmpty
            ? '/locker'
            : _basePathController.text.trim(),
        direction: _direction,
        wifiOnly: _wifiOnly,
        enabled: true,
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
          : (_editingId == null
              ? ''
              : await SyncProfileService.instance.getPassword(_editingId!) ??
                  '');
      final store = WebDAVStore(
        baseUrl: url,
        username: _userController.text.trim(),
        password: password,
        basePath: _basePathController.text.trim().isEmpty
            ? '/locker'
            : _basePathController.text.trim(),
      );
      await store.testConnection();
      _snack('Connected ✓');
      _addLog('Connection test succeeded', ok: true);
    } catch (e) {
      final msg = _describeConnError(e);
      _snack(msg);
      _addLog('Connection test failed: $msg', ok: false);
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  /// Map a WebDAV/Dio failure to something actionable. A connect timeout on a
  /// LAN IP is always "server unreachable", never "timeout too short".
  // string-match on toString(); avoids importing transitive dio.
  String _describeConnError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('connection timeout') || s.contains('connecttimeout')) {
      return 'Couldn\'t reach the server (timed out). Check it\'s running on '
          'the right port and bound to 0.0.0.0, not localhost.';
    }
    if (s.contains('connection refused') ||
        s.contains('reset') ||
        s.contains('broken pipe')) {
      return 'Server refused the connection. Wrong port, or the WebDAV '
          'service isn\'t running.';
    }
    if (s.contains('connection error') ||
        s.contains('socket') ||
        s.contains('network') ||
        s.contains('host')) {
      return 'Network error — wrong address, firewall, or device not on the '
          'same LAN as the server.';
    }
    if (s.contains('401') || s.contains('unauthorized')) {
      return 'Authentication failed — check username and password.';
    }
    return 'Connection failed: $e';
  }

  Future<void> _save() async {
    if (_urlController.text.trim().isEmpty) {
      _snack('Server URL is required');
      return;
    }
    final isNew = _editingId == null;
    final profile = _profileFromForm();
    await SyncProfileService.instance.saveProfile(profile);
    if (_passwordController.text.isNotEmpty) {
      await SyncProfileService.instance
          .savePassword(profile.id, _passwordController.text);
      _passwordController.clear();
    }
    _editingId = profile.id;

    // New profiles (or when none is active yet) auto-activate so sync works.
    if (isNew || _activeId == null) {
      _activeId = profile.id;
      _masterEnabled = true;
      await _persistActivation(profile.id, enabled: true);
    }
    ref.invalidate(vaultSettingsProvider);
    ref.invalidate(syncProfilesProvider);
    if (mounted) _snack('Saved');
  }

  Future<void> _activate(SyncProfile p) async {
    setState(() {
      _activeId = p.id;
      _masterEnabled = true;
    });
    await _persistActivation(p.id, enabled: true);
    ref.invalidate(vaultSettingsProvider);
    _snack('Active server: ${_hostOf(p.serverUrl)}');
  }

  Future<void> _setMasterEnabled(bool v) async {
    setState(() => _masterEnabled = v);
    final s = await ref.read(vaultServiceProvider).getSettings();
    await ref
        .read(vaultServiceProvider)
        .updateSettings(s.copyWith(syncEnabled: v));
    ref.invalidate(vaultSettingsProvider);
  }

  Future<void> _persistActivation(String id, {required bool enabled}) async {
    final s = await ref.read(vaultServiceProvider).getSettings();
    await ref.read(vaultServiceProvider).updateSettings(
          s.copyWith(syncProfileId: id, syncEnabled: enabled),
        );
  }

  Future<void> _confirmDelete(SyncProfile p) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: context.backgroundColor,
            title: const Text('Remove server?',
                style: TextStyle(fontFamily: 'ProductSans')),
            content: Text(
              'Delete the profile for ${_hostOf(p.serverUrl)}? '
              'Encrypted blobs already on the server are left in place.',
              style: _subStyle(ctx).copyWith(color: context.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel',
                    style: TextStyle(fontFamily: 'ProductSans')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete',
                    style: TextStyle(fontFamily: 'ProductSans')),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await SyncProfileService.instance.deleteProfile(p.id);
    final wasActive = _activeId == p.id;
    final wasEditing = _editingId == p.id;
    if (wasActive) {
      _activeId = null;
      final s = await ref.read(vaultServiceProvider).getSettings();
      await ref
          .read(vaultServiceProvider)
          .updateSettings(s.copyWith(syncProfileId: null));
    }
    if (wasEditing) {
      final remaining = await SyncProfileService.instance.listProfiles();
      _seedForm(remaining.firstOrNull);
    }
    ref.invalidate(vaultSettingsProvider);
    ref.invalidate(syncProfilesProvider);
    if (mounted) setState(() {});
  }

  Future<void> _syncNow() async {
    if (_activeId == null) {
      _snack('Add and activate a server first');
      return;
    }
    await ref.read(syncProvider.notifier).syncNow();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _hostOf(String url) {
    final u = Uri.tryParse(url);
    return u?.host.isNotEmpty == true ? u!.host : url;
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(syncProvider);
    final profilesAsync = ref.watch(syncProfilesProvider);
    final profiles = profilesAsync.asData?.value ?? const <SyncProfile>[];
    final active = profiles.where((p) => p.id == _activeId).firstOrNull;

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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _HeroStatus(
                  state: syncState,
                  active: active,
                  masterEnabled: _masterEnabled,
                ),
                const SizedBox(height: 20),

                // ---- Profiles ----
                _SectionHeader(
                  title: 'Servers',
                  trailing: TextButton.icon(
                    onPressed: () => setState(_seedFormNull),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add',
                        style: TextStyle(fontFamily: 'ProductSans')),
                  ),
                ),
                if (profiles.isEmpty)
                  _emptyServersHint(context)
                else
                  ...profiles.map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _profileCard(context, p,
                            isActive: p.id == _activeId),
                      )),
                const SizedBox(height: 8),

                // ---- Editor ----
                _SectionHeader(
                    title: _editingId == null ? 'New server' : 'Edit server'),
                _card(context, [
                  _field(
                    controller: _urlController,
                    label: 'Server URL',
                    hint: 'https://nas.local/dav',
                    keyboardType: TextInputType.url,
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_isPlainHttp) _plainHttpWarning(context),
                  _field(
                    controller: _userController,
                    label: 'Username (optional)',
                    hint: 'app-password user',
                  ),
                  _passwordField(context),
                  _field(
                    controller: _basePathController,
                    label: 'Base path',
                    hint: '/locker',
                  ),
                ]),
                const SizedBox(height: 12),
                _SectionHeader(title: 'Options'),
                _card(context, [
                  _formLabel(context, 'Direction'),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: InputDecorator(
                      decoration: _fieldDecoration().copyWith(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                      ),
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
                  ),
                  SwitchListTile(
                    title: const Text('Wi-Fi only',
                        style: TextStyle(fontFamily: 'ProductSans')),
                    subtitle: Text('Skip sync on mobile data',
                        style: _subStyle(context)),
                    value: _wifiOnly,
                    onChanged: (v) => setState(() => _wifiOnly = v),
                    activeThumbColor: context.accentColor,
                    contentPadding: EdgeInsets.zero,
                  ),
                ]),
                const SizedBox(height: 8),
                if (_editingActive)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle,
                            size: 16, color: context.accentColor),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'This is the active sync target.',
                            style: _subStyle(context)
                                .copyWith(color: context.accentColor),
                          ),
                        ),
                      ],
                    ),
                  ),
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
                            : const Text('Test',
                                style: TextStyle(fontFamily: 'ProductSans')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _save,
                        child: Text(_editingId == null ? 'Create' : 'Save',
                            style: const TextStyle(fontFamily: 'ProductSans')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ---- Sync ----
                _SectionHeader(title: 'Sync'),
                _card(context, [
                  SwitchListTile(
                    title: const Text('Enable server sync',
                        style: TextStyle(fontFamily: 'ProductSans')),
                    subtitle: Text(
                        'Master switch for Sync Now and background runs',
                        style: _subStyle(context)),
                    value: _masterEnabled,
                    onChanged: _activeId == null ? null : _setMasterEnabled,
                    activeThumbColor: context.accentColor,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Text(
                      'Push-only backs the vault up as encrypted blobs to your '
                      'server. Two-way also pulls remote changes and deletions '
                      'onto this device.',
                      style: _subStyle(context),
                    ),
                  ),
                  if (syncState.status == SyncStatus.error &&
                      syncState.error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                      child: _errorBanner(context, syncState.error!),
                    ),
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
                      label: Text(syncState.isSyncing ? 'Syncing…' : 'Sync Now',
                          style: const TextStyle(fontFamily: 'ProductSans')),
                      onPressed: syncState.isSyncing ||
                              _activeId == null ||
                              !_masterEnabled
                          ? null
                          : _syncNow,
                    ),
                  ),
                ]),
                if (_log.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _SectionHeader(title: 'History'),
                  _card(
                      context, _log.map((e) => _logTile(context, e)).toList()),
                ],
              ],
            ),
    );
  }

  void _seedFormNull() => _seedForm(null);

  Widget _profileCard(BuildContext context, SyncProfile p,
      {required bool isActive}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _seedForm(p)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(
            color: isActive
                ? context.accentColor.withValues(alpha: 0.08)
                : context.textPrimary.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive
                  ? context.accentColor.withValues(alpha: 0.5)
                  : context.borderColor,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.dns_outlined,
                  size: 22,
                  color: isActive ? context.accentColor : context.textTertiary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _hostOf(p.serverUrl),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontFamily: 'ProductSans',
                                fontWeight: FontWeight.w600,
                                color: context.textPrimary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          p.direction == SyncDirection.twoWay
                              ? 'Two-way'
                              : 'Push only',
                          style: _subStyle(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p.lastSyncedAt == null
                          ? (p.basePath.isEmpty ? '/locker' : p.basePath)
                          : 'Synced ${_formatDate(p.lastSyncedAt!)}',
                      style: _subStyle(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (isActive)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: context.accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('ACTIVE',
                      style: TextStyle(
                          fontFamily: 'ProductSans',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: context.accentColor)),
                )
              else
                IconButton(
                  tooltip: 'Set as active',
                  icon: Icon(Icons.radio_button_unchecked,
                      size: 20, color: context.textTertiary),
                  onPressed: () => _activate(p),
                ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert,
                    size: 20, color: context.textTertiary),
                itemBuilder: (_) => [
                  if (!isActive)
                    const PopupMenuItem(
                        value: 'activate', child: Text('Set as active')),
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
                onSelected: (v) {
                  switch (v) {
                    case 'activate':
                      _activate(p);
                      break;
                    case 'edit':
                      setState(() => _seedForm(p));
                      break;
                    case 'delete':
                      _confirmDelete(p);
                      break;
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyServersHint(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.textPrimary.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: context.borderColor, style: BorderStyle.solid),
        ),
        child: Column(
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 32, color: context.textTertiary),
            const SizedBox(height: 8),
            Text('No servers yet',
                style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontWeight: FontWeight.w600,
                    color: context.textSecondary)),
            const SizedBox(height: 4),
            Text(
              'Tap Add to configure a WebDAV server (NAS or cloud).',
              textAlign: TextAlign.center,
              style: _subStyle(context),
            ),
          ],
        ),
      );

  Widget _card(BuildContext context, List<Widget> children) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
        decoration: BoxDecoration(
          color: context.textPrimary.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );

  Widget _plainHttpWarning(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 4, bottom: 8),
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
                fontFamily: 'ProductSans',
                fontSize: 12,
                color: AppColors.error)),
      );

  TextStyle _subStyle(BuildContext context) => TextStyle(
        fontFamily: 'ProductSans',
        fontSize: 12,
        color: context.textTertiary,
      );

  Widget _formLabel(BuildContext context, String text) => Text(
        text,
        style: TextStyle(
            fontFamily: 'ProductSans',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.textTertiary),
      );

  InputDecoration _fieldDecoration({String? hint, Widget? suffixIcon}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
            fontFamily: 'ProductSans', fontSize: 13, color: context.textSecondary),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: context.textPrimary.withValues(alpha: 0.03),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.accentColor),
        ),
      );

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool obscure = false,
    TextInputType? keyboardType,
    void Function(String)? onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _formLabel(context, label),
            const SizedBox(height: 6),
            TextField(
              controller: controller,
              obscureText: obscure,
              keyboardType: keyboardType,
              decoration: _fieldDecoration(hint: hint),
              onChanged: (v) => onChanged?.call(v),
            ),
          ],
        ),
      );

  Widget _passwordField(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _formLabel(context, 'Password'),
            const SizedBox(height: 6),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: _fieldDecoration(
                hint: _editingId == null
                    ? 'app password'
                    : 'leave blank to keep current',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                ),
              ),
            ),
          ],
        ),
      );

  String _formatDate(DateTime d) {
    final local = d.toLocal();
    return '${local.day}/${local.month}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration? d) {
    if (d == null) return '—';
    if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds % 60}s';
    }
    return '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';
  }

  Widget _logTile(BuildContext context, _SyncLogEntry e) {
    final color = e.ok ? Colors.green : AppColors.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(e.ok ? Icons.check_circle_outline : Icons.error_outline,
              color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_formatDate(e.time)} — ${e.message}',
              style: TextStyle(
                  fontFamily: 'ProductSans',
                  fontSize: 12,
                  color: context.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Big status banner for the active profile's current run state.
class _HeroStatus extends StatelessWidget {
  const _HeroStatus({
    required this.state,
    required this.active,
    required this.masterEnabled,
  });

  final SyncState state;
  final SyncProfile? active;
  final bool masterEnabled;

  @override
  Widget build(BuildContext context) {
    // No active server configured yet.
    if (active == null) {
      return _shell(
        context,
        color: context.textTertiary,
        icon: Icons.cloud_off_outlined,
        children: [
          Text('No active server',
              style: TextStyle(
                  fontFamily: 'ProductSans',
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary)),
          Text('Add a server below, then set it active.', style: _sub(context)),
        ],
      );
    }

    final (label, color, icon) = switch (state.status) {
      SyncStatus.idle => (
          'Idle',
          context.textTertiary,
          Icons.cloud_queue_outlined
        ),
      SyncStatus.syncing => (
          'Syncing…',
          context.accentColor,
          Icons.cloud_sync_outlined
        ),
      SyncStatus.success => (
          'Up to date',
          Colors.green,
          Icons.cloud_done_outlined
        ),
      SyncStatus.error => ('Error', AppColors.error, Icons.error_outline),
    };

    final progress = state.progress;
    final showBar = state.isSyncing && progress != null && progress.total > 0;
    final pct =
        showBar ? (progress.completed / progress.total).clamp(0.0, 1.0) : 0.0;

    String? detail;
    if (state.isSyncing && progress != null && progress.total > 0) {
      detail =
          '${_phaseLabel(progress)} ${progress.completed}/${progress.total}';
    } else if (state.status == SyncStatus.success && state.message != null) {
      detail = state.message;
    } else if (active!.lastSyncedAt != null) {
      detail = 'Last sync ${_fmt(active!.lastSyncedAt!)}';
    }

    return _shell(
      context,
      color: color,
      icon: icon,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontFamily: 'ProductSans',
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary)),
            ),
            if (state.status == SyncStatus.success && !masterEnabled)
              _tag(context, 'Paused', context.textTertiary),
            if (active!.direction == SyncDirection.twoWay &&
                state.status != SyncStatus.error)
              _tag(context, 'Two-way', context.accentColor),
          ],
        ),
        if (detail != null) ...[
          const SizedBox(height: 2),
          Text(detail, style: _sub(context)),
        ],
        if (showBar) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: color.withValues(alpha: 0.15),
              color: color,
            ),
          ),
        ],
        const SizedBox(height: 2),
        Text(active!.serverUrl,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: _sub(context)),
      ],
    );
  }

  Widget _shell(BuildContext context,
      {required Color color,
      required IconData icon,
      required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(BuildContext context, String text, Color color) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(
                fontFamily: 'ProductSans',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color)),
      );

  TextStyle _sub(BuildContext context) => TextStyle(
        fontFamily: 'ProductSans',
        fontSize: 12,
        color: context.textTertiary,
      );

  static String _phaseLabel(SyncProgress p) => switch (p.phase) {
        SyncPhase.connecting => 'Connecting',
        SyncPhase.uploading => 'Uploading',
        SyncPhase.downloading => 'Downloading',
        SyncPhase.committing => 'Committing',
        SyncPhase.done => 'Done',
      };

  static String _fmt(DateTime d) {
    final local = d.toLocal();
    return '${local.day}/${local.month}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        children: [
          Text(title,
              style: TextStyle(
                  fontFamily: 'ProductSans',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: context.textTertiary)),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _SyncLogEntry {
  final DateTime time;
  final String message;
  final bool ok;
  const _SyncLogEntry(this.time, this.message, this.ok);
}
