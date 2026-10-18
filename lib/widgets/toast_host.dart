import 'dart:async';

import 'package:flutter/material.dart';

/// Payload for a single toast message rendered by [ToastHost].
class ToastMessage {
  const ToastMessage({
    required this.message,
    this.backgroundColor,
    this.duration = const Duration(seconds: 2),
  });

  final String message;
  final Color? backgroundColor;
  final Duration duration;
}

/// Shows app-wide toasts above every route without using
/// [ScaffoldMessenger].
///
/// Mount once through `MaterialApp.builder`:
///
/// ```dart
/// builder: (context, child) => ToastHost(child: child),
/// ```
///
/// Messages enter with a short fade + slide and leave the same way, driven by
/// paint-only properties (no layout passes), so a toast never triggers a
/// rebuild or relayout of the screen underneath. A new message arriving while
/// one is visible slides the current toast out and takes its place.
class ToastHost extends StatefulWidget {
  const ToastHost({super.key, required this.child});

  /// The app content the toast is layered on top of.
  final Widget child;

  static _ToastHostState? _instance;

  /// Shows a toast. No-op when the host has not been mounted yet.
  static void show(ToastMessage message) => _instance?._show(message);

  @override
  State<ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<ToastHost>
    with SingleTickerProviderStateMixin {
  static const Duration _enterDuration = Duration(milliseconds: 260);
  static const Duration _exitDuration = Duration(milliseconds: 200);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _enterDuration,
  )..addStatusListener(_handleAnimationStatus);

  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  ToastMessage? _current;
  ToastMessage? _pending;
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    ToastHost._instance = this;
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _curve.dispose();
    _controller.dispose();
    if (identical(ToastHost._instance, this)) {
      ToastHost._instance = null;
    }
    super.dispose();
  }

  void _show(ToastMessage message) {
    _pending = message;
    if (_controller.isDismissed) {
      _promotePending();
    } else {
      _beginExit();
    }
  }

  /// Makes the pending message visible and animates it in.
  void _promotePending() {
    final message = _pending;
    if (message == null) return;
    _pending = null;
    _controller.duration = _enterDuration;
    setState(() => _current = message);
    _controller.forward();
  }

  /// Animates the visible toast out; a pending message takes over once the
  /// exit finishes.
  void _beginExit() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;
    if (_controller.isDismissed ||
        _controller.status == AnimationStatus.reverse) {
      return;
    }
    _controller.duration = _exitDuration;
    _controller.reverse();
  }

  void _handleAnimationStatus(AnimationStatus status) {
    switch (status) {
      case AnimationStatus.completed:
        if (_pending != null) {
          _beginExit();
        } else {
          _scheduleAutoDismiss();
        }
      case AnimationStatus.dismissed:
        if (_pending != null) {
          _promotePending();
        } else if (_current != null) {
          setState(() => _current = null);
        }
      case AnimationStatus.forward:
      case AnimationStatus.reverse:
        break;
    }
  }

  void _scheduleAutoDismiss() {
    _autoDismissTimer?.cancel();
    final message = _current;
    if (message == null) return;
    _autoDismissTimer = Timer(message.duration, () {
      if (mounted) {
        _beginExit();
      }
    });
  }

  double _bottomInset(BuildContext context) {
    final media = MediaQuery.of(context);
    return media.padding.bottom + media.viewInsets.bottom + 12;
  }

  @override
  Widget build(BuildContext context) {
    final toast = _current;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (toast != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: _bottomInset(context),
            child: Center(
              heightFactor: 1.0,
              child: AnimatedBuilder(
                animation: _curve,
                child: RepaintBoundary(
                  child: Semantics(
                    container: true,
                    liveRegion: true,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: _ToastCard(message: toast),
                    ),
                  ),
                ),
                builder: (context, child) => Opacity(
                  opacity: _curve.value,
                  child: FractionalTranslation(
                    translation: Offset(0, (1 - _curve.value) * 0.6),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({required this.message});

  final ToastMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = message.backgroundColor ?? scheme.inverseSurface;
    final foreground = message.backgroundColor == null
        ? scheme.onInverseSurface
        : (ThemeData.estimateBrightnessForColor(background) == Brightness.dark
            ? Colors.white
            : Colors.black87);
    return Material(
      color: background,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shadowColor: Colors.black45,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          message.message,
          style: TextStyle(
            color: foreground,
            fontFamily: 'GoogleSansFlex',
            fontSize: 14,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}
