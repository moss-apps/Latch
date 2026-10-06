import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/share_import_screen.dart';
import '../services/session_service.dart';
import '../services/share_intake_service.dart';

/// Opens the share review screen once the vault is unlocked and files are
/// waiting. Pending references live outside the provider scope, so they
/// survive the subtree recreation that happens on lock.
class ShareIntakeHost extends StatefulWidget {
  const ShareIntakeHost({super.key, required this.child});

  final Widget child;

  @override
  State<ShareIntakeHost> createState() => _ShareIntakeHostState();
}

class _ShareIntakeHostState extends State<ShareIntakeHost> {
  bool _routeOpen = false;

  @override
  void initState() {
    super.initState();
    ShareIntakeService.instance.addListener(_scheduleCheck);
    SessionService.instance.addListener(_scheduleCheck);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleCheck());
  }

  @override
  void dispose() {
    ShareIntakeService.instance.removeListener(_scheduleCheck);
    SessionService.instance.removeListener(_scheduleCheck);
    super.dispose();
  }

  void _scheduleCheck() {
    if (!mounted) return;
    scheduleMicrotask(_openIfNeeded);
  }

  void _openIfNeeded() {
    if (!mounted || _routeOpen) return;
    final intake = ShareIntakeService.instance;
    if (!SessionService.instance.isUnlocked ||
        !intake.hasPending ||
        intake.isDeferred) {
      return;
    }
    _routeOpen = true;
    Navigator.of(context, rootNavigator: true)
        .push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => const ShareImportScreen(),
          ),
        )
        .whenComplete(() {
      _routeOpen = false;
      _openIfNeeded();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
