import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/operation_progress.dart';
import 'package:locker/providers/operation_provider.dart';
import 'package:locker/services/file_import_service.dart';
import 'package:locker/services/file_operation_gate.dart';
import 'package:locker/services/file_service.dart';
import 'package:locker/services/operation_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('presentation changes never restart or finish the underlying task',
      () async {
    final gate = FileOperationGate();
    final done = Completer<OperationOutcome>();
    final finished = Completer<OperationOutcome>();
    final controller =
        OperationController(gate: gate, onFinished: finished.complete);
    addTearDown(controller.dispose);
    late OperationJob job;
    var starts = 0;
    expect(
        controller.start(
          type: OperationType.hide,
          initialProgress: const OperationProgressState(totalFiles: 3),
          task: (current) {
            job = current;
            starts++;
            return done.future;
          },
        ),
        isTrue);

    controller.minimize();
    controller.expand();
    controller.restore();
    controller.minimize();
    controller.dismiss(); // Cannot dismiss a running task.
    job.fileProgress(FileProgressInfo(
      current: 3,
      total: 3,
      fileName: 'large.mp4',
      fileSize: 900,
      status: 'Encrypting...',
      isEncrypting: true,
      encryptedBytes: 450,
      totalBytes: 900,
      completedFiles: 0,
      batchProcessedBytes: 500,
      batchTotalBytes: 1000,
    ));
    expect(starts, 1);
    expect(controller.isRunning, isTrue);
    expect(controller.presentation, OperationPresentation.pill);
    expect(controller.progress.currentFile, 0);
    expect(controller.progress.fraction, 0.5);
    done.complete(
        const OperationOutcome(message: 'Imported 3', processedFiles: 3));
    await finished.future;
    expect(controller.isRunning, isFalse);
    expect(gate.isBusy, isFalse);
    expect(controller.presentation, OperationPresentation.pill);
    expect(controller.progress.isComplete, isTrue);
    expect(controller.progress.fraction, 1);
    controller.dismiss();
    expect(controller.type, isNull);
    job.batchProgress(99, 99); // Late callbacks after dismissal are ignored.
    expect(controller.progress.totalFiles, 0);
  });

  test(
      'rejects another batch without queueing it while navigation is available',
      () async {
    final done = Completer<OperationOutcome>();
    final finished = Completer<OperationOutcome>();
    var busyCalls = 0;
    var secondStarts = 0;
    final controller = OperationController(
        gate: FileOperationGate(),
        onFinished: finished.complete,
        onBusy: () => busyCalls++);
    addTearDown(controller.dispose);
    controller.start(
        type: OperationType.delete,
        initialProgress: const OperationProgressState(),
        task: (_) => done.future);
    controller.minimize();
    expect(
        controller.start(
          type: OperationType.hide,
          initialProgress: const OperationProgressState(),
          task: (_) async {
            secondStarts++;
            return const OperationOutcome(message: 'Should not run');
          },
        ),
        isFalse);
    expect(busyCalls, 1);
    expect(secondStarts, 0);
    done.complete(const OperationOutcome(message: 'Deleted'));
    await finished.future;
    expect(secondStarts, 0);
  });

  test('partial results preserve actual counts, bytes, and review details',
      () async {
    final finished = Completer<OperationOutcome>();
    final partial =
        BulkDeleteResult(removed: ['one'], failed: ['two', 'three']);
    final controller = OperationController(
        gate: FileOperationGate(), onFinished: finished.complete);
    addTearDown(controller.dispose);
    String? finalizingStatus;
    String? nameAfterUnnamedUpdate;
    controller.start(
      type: OperationType.delete,
      initialProgress:
          const OperationProgressState(totalFiles: 3, totalSizeBytes: 1000),
      task: (job) async {
        job.batchProgress(1, 3,
            currentSize: 400, totalSize: 1000, currentFileName: 'two.txt');
        job.batchProgress(3, 3,
            currentSize: 1000, totalSize: 1000, currentFileName: 'two.txt');
        finalizingStatus = job.value.statusMessage;
        // Counts-only updates from byte streams must not erase the name.
        job.batchProgress(1, 3, currentSize: 400, totalSize: 1000);
        nameAfterUnnamedUpdate = job.value.currentFileName;
        return OperationOutcome(
            kind: OperationOutcomeKind.warning,
            message: 'Deleted 1; 2 could not be deleted',
            processedFiles: 1,
            result: partial);
      },
    );
    await finished.future;
    expect(finalizingStatus, 'Finalizing...');
    expect(nameAfterUnnamedUpdate, 'two.txt');
    expect(controller.progress.currentFile, 1);
    expect(controller.progress.fraction, 0.4);
    expect(controller.progress.currentFileName, 'two.txt');
    expect(controller.progress.statusMessage, contains('2 could not'));
    expect(controller.outcome!.result, same(partial));
    expect(controller.progress.isComplete, isTrue);
  });

  test('an exception becomes a reviewable error and releases the reservation',
      () async {
    final gate = FileOperationGate();
    final finished = Completer<OperationOutcome>();
    final controller =
        OperationController(gate: gate, onFinished: finished.complete);
    addTearDown(controller.dispose);
    controller.start(
        type: OperationType.encrypt,
        initialProgress: const OperationProgressState(),
        task: (_) async => throw StateError('test failure'));
    final result = await finished.future;
    expect(result.kind, OperationOutcomeKind.error);
    expect(gate.isBusy, isFalse);
    expect(controller.isRunning, isFalse);
  });

  test(
      'disposing the session invalidates IO and suppresses stale progress/toasts',
      () async {
    final gate = FileOperationGate();
    final done = Completer<OperationOutcome>();
    var finishes = 0;
    late OperationJob job;
    final controller =
        OperationController(gate: gate, onFinished: (_) => finishes++);
    controller.start(
        type: OperationType.unhide,
        initialProgress: const OperationProgressState(),
        task: (current) {
          job = current;
          return done.future;
        });
    controller.minimize();
    controller.dispose();
    expect(job.isCurrent, isFalse);
    job.batchProgress(5, 5);
    var drained = false;
    final cleanup = gate.invalidateAndDrain().then((_) => drained = true);
    await Future<void>.delayed(Duration.zero);
    expect(drained, isFalse);
    done.complete(const OperationOutcome(message: 'Sensitive result'));
    await cleanup;
    await Future<void>.delayed(Duration.zero);
    expect(finishes, 0);
    expect(gate.isBusy, isFalse);
    expect(controller.type, isNull);
  });

  test(
      'gate permits nested owner IO, blocks foreign mutations, and protects only affected reads',
      () async {
    final gate = FileOperationGate();
    final lease = gate.acquire({'affected'})!;
    final release = Completer<void>();
    final running = gate.run(lease, () async {
      expect(gate.allowsMutation, isTrue);
      expect(gate.canRead('affected'), isTrue);
      expect(await gate.mutate(() async => 7, blockedResult: -1), 7);
      await release.future;
      expect(gate.allowsMutation, isFalse);
      expect(gate.canRead('unrelated'), isFalse); // Old session's callbacks.
      return gate.mutate(() async => 8, blockedResult: -1);
    });
    expect(gate.acquire({}), isNull);
    expect(gate.canRead('affected'), isFalse);
    expect(gate.canRead('unrelated'), isTrue);
    expect(await gate.mutate(() async => 9, blockedResult: -1), -1);
    final drained = gate.invalidateAndDrain();
    release.complete();
    expect(await running, -1);
    await drained;
    expect(gate.canRead('affected'), isTrue);
    expect(await gate.mutate(() async => 10, blockedResult: -1), 10);
  });

  test(
      'controller also rejects a batch during an earlier non-progress mutation',
      () async {
    final gate = FileOperationGate();
    final release = Completer<void>();
    final prior = gate.mutate(() => release.future, blockedResult: null);
    final controller = OperationController(gate: gate);
    addTearDown(controller.dispose);
    expect(controller.checkAvailable(), isFalse);
    release.complete();
    await prior;
    expect(controller.checkAvailable(), isTrue);
  });

  test(
      'duplicate-only imports are informational, mixed failures are not success',
      () {
    expect(
        importOutcome(const ImportResult(
                success: true, importedFiles: [], skippedDuplicates: 2))
            .kind,
        OperationOutcomeKind.info);
    expect(
        importOutcome(const ImportResult(
                success: false,
                importedFiles: [],
                skippedDuplicates: 2,
                failedCount: 1))
            .kind,
        OperationOutcomeKind.error);
  });

  test(
      'percentage uses bytes where known and is bounded for malformed callbacks',
      () {
    expect(const OperationProgressState(totalFiles: 2, currentFile: 1).fraction,
        0.5);
    expect(
        const OperationProgressState(
                totalFiles: 2,
                currentFile: 2,
                totalSizeBytes: 100,
                processedSizeBytes: 20)
            .fraction,
        0.2);
    expect(
        const OperationProgressState(
                totalSizeBytes: 100, processedSizeBytes: 101)
            .fraction,
        1);
    expect(
        const OperationProgressState(totalFiles: 2, currentFile: -1).fraction,
        0);
  });
}
