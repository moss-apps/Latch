import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'remote/remote_store.dart';

class Diagnostics {
  static void event(String operation, Map<String, Object?> fields) {
    debugPrint('[Latch] ${jsonEncode({
          'time': DateTime.now().toUtc().toIso8601String(),
          'operation': operation,
          ...fields,
        })}');
  }

  static String failure(String operation, Object error, StackTrace stack) {
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    // Request URLs, headers, filenames and exception messages can contain secrets.
    event(operation, {
      'errorId': id,
      'type': error.runtimeType.toString(),
      if (error is DioException) 'transport': error.type.name,
      if (error is DioException) 'httpStatus': error.response?.statusCode,
      if (error is DioException) 'method': error.requestOptions.method,
      if (error is FileSystemException) 'osCode': error.osError?.errorCode,
      if (error is SocketException) 'osCode': error.osError?.errorCode,
      if (error is UnsafeRemotePublication) 'reason': error.reason,
      if (error is FormatException &&
          const {
            'Source changed during sync',
            'Uploaded blob hash mismatch',
            'Downloaded blob hash mismatch',
            'Missing remote blob',
            'Incomplete restore metadata',
            'Missing vault destination',
            'Conflict copy hash mismatch',
            'Destination collision',
            'Invalid blob hash',
            'Invalid sync state',
            'Manifest blob too short',
          }.contains(error.message))
        'reason': error.message,
    });
    for (final line in stack.toString().split('\n')) {
      if (line.isNotEmpty) debugPrint('[Latch][$id] $line');
    }
    return id;
  }
}
