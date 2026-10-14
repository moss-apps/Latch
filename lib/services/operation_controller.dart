import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/operation_progress.dart';
import 'file_operation_gate.dart';
import 'file_service.dart';

/// Owns the task, not a route. Minimizing changes presentation only.
class OperationController extends ChangeNotifier {
  OperationController({
    FileOperationGate? gate,
    this.onFinished,
    this.onBusy,
  }) : _gate = gate ?? FileOperationGate.instance;

  final FileOperationGate _gate;
  final ValueChanged<OperationOutcome>? onFinished;
  final VoidCallback? onBusy;
  OperationJob? _job;
  FileOperationLease? _lease;
  OperationType? type;
  OperationOutcome? outcome;
  OperationPresentation presentation = OperationPresentation.sheet;
  int id = 0;
  bool _disposed = false;

  OperationProgressState get progress =>
      _job?.value ?? const OperationProgressState();
  void _progressChanged() => notifyListeners();
  bool get isRunning => _job != null && outcome == null;
  bool get isBusy => isRunning || _gate.isBusy;

  bool checkAvailable() {
    if (_disposed) return false;
    if (!isBusy) return true;
    onBusy?.call();
    return false;
  }

  bool start({
    required OperationType type,
    required OperationProgressState initialProgress,
    required Future<OperationOutcome> Function(OperationJob job) task,
    Set<String> fileIds = const {},
  }) {
    if (!checkAvailable()) return false;
    final lease = _gate.acquire(fileIds);
    if (lease == null) return false;
    id++;
    this.type = type;
    outcome = null;
    presentation = OperationPresentation.sheet;
    _lease = lease;
    final job = _job = OperationJob._(this, id, initialProgress);
    notifyListeners();
    unawaited(_execute(job, lease, task));
    return true;
  }

  Future<void> _execute(OperationJob job, FileOperationLease lease,
      Future<OperationOutcome> Function(OperationJob) task) async {
    OperationOutcome result;
    try {
      result = await _gate.run(lease, () => task(job));
    } catch (error, stack) {
      debugPrint('File operation failed: $error\n$stack');
      result = const OperationOutcome(
        kind: OperationOutcomeKind.error,
        message: 'The operation failed. Review your files before trying again.',
      );
    }
    if (!job.isCurrent) return;
    outcome = result;
    job._value = job.value.copyWith(
      isProcessing: false,
      isComplete: true,
      isEncrypting: false,
      currentFile: result.processedFiles,
      processedSizeBytes: result.kind == OperationOutcomeKind.success
          ? job.value.totalSizeBytes
          : null,
      statusMessage: result.message,
    );
    notifyListeners();
    onFinished?.call(result);
  }

  void minimize() => _present(OperationPresentation.pill);
  void expand() => _present(OperationPresentation.panel);
  void restore() => _present(OperationPresentation.sheet);

  void _present(OperationPresentation value) {
    if (_disposed || type == null || presentation == value) return;
    presentation = value;
    notifyListeners();
  }

  void dismiss() {
    if (_disposed || isRunning) return;
    type = null;
    _job = null;
    outcome = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _lease?.invalidate();
    _job = null;
    type = null;
    outcome = null;
    super.dispose();
  }
}

class OperationJob {
  OperationJob._(this._controller, this._id, this._value);
  final OperationController _controller;
  final int _id;
  OperationProgressState _value;

  bool get isCurrent =>
      !_controller._disposed &&
      identical(_controller._job, this) &&
      _controller.id == _id &&
      _controller._lease?.isValid == true;

  OperationProgressState get value => _value;
  set value(OperationProgressState state) {
    if (!isCurrent || _controller.outcome != null) return;
    _value = state;
    _controller._progressChanged();
  }

  void batchProgress(int current, int total,
      {int? currentSize, int? totalSize, String? currentFileName}) {
    value = value.copyWith(
      totalFiles: total,
      currentFile: current,
      currentFileName: currentFileName,
      totalSizeBytes: totalSize,
      processedSizeBytes: currentSize,
      statusMessage: current == 0
          ? 'Preparing files...'
          : current >= total
              ? 'Finalizing...'
              : 'Processing file ${current + 1} of $total...',
    );
  }

  void fileProgress(FileProgressInfo info) {
    value = value.copyWith(
      totalFiles: info.total,
      currentFile: info.completedFiles,
      currentFileName: info.fileName,
      statusMessage: info.status,
      isEncrypting: info.isEncrypting,
      totalSizeBytes: info.batchTotalBytes,
      processedSizeBytes: info.batchProcessedBytes,
    );
  }

  void encryptionProgress(
      int current, int total, String name, int processed, int totalBytes) {
    value = value.copyWith(
      totalFiles: total,
      currentFile: current,
      currentFileName: name,
      totalSizeBytes: totalBytes,
      processedSizeBytes: processed,
      statusMessage: current >= total
          ? 'Finalizing...'
          : 'Processing ${current + 1} of $total...',
    );
  }
}
