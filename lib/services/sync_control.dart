import 'package:dio/dio.dart';

class SyncCancelled implements Exception {}

class SyncControl {
  final CancelToken network = CancelToken();
  bool _cancelled = false;
  bool committing = false;
  void Function()? onCancel;

  bool get cancelled => _cancelled;

  void cancel() {
    if (committing || _cancelled) return;
    _cancelled = true;
    network.cancel();
    onCancel?.call();
  }

  void check() {
    if (_cancelled && !committing) throw SyncCancelled();
  }
}
