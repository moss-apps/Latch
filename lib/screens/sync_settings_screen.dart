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
                child: const Text('Done'),
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
            title: const Text('Remove server?'),
            content: Text(
              'Delete the profile for ${_hostOf(p.serverUrl)}? '
              'Encrypted blobs already on the server are left in place.',
              style:
                  _subStyle(ctx).copyWith(color: context.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
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
      appBar: AppBar(title: const Text('Server Sync')),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: context.accentColor),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                ..._statusChildren(syncState, active),
                const SizedBox(height: 24),
                ..._serversChildren(profiles),
                const SizedBox(height: 24),
                ..._syncChildren(syncState),
                if (_log.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  ..._historyChildren(),
                ],
              ],
            ),
    );
  }

  // ---- builders ----

  Widget _sectionTitle(String title, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: context.accentColor,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  TextStyle _subStyle(BuildContext context) => TextStyle(
        fontSize: 12,
        color: context.textTertiary,
      );

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
        style: _subStyle(context),
      ),
      trailing: Icon(Icons.chevron_right, color: context.textTertiary),
      onTap: onTap,
    );
  }

  List<Widget> _statusChildren(SyncState syncState, SyncProfile? active) {
    // No active server configured yet.
    if (active == null) {
      return [
        _sectionTitle('Status'),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading:
              Icon(Icons.cloud_off_outlined, color: context.textTertiary),
          title: const Text('No active server'),
          subtitle: Text(
            'Add a server to get started — it becomes the sync target.',
            style: _subStyle(context),
          ),
        ),
      ];
    }

    final (label, color, icon) = switch (syncState.status) {
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

    final progress = syncState.progress;
    final showBar =
        syncState.isSyncing && progress != null && progress.total > 0;
    final pct =
        showBar ? (progress.completed / progress.total).clamp(0.0, 1.0) : 0.0;

    String? detail;
    if (syncState.isSyncing && progress != null && progress.total > 0) {
      detail =
          '${_phaseLabel(progress)} ${progress.completed}/${progress.total}';
    } else if (syncState.status == SyncStatus.success &&
        syncState.message != null) {
      detail = syncState.message;
    } else if (active.lastSyncedAt != null) {
      detail = 'Last sync ${_formatDate(active.lastSyncedAt!)}';
    }

    return [
      _sectionTitle('Status'),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: color),
        title: Row(
          children: [
            Flexible(child: Text(label)),
            if (syncState.status == SyncStatus.success && !_masterEnabled)
              _tag('Paused', context.textTertiary),
            if (active.direction == SyncDirection.twoWay &&
                syncState.status != SyncStatus.error)
              _tag('Two-way', context.accentColor),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (detail != null) Text(detail, style: _subStyle(context)),
            Text(
              active.serverUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _subStyle(context),
            ),
          ],
        ),
      ),
      if (showBar)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
            backgroundColor: color.withValues(alpha: 0.15),
            color: color,
          ),
        ),
    ];
  }

  Widget _tag(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  List<Widget> _serversChildren(List<SyncProfile> profiles) {
    final addButton = IconButton(
      tooltip: 'Add server',
      icon: Icon(Icons.add, size: 20, color: context.accentColor),
      onPressed: () => _openEditor(),
    );

    if (profiles.isEmpty) {
      return [
        _sectionTitle('Servers', trailing: addButton),
        Text(
          'Connect to any WebDAV server — a NAS at home '
          'or a cloud provider.',
          style: _subStyle(context),
        ),
        _tile(
          icon: Icons.add,
          title: 'Add server',
          subtitle: 'WebDAV — works with most NAS boxes and cloud providers',
          onTap: () => _openEditor(),
        ),
      ];
    }

    return [
      _sectionTitle('Servers', trailing: addButton),
      ...profiles.map((p) => _profileTile(p, isActive: p.id == _activeId)),
    ];
  }

  Widget _profileTile(SyncProfile p, {required bool isActive}) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.dns_outlined,
        color: isActive ? context.accentColor : context.textTertiary,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              _hostOf(p.serverUrl),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color:
                    isActive ? context.accentColor : context.textPrimary,
              ),
            ),
          ),
          if (isActive) _tag('ACTIVE', context.accentColor),
        ],
      ),
      subtitle: Text(
        '${p.direction == SyncDirection.twoWay ? 'Two-way' : 'Backup'} · '
        '${p.lastSyncedAt == null
            ? (p.basePath.isEmpty ? '/locker' : p.basePath)
            : 'Synced ${_formatDate(p.lastSyncedAt!)}'}',
        style: _subStyle(context),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        icon: Icon(Icons.more_vert, size: 20, color: context.textTertiary),
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
      onTap: () => _openEditor(profile: p),
    );
  }

  List<Widget> _syncChildren(SyncState syncState) {
    return [
      _sectionTitle('Sync'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Enable server sync'),
        subtitle: Text(
          'Master switch for Sync Now and background runs',
          style: _subStyle(context),
        ),
        value: _masterEnabled,
        onChanged: _activeId == null ? null : _setMasterEnabled,
        activeThumbColor: context.accentColor,
      ),
      Text(
        'Backup pushes the vault as encrypted blobs to your '
        'server. Two-way also pulls remote changes and deletions '
        'onto this device.',
        style: _subStyle(context),
      ),
      if (syncState.status == SyncStatus.error && syncState.error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            syncState.error!,
            style: TextStyle(fontSize: 12, color: AppColors.error),
          ),
        ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          icon: syncState.isSyncing
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.backgroundColor,
                  ),
                )
              : const Icon(Icons.sync),
          label: Text(syncState.isSyncing ? 'Syncing…' : 'Sync Now'),
          onPressed: syncState.isSyncing ||
                  _activeId == null ||
                  !_masterEnabled
              ? null
              : _syncNow,
        ),
      ),
    ];
  }

  List<Widget> _historyChildren() {
    return [
      _sectionTitle('History'),
      ..._log.map((e) {
        final color = e.ok ? Colors.green : AppColors.error;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: Icon(
            e.ok ? Icons.check_circle_outline : Icons.error_outline,
            color: color,
            size: 18,
          ),
          title: Text(
            e.message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: context.textPrimary),
          ),
          subtitle: Text(_formatDate(e.time), style: _subStyle(context)),
        );
      }),
    ];
  }

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

  static String _phaseLabel(SyncProgress p) => switch (p.phase) {
        SyncPhase.connecting => 'Connecting',
        SyncPhase.uploading => 'Uploading',
        SyncPhase.downloading => 'Downloading',
        SyncPhase.committing => 'Committing',
        SyncPhase.done => 'Done',
      };
}

class _SyncLogEntry {
  final DateTime time;
  final String message;
  final bool ok;
  const _SyncLogEntry(this.time, this.message, this.ok);
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
                          color: _direction == SyncDirection.pushOnly
                              ? context.accentColor
                              : context.textSecondary)),
                ),
                ButtonSegment(
                  value: SyncDirection.twoWay,
                  label: Text('Two-way',
                      style: TextStyle(
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
              title: const Text('Wi-Fi only'),
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
                    label: const Text('Test'),
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
                        : Text(isNew ? 'Add server' : 'Save'),
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
          style:
              TextStyle(fontSize: 12, color: AppColors.error),
        ),
      );

  TextStyle _subStyle(BuildContext context) => TextStyle(
        fontSize: 12,
        color: context.textTertiary,
      );

  Widget _formLabel(BuildContext context, String text) => Text(
        text,
        style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.textTertiary),
      );

  InputDecoration _fieldDecoration({String? hint, Widget? suffixIcon}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
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
