import 'dart:async';

/// Reserves file changes for one job, including its nested service calls.
/// Zones distinguish the owning job from actions on other, navigable screens.
class FileOperationGate {
  static final instance = FileOperationGate();
  static final Object _zoneKey = Object();
  FileOperationLease? _active;

  bool get isBusy => _active != null;

  bool get allowsMutation {
    final caller = Zone.current[_zoneKey] as FileOperationLease?;
    if (caller != null && !caller.isValid) return false;
    return _active == null || identical(caller, _active);
  }

  bool canRead(String fileId) {
    final caller = Zone.current[_zoneKey] as FileOperationLease?;
    if (caller != null && !caller.isValid) return false;
    return _active == null ||
        identical(caller, _active) ||
        !_active!.fileIds.contains(fileId);
  }

  /// Waits for a transient reservation of [fileId] to clear.
  ///
  /// Readers use this instead of failing immediately when another operation
  /// briefly owns the file (for example, a metadata commit). Returns false on
  /// timeout or when [shouldAbort] asks to stop.
  Future<bool> waitForReadable(
    String fileId, {
    Duration timeout = const Duration(seconds: 10),
    bool Function()? shouldAbort,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!canRead(fileId)) {
      if (shouldAbort?.call() ?? false) return false;
      if (!DateTime.now().isBefore(deadline)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return true;
  }

  /// Non-progress mutations (sharing, single-file actions) also reserve IO so a
  /// new batch cannot begin while an earlier service call is still committing.
  ///
  /// [fileIds] must only name payloads the task actually modifies. Reserving a
  /// read-only source blocks other screens from opening it for the whole task.
  Future<T> mutate<T>(Future<T> Function() task,
      {required T blockedResult, Set<String> fileIds = const {}}) {
    if (!allowsMutation) return Future.value(blockedResult);
    if (_active != null) return task();
    final lease = acquire(fileIds)!;
    return run(lease, task);
  }

  FileOperationLease? acquire(Set<String> fileIds) {
    if (isBusy) return null;
    return _active = FileOperationLease._(Set.of(fileIds));
  }

  /// Nested maintenance discovers ids after acquiring the mutation gate.
  /// Extend its read reservation before moving or overwriting those files.
  void reserveFileIds(Iterable<String> fileIds) {
    final caller = Zone.current[_zoneKey] as FileOperationLease?;
    if (caller == null || !caller.isValid || !identical(caller, _active)) {
      throw StateError('No active file operation');
    }
    caller._fileIds.addAll(fileIds);
  }

  Future<T> run<T>(FileOperationLease lease, Future<T> Function() task) async {
    try {
      return await runZoned(task, zoneValues: {_zoneKey: lease});
    } finally {
      if (identical(_active, lease)) _active = null;
      if (!lease._done.isCompleted) lease._done.complete();
    }
  }

  /// Lock cleanup waits for outstanding file IO before clearing session stores.
  Future<void> invalidateAndDrain() {
    final lease = _active;
    if (lease == null) return Future.value();
    lease.invalidate();
    return lease._done.future;
  }
}

class FileOperationLease {
  FileOperationLease._(this._fileIds);
  final Set<String> _fileIds;
  Set<String> get fileIds => Set.unmodifiable(_fileIds);
  final Completer<void> _done = Completer<void>();
  bool isValid = true;

  void invalidate() => isValid = false;
}
