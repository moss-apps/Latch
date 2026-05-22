import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/auto_kill_service.dart';
import '../services/permission_service.dart';

/// A warning banner that displays when "All Files Access" permission is not granted.
/// This permission is required on Android 11+ for the app to hide files.
class PermissionWarningBanner extends StatefulWidget {
  /// Callback when the permission status changes
  final VoidCallback? onPermissionChanged;

  const PermissionWarningBanner({
    super.key,
    this.onPermissionChanged,
  });

  @override
  State<PermissionWarningBanner> createState() =>
      _PermissionWarningBannerState();
}

class _PermissionWarningBannerState extends State<PermissionWarningBanner>
    with WidgetsBindingObserver {
  bool _hasPermission = true;
  bool _isLoading = true;
  bool _isDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check permission when app resumes (user might have granted it in settings)
    if (state == AppLifecycleState.resumed) {
      _checkPermission();
    }
  }

  Future<void> _checkPermission() async {
    if (!Platform.isAndroid) {
      setState(() {
        _hasPermission = true;
        _isLoading = false;
      });
      return;
    }

    final hasAccess = await PermissionService.instance.hasAllFilesAccess();
    if (mounted) {
      final previousState = _hasPermission;
      setState(() {
        _hasPermission = hasAccess;
        _isLoading = false;
      });

      // Notify parent if permission state changed
      if (previousState != hasAccess) {
        widget.onPermissionChanged?.call();
      }
    }
  }

  Future<void> _requestPermission() async {
    final granted = await PermissionService.instance.requestAllFilesAccess();
    if (mounted) {
      setState(() {
        _hasPermission = granted;
      });
      if (granted) {
        widget.onPermissionChanged?.call();
      }
    }
  }

  Future<void> _openSettings() async {
    await AutoKillService.runSafe(() => openAppSettings());
  }

  @override
  Widget build(BuildContext context) {
    // Don't show on non-Android platforms
    if (!Platform.isAndroid) return const SizedBox.shrink();

    // Don't show while loading
    if (_isLoading) return const SizedBox.shrink();

    // Don't show if permission is granted or dismissed
    if (_hasPermission || _isDismissed) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.orange.shade700,
            Colors.orange.shade800,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'All Files Access Required',
                          style: TextStyle(
                            fontFamily: 'ProductSans',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'To hide files from other apps, Latch needs permission to access all files on your device.',
                          style: TextStyle(
                            fontFamily: 'ProductSans',
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.9),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Dismiss button
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isDismissed = true;
                      });
                    },
                    child: Icon(
                      Icons.close,
                      color: Colors.white.withValues(alpha: 0.7),
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openSettings,
                      icon: const Icon(Icons.settings, size: 18),
                      label: const Text('Open Settings'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _requestPermission,
                      icon: const Icon(Icons.security, size: 18),
                      label: const Text('Grant Access'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.orange.shade800,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact version of the permission warning for use in app bars or smaller spaces
class CompactPermissionWarning extends StatefulWidget {
  final VoidCallback? onTap;

  const CompactPermissionWarning({
    super.key,
    this.onTap,
  });

  @override
  State<CompactPermissionWarning> createState() =>
      _CompactPermissionWarningState();
}

class _CompactPermissionWarningState extends State<CompactPermissionWarning>
    with WidgetsBindingObserver {
  bool _hasPermission = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermission();
    }
  }

  Future<void> _checkPermission() async {
    if (!Platform.isAndroid) {
      setState(() {
        _hasPermission = true;
        _isLoading = false;
      });
      return;
    }

    final hasAccess = await PermissionService.instance.hasAllFilesAccess();
    if (mounted) {
      setState(() {
        _hasPermission = hasAccess;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid || _isLoading || _hasPermission) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: widget.onTap ??
          () => AutoKillService.runSafe(() => openAppSettings()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.shade700,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 4),
            const Text(
              'Permission needed',
              style: TextStyle(
                fontFamily: 'ProductSans',
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
