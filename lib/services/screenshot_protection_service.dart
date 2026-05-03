import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ScreenshotProtectionService {
  ScreenshotProtectionService._();

  static const MethodChannel _channel =
      MethodChannel('com.mossapps.locker/screenshot_protection');

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> setEnabled(bool enabled) async {
    if (!isSupported) return;

    try {
      await _channel.invokeMethod('setScreenshotProtectionEnabled', enabled);
      debugPrint('[ScreenshotProtection] Set enabled: $enabled');
    } on PlatformException catch (e) {
      debugPrint('[ScreenshotProtection] Failed to set enabled: $e');
    }
  }
}
