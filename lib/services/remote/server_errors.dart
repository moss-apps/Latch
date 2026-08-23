import 'package:flutter/foundation.dart';

/// Map any server/sync failure to a plain-language, actionable message.
/// String-matches on toString() so callers don't import transitive dio/webdav.
String describeServerError(Object e) {
  final s = e.toString().toLowerCase();

  if (s.contains('connection timeout') || s.contains('connecttimeout')) {
    return "Couldn't reach the server (timed out). Check it's running on "
        'the right port and bound to 0.0.0.0, not localhost.';
  }
  if (s.contains('connection refused') ||
      s.contains('reset') ||
      s.contains('broken pipe')) {
    return "Server refused the connection. Wrong port, or the WebDAV "
        "service isn't running.";
  }
  if (s.contains('401') ||
      s.contains('unauthorized') ||
      s.contains('403') ||
      s.contains('forbidden')) {
    return 'Sign-in failed — check your username and password.';
  }
  if (s.contains('certificate') ||
      s.contains('handshake') ||
      s.contains('tls')) {
    return "Secure connection failed — the server's certificate was "
        'rejected. If you trust it, add the exception in your server '
        'settings.';
  }
  if (s.contains('404') || s.contains('not found')) {
    return "The server couldn't find that path — check the base path and "
        'URL in your server settings.';
  }
  if (s.contains('receive timeout') ||
      s.contains('send timeout') ||
      s.contains('connection closed')) {
    return 'The connection dropped mid-transfer. Check your network and '
        'try again.';
  }
  if (s.contains('connection error') ||
      s.contains('socket') ||
      s.contains('network') ||
      s.contains('host')) {
    return 'Network error — wrong address, firewall, or device not on the '
        'same LAN as the server.';
  }
  if (e is FormatException || s.contains('invalid ciphertext')) {
    return "The data on the server couldn't be read — it may be corrupt or "
        'belong to a different vault.';
  }
  if (s.startsWith('bad state:')) {
    // SyncService StateErrors are already plain sentences; strip the prefix.
    return e.toString().replaceFirst(RegExp(r'^Bad state:\s*'), '');
  }

  debugPrint('[sync] unrecognized error: $e');
  return 'Something went wrong while talking to the server. Check your '
      'connection and try again.';
}
