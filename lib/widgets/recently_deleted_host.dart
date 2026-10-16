import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/deleted_vault_item.dart';
import '../providers/note_providers.dart';
import '../providers/password_providers.dart';
import '../providers/recently_deleted_provider.dart';
import '../providers/vault_providers.dart';
import '../services/decoy_service.dart';
import '../services/diagnostics.dart';
import '../services/recently_deleted_service.dart';
import '../services/session_service.dart';

/// Runs only in the disposable protected session. OS background execution is
/// not assumed; expiry runs while unlocked and again on resume/unlock.
class RecentlyDeletedHost extends ConsumerStatefulWidget {
  const RecentlyDeletedHost({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<RecentlyDeletedHost> createState() =>
      _RecentlyDeletedHostState();
}

class _RecentlyDeletedHostState extends ConsumerState<RecentlyDeletedHost>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _running = false;
  late final RecentlyDeletedService _recovery;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SessionService.instance.addListener(_schedule);
    _recovery = ref.read(vaultServiceProvider).recentlyDeleted;
    _recovery.addListener(_schedule);
    WidgetsBinding.instance.addPostFrameCallback((_) => _schedule());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    SessionService.instance.removeListener(_schedule);
    _recovery.removeListener(_schedule);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _schedule();
  }

  void _schedule() {
    if (!mounted || _running) return;
    _timer?.cancel();
    if (SessionService.instance.isUnlocked) {
      _timer = Timer(Duration.zero, _maintain);
    }
  }

  Future<void> _maintain() async {
    if (!mounted || _running || !SessionService.instance.isUnlocked) return;
    _running = true;
    try {
      final vault = ref.read(vaultServiceProvider);
      final decoy = DecoyService.instance.isDecoyModeActive;
      final before = await vault.store.loadDeletedItems(isDecoy: decoy);
      var retry = !await vault.recentlyDeleted.maintain(isDecoy: decoy);
      if (!mounted || !SessionService.instance.isUnlocked) return;
      if (before.isNotEmpty) {
        ref.invalidate(recentlyDeletedProvider);
        ref.invalidate(vaultNotifierProvider);
        ref.invalidate(notesNotifierProvider);
        ref.invalidate(passwordsNotifierProvider);
        ref.invalidate(totalStorageProvider);
      }
      final items = await vault.store.loadDeletedItems(isDecoy: decoy);
      DateTime? next;
      for (final item in items) {
        if (item.stage != DeletionStage.trashed) retry = true;
        if (next == null || item.expiresAt.isBefore(next)) {
          next = item.expiresAt;
        }
      }
      if (!mounted) return;
      if (retry || (next != null && !DateTime.now().isBefore(next))) {
        _timer = Timer(const Duration(minutes: 1), _maintain);
      } else if (next != null) {
        final delay = next.difference(DateTime.now());
        _timer = Timer(
            delay > const Duration(days: 1) ? const Duration(days: 1) : delay,
            _maintain);
      }
    } catch (error, stack) {
      Diagnostics.failure('recovery.maintenance', error, stack);
      if (mounted) _timer = Timer(const Duration(minutes: 1), _maintain);
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
