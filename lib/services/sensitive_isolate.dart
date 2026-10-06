import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

class SensitiveIsolate {
  static const _tag = '[SensitiveIsolate]';
  static int _generation = 0;
  static final Map<Isolate, void Function()> _running = {};

  static Future<T> run<T>(Future<T> Function() task) async {
    final generation = _generation;
    final port = ReceivePort();
    final result = Completer<T>();
    Object? workerError;
    StackTrace? workerStack;

    void logFailure(String detail) {
      debugPrint('$_tag worker failed: $detail');
      final stack = workerStack;
      if (stack != null) {
        debugPrintStack(label: _tag, stackTrace: stack);
      }
    }

    final subscription = port.listen((message) {
      if (result.isCompleted) return;
      if (message is List && message.length == 2 && message[0] == 'result') {
        result.complete(message[1] as T);
        return;
      }
      if (message == null) {
        final detail =
            workerError?.toString() ?? 'exited without returning a result';
        logFailure(detail);
        result.completeError(StateError('Sensitive worker failed: $detail'));
        return;
      }
      // Isolate.spawn delivers uncaught errors as [error, stackTrace].
      if (message is List && message.length == 2) {
        workerError = message[0];
        final raw = message[1];
        workerStack = raw is StackTrace
            ? raw
            : raw == null
                ? null
                : StackTrace.fromString('$raw');
      } else {
        workerError = message;
      }
      logFailure('$workerError');
      result.completeError(StateError('Sensitive worker failed: $workerError'));
    });
    Isolate? isolate;
    try {
      try {
        isolate = await Isolate.spawn(
          _entry,
          [port.sendPort, task],
          onError: port.sendPort,
          onExit: port.sendPort,
          errorsAreFatal: true,
        );
      } catch (e, st) {
        debugPrint('$_tag spawn failed: $e');
        debugPrintStack(label: _tag, stackTrace: st);
        rethrow;
      }
      if (generation != _generation) {
        isolate.kill(priority: Isolate.immediate);
        throw StateError('Vault session expired');
      }
      _running[isolate] = () {
        if (!result.isCompleted) {
          result.completeError(StateError('Vault session locked'));
        }
      };
      final value = await result.future;
      if (generation != _generation) throw StateError('Vault session expired');
      return value;
    } finally {
      if (isolate != null) {
        _running.remove(isolate);
        isolate.kill(priority: Isolate.immediate);
      }
      await subscription.cancel();
      port.close();
    }
  }

  static void cancelAll() {
    _generation++;
    for (final entry in _running.entries) {
      entry.key.kill(priority: Isolate.immediate);
      entry.value();
    }
    _running.clear();
  }

  static Future<void> _entry(List<Object> args) async {
    final port = args[0] as SendPort;
    final task = args[1] as Future<Object?> Function();
    port.send(['result', await task()]);
  }
}
