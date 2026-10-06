import 'dart:io';

import 'package:dio/dio.dart';

import 'remote_store.dart';

String describeServerError(Object error) {
  final text = error.toString().toLowerCase();
  final status = error is DioException ? error.response?.statusCode : null;
  if (error is RemoteRevisionChanged) {
    return 'Another device updated the backup while you were syncing. Your files are safe. Try syncing again.';
  }
  if (error is UnsafeRemotePublication) {
    return 'This server cannot safely update your backup. Try another server or use Desktop Backup.';
  }
  if (status == 401 || status == 403 || text.contains('unauthorized') || text.contains('forbidden')) {
    return 'Couldn’t sign in to your server. Check the username and password in its settings.';
  }
  if (status == 507 || text.contains('no space') || text.contains('errno = 28')) {
    return 'There isn’t enough free space to finish. Free up space on this device or the server, then try again.';
  }
  if (status == 429 || (status != null && status >= 500)) {
    return 'Your server is busy or unavailable. Wait a moment and try again.';
  }
  if (text.contains('session') && (text.contains('locked') || text.contains('expired'))) {
    return 'Sync stopped when the vault locked. Unlock it and sync again.';
  }
  if (text.contains('certificate') || text.contains('handshake') || text.contains('tls')) {
    return 'A secure connection to your server couldn’t be established. Check its security settings and try again.';
  }
  if (error is FormatException || text.contains('invalidcipher') || text.contains('invalid ciphertext')) {
    return 'This backup couldn’t be verified or belongs to another vault. Your existing files haven’t been replaced. Check the backup and try again.';
  }
  if (error is FileSystemException) {
    return 'A file couldn’t be saved or opened. Check free space and storage access, then try again.';
  }
  if (error is DioException || error is SocketException || text.contains('timeout') || text.contains('connection')) {
    return 'Couldn’t connect to your server or the connection was interrupted. Check your network and server settings, then try again.';
  }
  return 'Sync couldn’t finish. Your files are still available. Try again; if it keeps happening, copy the error details for help.';
}
