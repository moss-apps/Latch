import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/sync_profile.dart';
import '../providers/sync_provider.dart';
import '../providers/vault_providers.dart';
import '../services/remote/server_errors.dart';
import '../services/remote/webdav_store.dart';
import '../services/sync_profile_service.dart';
import '../services/sync_service.dart' show SyncPhase, SyncProgress;
import '../themes/app_colors.dart';

/// Connection settings + sync status for the local-server sync feature
/// (docs/local_server_sync.md). Supports multiple profiles; exactly one is
/// "active" (the sync target), held in vault settings as [syncProfileId].
/// Adding/editing a server happens in [_ServerSheet], a focused bottom sheet.
class SyncSettingsScreen extends ConsumerStatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  ConsumerState<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends ConsumerState<SyncSettingsScreen> {
  String? _activeId;
  bool _masterEnabled = false;

  bool _loading = true;
  final List<_SyncLogEntry> _log = [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
    ref.listen<SyncState>(syncProvider, _onSyncStateChanged);
  }

  /// One-shot load of settings + profiles. Reactive updates afterwards come
  // from watching the providers in [build].
  Future<void> _bootstrap() async {
    final settings = await ref.read(vaultServiceProvider).getSettings();
    _activeId = settings.syncProfileId;
    _masterEnabled = settings.syncEnabled;
    if (mounted) setState(() => _loading = false);
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

  void _openEditor({SyncProfile? profile}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ServerSheet(
        profile: profile,
        onSave: _saveFromSheet,
      ),
    );
  }

  /// Persists the profile (and password when given). New profiles auto-activate
  /// so sync works out of the box. Returns whether the sheet may close.
  Future<bool> _saveFromSheet(
      SyncProfile profile, String password, bool isNew) async {
    try {
      await SyncProfileService.instance.saveProfile(profile);
      if (password.isNotEmpty) {
        await SyncProfileService.instance.savePassword(profile.id, password);
      }
      if (isNew || _activeId == null) {
        _activeId = profile.id;
        _masterEnabled = true;
        await _persistActivation(profile.id, enabled: true);
      }
      ref.invalidate(vaultSettingsProvider);
      ref.invalidate(syncProfilesProvider);
      if (mounted) {
        setState(() {});
        _snack(isNew
            ? 'Server added and activated'
            : 'Saved');
      }
      return true;
    } catch (_) {
      if (mounted) _snack('Couldn\'t save — try again');
      return false;
    }
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
    if (_activeId == p.id) {
      _activeId = null;
      final s = await ref.read(vaultServiceProvider).getSettings();
      await ref
          .read(vaultServiceProvider)
          .updateSettings(s.copyWith(syncProfileId: null));
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

                // ---- Servers ----
                if (profiles.isEmpty)
                  _emptyServersHint(context)
                else ...[
                  _SectionHeader(
                    title: 'Servers',
                    trailing: IconButton(
                      tooltip: 'Add server',
                      icon: Icon(Icons.add, size: 20, color: context.accentColor),
                      onPressed: () => _openEditor(),
                    ),
                  ),
                  ...profiles.map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _profileCard(context, p,
                            isActive: p.id == _activeId),
                      )),
                ],
                const SizedBox(height: 12),

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
                      'Backup pushes the vault as encrypted blobs to your '
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

  Widget _profileCard(BuildContext context, SyncProfile p,
      {required bool isActive}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openEditor(profile: p),
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
                              : 'Backup',
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
                      _openEditor(profile: p);
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
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: context.textPrimary.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: context.borderColor, style: BorderStyle.solid),
        ),
        child: Column(
          children: [
            Icon(Icons.cloud_outlined,
                size: 32, color: context.textTertiary),
            const SizedBox(height: 10),
            Text('No servers yet',
                style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontWeight: FontWeight.w600,
                    color: context.textSecondary)),
            const SizedBox(height: 4),
            Text(
              'Connect to any WebDAV server — a NAS at home '
              'or a cloud provider.',
              textAlign: TextAlign.center,
              style: _subStyle(context),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add server',
                  style: TextStyle(fontFamily: 'ProductSans')),
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

/// Focused add/edit form shown as a bottom sheet. Owns all field state;
/// persistence goes through [onSave].
class _ServerSheet extends StatefulWidget {
  const _ServerSheet({required this.profile, required this.onSave});

  final SyncProfile? profile;
  final Future<bool> Function(
      SyncProfile profile, String password, bool isNew) onSave;

  @override
  State<_ServerSheet> createState() => _ServerSheetState();
}

class _ServerSheetState extends State<_ServerSheet> {
  late final TextEditingController _urlController =
      TextEditingController(text: widget.profile?.serverUrl ?? '');
  late final TextEditingController _userController =
      TextEditingController(text: widget.profile?.username ?? '');
  final _passwordController = TextEditingController();
  late final TextEditingController _basePathController = TextEditingController(
      text: widget.profile?.basePath.isEmpty == true
          ? '/locker'
          : (widget.profile?.basePath ?? '/locker'));

  late SyncDirection _direction =
      widget.profile?.direction ?? SyncDirection.pushOnly;
  late bool _wifiOnly = widget.profile?.wifiOnly ?? true;

  bool _obscurePassword = true;
  bool _isTesting = false;
  bool _isSaving = false;
  String? _urlError;

  bool get _isPlainHttp =>
      _urlController.text.trim().toLowerCase().startsWith('http://');

  @override
  void dispose() {
    _urlController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    _basePathController.dispose();
    super.dispose();
  }

  bool _validateUrl() {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _urlError = 'Server URL is required');
      return false;
    }
    if (Uri.tryParse(url)?.host.isEmpty != false) {
      setState(() => _urlError = 'Enter a full URL, e.g. https://nas.local/dav');
      return false;
    }
    if (_urlError != null) setState(() => _urlError = null);
    return true;
  }

  Future<void> _testConnection() async {
    if (!_validateUrl()) return;
    setState(() => _isTesting = true);
    try {
      final password = _passwordController.text.isNotEmpty
          ? _passwordController.text
          : (widget.profile == null
              ? ''
              : await SyncProfileService.instance
                      .getPassword(widget.profile!.id) ??
                  '');
      final store = WebDAVStore(
        baseUrl: _urlController.text.trim(),
        username: _userController.text.trim(),
        password: password,
        basePath: _basePathController.text.trim().isEmpty
            ? '/locker'
            : _basePathController.text.trim(),
      );
      await store.testConnection();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connected ✓')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(describeServerError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _save() async {
    if (!_validateUrl()) return;
    setState(() => _isSaving = true);
    final profile = SyncProfile(
      id: widget.profile?.id ?? const Uuid().v4(),
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
    final ok = await widget.onSave(
        profile, _passwordController.text, widget.profile == null);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.profile == null;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isNew ? 'Add server' : 'Edit server',
              style: TextStyle(
                  fontFamily: 'ProductSans',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              isNew
                  ? 'WebDAV — works with most NAS boxes and cloud providers.'
                  : _hostOf(widget.profile!.serverUrl),
              style: _subStyle(context),
            ),
            const SizedBox(height: 16),
            _field(
              controller: _urlController,
              label: 'Server URL',
              hint: 'https://nas.local/dav',
              keyboardType: TextInputType.url,
              errorText: _urlError,
              onChanged: (_) {
                if (_urlError != null) setState(() => _urlError = null);
                setState(() {});
              },
            ),
            if (_isPlainHttp) ...[
              _plainHttpWarning(context),
              const SizedBox(height: 12),
            ],
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
            _formLabel(context, 'Direction'),
            const SizedBox(height: 6),
            SegmentedButton<SyncDirection>(
              segments: [
                ButtonSegment(
                  value: SyncDirection.pushOnly,
                  label: Text('Backup',
                      style: TextStyle(
                          fontFamily: 'ProductSans',
                          color: _direction == SyncDirection.pushOnly
                              ? context.accentColor
                              : context.textSecondary)),
                ),
                ButtonSegment(
                  value: SyncDirection.twoWay,
                  label: Text('Two-way',
                      style: TextStyle(
                          fontFamily: 'ProductSans',
                          color: _direction == SyncDirection.twoWay
                              ? context.accentColor
                              : context.textSecondary)),
                ),
              ],
              selected: {_direction},
              showSelectedIcon: false,
              onSelectionChanged: (s) =>
                  setState(() => _direction = s.first),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Wi-Fi only',
                  style: TextStyle(fontFamily: 'ProductSans')),
              subtitle:
                  Text('Skip sync on mobile data', style: _subStyle(context)),
              value: _wifiOnly,
              onChanged: (v) => setState(() => _wifiOnly = v),
              activeThumbColor: context.accentColor,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isTesting || _isSaving ? null : _testConnection,
                    icon: _isTesting
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.accentColor),
                          )
                        : const Icon(Icons.network_check, size: 18),
                    label: const Text('Test',
                        style: TextStyle(fontFamily: 'ProductSans')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.backgroundColor),
                          )
                        : Text(isNew ? 'Add server' : 'Save',
                            style:
                                const TextStyle(fontFamily: 'ProductSans')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _hostOf(String url) {
    final u = Uri.tryParse(url);
    return u?.host.isNotEmpty == true ? u!.host : url;
  }

  Widget _plainHttpWarning(BuildContext context) => Container(
        width: double.infinity,
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
            fontFamily: 'ProductSans',
            fontSize: 13,
            color: context.textSecondary),
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
    String? errorText,
    void Function(String)? onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _formLabel(context, label),
            const SizedBox(height: 6),
            TextField(
              controller: controller,
              obscureText: obscure,
              keyboardType: keyboardType,
              decoration:
                  _fieldDecoration(hint: hint).copyWith(errorText: errorText),
              onChanged: (v) => onChanged?.call(v),
            ),
          ],
        ),
      );

  Widget _passwordField(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _formLabel(context, 'Password'),
            const SizedBox(height: 6),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: _fieldDecoration(
                hint: widget.profile == null
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
          Text('Add a server to get started — it becomes the sync target.',
              style: _sub(context)),
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
