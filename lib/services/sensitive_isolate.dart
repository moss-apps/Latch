import 'dart:async';
import 'dart:isolate';

class SensitiveIsolate {
  static int _generation = 0;
  static final Map<Isolate, void Function()> _running = {};

  static Future<T> run<T>(Future<T> Function() task) async {
    final generation = _generation;
    final port = ReceivePort();
    final result = Completer<T>();
    final subscription = port.listen((message) {
      if (result.isCompleted) return;
      if (message is List && message.length == 2 && message[0] == 'result') {
        result.complete(message[1] as T);
      } else {
        result.completeError(StateError('Sensitive worker failed: $message'));
      }
    });
    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(
        _entry,
        [port.sendPort, task],
        onError: port.sendPort,
        onExit: port.sendPort,
        errorsAreFatal: true,
      );
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
