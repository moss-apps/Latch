import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'session_service.dart';

class AutoKillService {
  static bool _configuredEnabled = true;

  static Future<void> configure({required bool enabled}) async {
    _configuredEnabled = enabled;
    await _applyEnabled();
  }

  static Future<void> _applyEnabled() => setEnabled(
      _configuredEnabled && !SessionService.instance.hasSystemInteraction);
  static const MethodChannel _channel =
      MethodChannel('com.mossapps.locker/autokill');

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Apply the native switch; interaction callers should use [runSafe].
  static Future<void> setEnabled(bool enabled) async {
    if (!isSupported) return;

    try {
      await _channel.invokeMethod('setAutoKillEnabled', enabled);
      debugPrint('[AutoKill] Set enabled: $enabled');
    } on PlatformException catch (e) {
      debugPrint('[AutoKill] Failed to set enabled: $e');
    }
  }

  static Future<void> setDelaySeconds(int seconds) async {
    if (!isSupported) return;

    try {
      await _channel.invokeMethod('setAutoKillDelaySeconds', {
        'seconds': seconds,
      });
      debugPrint('[AutoKill] Set delay seconds: $seconds');
    } on PlatformException catch (e) {
      debugPrint('[AutoKill] Failed to set delay: $e');
    }
  }

  /// Suspend relocking and auto-kill until the system interaction returns.
  static Future<T> runSafe<T>(Future<T> Function() task,
      {bool waitForResume = false}) async {
    final interaction = SessionService.instance
        .beginSystemInteraction(waitForResume: waitForResume);
    interaction.released.then((_) => _applyEnabled());
    try {
      await _applyEnabled();
      final result = await task();
      interaction.complete();
      return result;
    } catch (_) {
      interaction.complete(failed: true);
      rethrow;
    }
  }
}
