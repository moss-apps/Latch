import 'dart:async';

import 'package:flutter/services.dart';

class ClipboardUtil {
  ClipboardUtil._();

  static Timer? _clearTimer;
  static String? _lastCopied;

  static Future<void> copyWithAutoClear(
    String text, {
    int seconds = 20,
  }) async {
    _clearTimer?.cancel();
    _lastCopied = text;
    await Clipboard.setData(ClipboardData(text: text));
    _clearTimer = Timer(Duration(seconds: seconds), () async {
      final current = await Clipboard.getData('text/plain');
      if (current?.text == _lastCopied) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
      _lastCopied = null;
    });
  }

  static void cancelClear() {
    _clearTimer?.cancel();
    _lastCopied = null;
  }
}
