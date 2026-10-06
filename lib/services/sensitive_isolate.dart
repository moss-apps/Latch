import 'dart:async';
import 'dart:isolate';

import 'diagnostics.dart';
import 'remote/server_errors.dart';
import 'sync_control.dart';

class SensitiveWorker {
  SensitiveWorker(this.port, this.control);
  final SendPort port;
  final SyncControl control;
  void emit(Object event) => port.send(['event', event]);
}

class SensitiveIsolate {
  static int _generation = 0;
  static final Map<Isolate, void Function()> _running = {};

  static Future<T> run<T>(Future<T> Function() task) =>
      runWithEvents<T>((_) => task());

  static Future<T> runWithEvents<T>(
    Future<T> Function(SensitiveWorker) task, {
    void Function(Object)? onEvent,
    SyncControl? control,
  }) async {
    final generation = _generation;
    final port = ReceivePort();
    final result = Completer<T>();
    StackTrace? workerStack;

    void failWorker() {
      final id = Diagnostics.failure('worker.exit',
          StateError('Worker exited unexpectedly'), workerStack ?? StackTrace.current);
      result.completeError(SyncWorkerFailure(
          'The operation stopped unexpectedly. Try again, or copy the error reference for help.', id));
    }

    final subscription = port.listen((message) {
      if (result.isCompleted) return;
      if (message is List && message[0] == 'control') {
        final send = message[1] as SendPort;
        control?.onCancel = () => send.send('cancel');
        if (control?.cancelled == true) send.send('cancel');
        return;
      }
      if (message is List && message[0] == 'event') {
        onEvent?.call(message[1] as Object);
        return;
      }
      if (message is List && message[0] == 'cancelled') {
        result.completeError(SyncCancelled());
        return;
      }
      if (message is List && message[0] == 'failure') {
        result.completeError(SyncWorkerFailure(message[1] as String,
            message[2] as String));
        return;
      }
      if (message is List && message.length == 2 && message[0] == 'result') {
        result.complete(message[1] as T);
        return;
      }
      if (message == null) {
        failWorker();
        return;
      }
      // Isolate.spawn delivers uncaught errors as [error, stackTrace].
      if (message is List && message.length == 2) {
        final raw = message[1];
        workerStack = raw is StackTrace
            ? raw
            : raw == null
                ? null
                : StackTrace.fromString('$raw');
      }
      failWorker();
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
        final id = Diagnostics.failure('worker.spawn', e, st);
        throw SyncWorkerFailure('The operation couldn’t start. Try again, or copy the error reference for help.', id);
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
      control?.onCancel = null;
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
    final task = args[1] as Future<Object?> Function(SensitiveWorker);
    final commands = ReceivePort();
    final control = SyncControl();
    final subscription = commands.listen((_) => control.cancel());
    port.send(['control', commands.sendPort]);
    try {
      port.send(['result', await task(SensitiveWorker(port, control))]);
    } catch (e, st) {
      if (e is SyncCancelled || control.cancelled) {
        port.send(['cancelled']);
      } else {
        final id = Diagnostics.failure('worker', e, st);
        port.send(['failure', describeServerError(e), id]);
      }
    } finally {
      await subscription.cancel();
      commands.close();
    }
  }
}

class SyncWorkerFailure implements Exception {
  SyncWorkerFailure(this.message, this.diagnosticId);
  final String message;
  final String diagnosticId;
}
