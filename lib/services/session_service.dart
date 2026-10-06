import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/vault_settings.dart';
import 'session_cleanup.dart';

class SessionService extends ChangeNotifier {
  SessionService({Future<void> Function()? onLock, DateTime Function()? now})
      : _onLock = onLock ?? (() async {}),
        _now = now ?? DateTime.now;

  static final instance = SessionService(onLock: clearSensitiveSession);

  final Future<void> Function() _onLock;
  final DateTime Function() _now;
  VaultSettings _settings = const VaultSettings();
  bool isUnlocked = false;
  bool hasAuthenticated = false;
  int generation = 0;
  bool _foreground = true;
  bool isObscured = false;
  DateTime? _lastActivity;
  DateTime? _backgroundAt;
  Timer? _timer;
  Future<void> _cleanup = Future.value();
  bool _cleanupPending = false;
  bool _cleanupFailed = false;
  final Set<SystemInteraction> _interactions = {};

  bool get hasSystemInteraction => _interactions.isNotEmpty;
  Future<void> get readyToAuthenticate => _cleanup;

  void configure(VaultSettings settings) {
    _settings = settings;
    _schedule();
  }

  void unlock() {
    if (_cleanupPending || _cleanupFailed) {
      throw StateError('Session cleanup must finish before unlocking');
    }
    isUnlocked = true;
    hasAuthenticated = true;
    generation++;
    _backgroundAt = _foreground ? null : _now();
    _lastActivity = _now();
    _schedule();
    notifyListeners();
  }

  Future<void> lock() {
    if (!isUnlocked) return _cleanup;
    isUnlocked = false;
    generation++;
    _timer?.cancel();
    // Evict keys before yielding to navigation or pending work.
    _startCleanup();
    for (final interaction in _interactions.toList()) {
      interaction._release();
    }
    notifyListeners();
    return _cleanup;
  }

  Future<void> retryCleanup() {
    if (isUnlocked) throw StateError('Cannot clean an unlocked session');
    if (!_cleanupPending) _startCleanup();
    return _cleanup;
  }

  void _startCleanup() {
    _cleanupPending = true;
    _cleanup = Future.sync(_onLock).then((_) {
      _cleanupPending = false;
      _cleanupFailed = false;
    }, onError: (Object error, StackTrace stack) {
      _cleanupPending = false;
      _cleanupFailed = true;
      Error.throwWithStackTrace(error, stack);
    });
    _cleanup.then<void>((_) {}, onError: (Object error, StackTrace stack) {
      debugPrint('Session cleanup failed: $error');
    });
  }

  void recordActivity() {
    if (!isUnlocked || !_foreground || hasSystemInteraction) return;
    _lastActivity = _now();
    _schedule();
  }

  void handleLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      isObscured = true;
      notifyListeners();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      isObscured = false;
      _foreground = true;
      _checkDeadline();
      _backgroundAt = null;
      for (final interaction in _interactions.toList()) {
        if (interaction._leftApp && interaction._completed) {
          interaction._release();
        }
      }
      _schedule();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      isObscured = true;
      _backgroundAt ??= _now();
      for (final interaction in _interactions) {
        interaction._leftApp = true;
        interaction._launchTimer?.cancel();
      }
      _schedule();
    }
    notifyListeners();
  }

  SystemInteraction beginSystemInteraction({bool waitForResume = false}) {
    final interaction = SystemInteraction._(this, waitForResume);
    _interactions.add(interaction);
    _timer?.cancel();
    notifyListeners();
    return interaction;
  }

  void _releaseInteraction(SystemInteraction interaction) {
    _interactions.remove(interaction);
    if (!hasSystemInteraction) {
      _lastActivity = _now();
      _backgroundAt = _foreground ? null : _now();
      _schedule();
    }
    notifyListeners();
  }

  DateTime? get _deadline {
    if (!isUnlocked || hasSystemInteraction) return null;
    final deadlines = <DateTime>[];
    if (_lastActivity != null && _settings.inactivityLockSeconds > 0) {
      deadlines.add(_lastActivity!
          .add(Duration(seconds: _settings.inactivityLockSeconds)));
    }
    if (_backgroundAt != null && _settings.backgroundLockDelaySeconds >= 0) {
      deadlines.add(_backgroundAt!
          .add(Duration(seconds: _settings.backgroundLockDelaySeconds)));
    }
    if (deadlines.isEmpty) return null;
    deadlines.sort();
    return deadlines.first;
  }

  void _checkDeadline() {
    final deadline = _deadline;
    if (deadline != null && !_now().isBefore(deadline)) {
      unawaited(lock());
    }
  }

  void _schedule() {
    _timer?.cancel();
    _checkDeadline();
    final deadline = _deadline;
    if (deadline != null) {
      _timer = Timer(deadline.difference(_now()), _schedule);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final interaction in _interactions.toList()) {
      interaction._launchTimer?.cancel();
    }
    super.dispose();
  }
}

class SystemInteraction {
  SystemInteraction._(this._session, this._waitForResume);
  final SessionService _session;
  final bool _waitForResume;
  final Completer<void> _released = Completer<void>();
  bool _completed = false;
  bool _leftApp = false;
  Timer? _launchTimer;

  Future<void> get released => _released.future;

  void complete({bool failed = false}) {
    if (_released.isCompleted) return;
    _completed = true;
    if (failed) {
      _release();
    } else if (_session._foreground) {
      if (_waitForResume && !_leftApp) {
        // Intent APIs can return before the pause callback arrives.
        _launchTimer = Timer(const Duration(seconds: 2), _release);
      } else {
        _release();
      }
    }
  }

  void _release() {
    if (_released.isCompleted) return;
    _launchTimer?.cancel();
    _session._releaseInteraction(this);
    _released.complete();
  }
}
