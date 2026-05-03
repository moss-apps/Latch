import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class AutoKillService {
  static const MethodChannel _channel =
      MethodChannel('com.mossapps.locker/autokill');

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Set whether the auto-kill feature (killing app on pause) is enabled.
  /// Set to [false] before requesting permissions or launching external intents.
  /// Set back to [true] immediately after the interaction is complete or the app resumes.
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

  /// Run a task with auto-kill disabled.
  /// Re-enables auto-kill after the task completes (even if it throws).
  static Future<T> runSafe<T>(Future<T> Function() task) async {
    await setEnabled(false);
    try {
      return await task();
    } finally {
      // We re-enable it, but maybe we should wait for onResume?
      // Actually, if we re-enable it immediately after the await returns,
      // we might still be paused if the task was "wait for result".
      // But typically we await the result of the intent.
      // E.g. await Permission.request() returns AFTER the dialog closes (usually).
      // However, for some intents, onResume happens before the future completes.
      // It's safer to re-enable.
      await setEnabled(true);
    }
  }
}
