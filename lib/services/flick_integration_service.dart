import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FlickIntegrationService {
  static const packageName = 'com.mossapps.flick';
  static const MethodChannel _channel =
      MethodChannel('com.mossapps.locker/flick');

  static Future<bool> isAvailable() async {
    if (!Platform.isAndroid) return false;

    try {
      return await _channel.invokeMethod<bool>('isFlickInstalled') ?? false;
    } on PlatformException catch (e) {
      debugPrint('[Flick] Failed to check availability: $e');
      return false;
    }
  }

  static Future<void> openAudioFile({
    required String filePath,
    required String mimeType,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Flick handoff is only available on Android');
    }

    await _channel.invokeMethod<void>('openAudioInFlick', {
      'filePath': filePath,
      'mimeType': mimeType,
    });
  }
}
