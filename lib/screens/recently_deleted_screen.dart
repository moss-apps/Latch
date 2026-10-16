import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/deleted_vault_item.dart';
import '../models/vault_settings.dart';
import '../providers/note_providers.dart';
import '../providers/password_providers.dart';
import '../providers/recently_deleted_provider.dart';
import '../providers/vault_providers.dart';
import '../themes/app_colors.dart';
import '../utils/toast_utils.dart';

class RecentlyDeletedScreen extends ConsumerStatefulWidget {
  const RecentlyDeletedScreen({super.key});

  @override
  ConsumerState<RecentlyDeletedScreen> createState() =>
      _RecentlyDeletedScreenState();
}

class _RecentlyDeletedScreenState extends ConsumerState<RecentlyDeletedScreen> {
  bool _busy = false;
  bool get _decoy => ref.read(isDecoyModeProvider);

  void _refresh() {
    ref.invalidate(recentlyDeletedProvider);
    ref.invalidate(recentlyDeletedStorageProvider);
    ref.invalidate(vaultNotifierProvider);
    ref.invalidate(notesNotifierProvider);
    ref.invalidate(passwordsNotifierProvider);
    ref.invalidate(totalStorageProvider);
    ref.invalidate(albumsProvider);
    ref.invalidate(foldersProvider);
  }

  Future<bool> _confirmPermanent(int count) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('Delete permanently?'),
          content: Text(
              'Permanently delete $count item(s) from this device, including '
              'their thumbnails? This cannot be undone. Existing backups and retained '
              'WebDAV blobs are not erased.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error),
                child: const Text('Delete permanently')),
          ],
        ),
      ) ??
      false;

  Future<void> _run(Future<bool> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      final ok = await action();
      if (!mounted) return;
      _refresh();
      if (ok) {
        ToastUtils.showSuccess(success);
      } else {
        ToastUtils.showWarning(
            'Could not finish. A file operation may be running; retry cleanup here.');
      }
    } catch (_) {
      if (mounted) {
        ToastUtils.showError(
            'Recovery storage could not be read. Try again after unlocking.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseRetention(VaultSettings settings) async {
    final days = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
            scrollable: true,
            title: const Text('Keep deleted items for'),
            content: RadioGroup<int>(
              groupValue: settings.recentlyDeletedRetentionDays,
              onChanged: (value) => Navigator.pop(context, value),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final days in VaultSettings.retentionOptions)
                  RadioListTile<int>(
                      title:
                          Text(days == 0 ? 'Delete immediately' : '$days days'),
                      value: days),
              ]),
            )));
    if (days == null ||
        !mounted ||
        days == settings.recentlyDeletedRetentionDays) {
      return;
    }
    if (days == 0) {
      final agreed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                scrollable: true,
                title: const Text('Turn off recovery for future deletions?'),
                content: const Text(
                    'New deletions will be permanent. Items already in '
                    'Recently Deleted keep their existing expiry dates.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete immediately')),
                ],
              ));
      if (agreed != true || !mounted) return;
    }
    await ref
        .read(vaultServiceProvider)
        .updateSettings(settings.copyWith(recentlyDeletedRetentionDays: days));
    if (mounted) ref.invalidate(vaultSettingsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(recentlyDeletedProvider);
    final settings = ref.watch(vaultSettingsProvider);
    final storage = ref.watch(recentlyDeletedStorageProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Recently Deleted'), actions: [
        IconButton(
            tooltip: 'Retry cleanup',
            icon: const Icon(Icons.refresh),
            onPressed: _busy
                ? null
                : () => _run(
                    () => ref
                        .read(vaultServiceProvider)
                        .recentlyDeleted
                        .maintain(isDecoy: _decoy),
                    'Cleanup complete')),
        PopupMenuButton<String>(
          tooltip: 'Recovery actions',
          enabled: !_busy,
          onSelected: (_) async {
            final current = items.asData?.value ?? [];
            if (current.isEmpty ||
                !await _confirmPermanent(current.length) ||
                !mounted) {
              return;
            }
            await _run(() async {
              var ok = true;
              final service = ref.read(vaultServiceProvider).recentlyDeleted;
              final decoy = _decoy;
              for (final item in current) {
                ok = await service.permanentlyDelete(item.file.id,
                        isDecoy: decoy) &&
                    ok;
              }
              return ok;
            }, 'Recently Deleted emptied');
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
                value: 'empty', child: Text('Empty Recently Deleted'))
          ],
        ),
      ]),
      body: SafeArea(
          child: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text(
                      'Recently Deleted could not be loaded. No recovery records were overwritten.'),
                  TextButton(
                      onPressed: _refresh, child: const Text('Try again')),
                ]))),
        data: (entries) {
          final sorted = [...entries]
            ..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
          return CustomScrollView(slivers: [
            SliverToBoxAdapter(
                child: Column(children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Text(
                      'Local recovery only. Deleted items still use device storage. '
                      'Expiry cleanup runs while Latch is unlocked and on the next unlock or resume. '
                      'New backups exclude these items. WebDAV receives a deletion on the next sync; '
                      'restoring makes the item eligible to sync again.',
                      style: TextStyle(
                          color: context.textSecondary, height: 1.5))),
              if (storage.asData case final data?)
                Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Text(
                        '${_formatBytes(data.value)} retained (payloads and thumbnails)')),
              if (settings.asData case final data?)
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Retention for future deletions'),
                  subtitle: Text(data.value.recentlyDeletedRetentionDays == 0
                      ? 'Delete immediately · existing expiry dates stay unchanged'
                      : '${data.value.recentlyDeletedRetentionDays} days · existing expiry dates stay unchanged'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : () => _chooseRetention(data.value),
                ),
              const Divider(),
              if (_busy) const LinearProgressIndicator(),
              if (sorted.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                        'No recently deleted items. Your active vault is unchanged.')),
            ])),
            SliverList.builder(
                itemCount: sorted.length,
                itemBuilder: (context, index) {
                  final item = sorted[index];
                  return ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: Text(item.file.originalName),
                    subtitle: Text(item.stage == DeletionStage.trashed
                        ? 'Expires ${_date(item.expiresAt.toLocal())}'
                        : '${item.stage == DeletionStage.purging ? 'Permanent deletion' : 'Recovery operation'} pending · retry cleanup'),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Actions for ${item.file.originalName}',
                      enabled: !_busy,
                      itemBuilder: (_) => [
                        if (item.canRestore(DateTime.now()))
                          const PopupMenuItem(
                              value: 'restore', child: Text('Restore')),
                        if (item.stage != DeletionStage.restoring)
                          const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete permanently')),
                        if (item.stage == DeletionStage.restoring)
                          const PopupMenuItem(
                              value: 'retry', child: Text('Retry restore')),
                      ],
                      onSelected: (action) async {
                        final service =
                            ref.read(vaultServiceProvider).recentlyDeleted;
                        final decoy = _decoy;
                        if (action == 'restore') {
                          await _run(
                              () =>
                                  service.restore(item.file.id, isDecoy: decoy),
                              'Item restored');
                        } else if (action == 'retry') {
                          await _run(() => service.maintain(isDecoy: decoy),
                              'Recovery complete');
                        } else if (await _confirmPermanent(1) && mounted) {
                          await _run(
                              () => service.permanentlyDelete(item.file.id,
                                  isDecoy: decoy),
                              'Item permanently deleted');
                        }
                      },
                    ),
                  );
                }),
            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ]);
        },
      )),
    );
  }

  String _date(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  String _formatBytes(int bytes) => bytes < 1024
      ? '$bytes B'
      : bytes < 1024 * 1024
          ? '${(bytes / 1024).toStringAsFixed(1)} KB'
          : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
