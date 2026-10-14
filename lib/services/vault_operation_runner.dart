import '../models/encryption_algorithm.dart';
import '../models/operation_progress.dart';
import 'file_import_service.dart';
import 'operation_controller.dart';
import 'vault_service.dart';

/// Captures services and immutable inputs before the initiating route can leave.
class VaultOperationRunner {
  const VaultOperationRunner(this.controller, this.vault, this.isDecoy);
  final OperationController controller;
  final VaultService vault;
  final bool isDecoy;

  bool delete(Set<String> selection) {
    final ids = Set<String>.unmodifiable(selection);
    return controller.start(
      type: OperationType.delete,
      fileIds: ids,
      initialProgress: OperationProgressState(totalFiles: ids.length),
      task: (job) async {
        final result = await vault.removeFiles(
          ids.toList(),
          isDecoy: isDecoy,
          onProgress: job.batchProgress,
        );
        return OperationOutcome(
          kind: result.allSucceeded
              ? OperationOutcomeKind.success
              : result.anyRemoved
                  ? OperationOutcomeKind.warning
                  : OperationOutcomeKind.error,
          message: result.allSucceeded
              ? 'Deleted ${result.removedCount} file(s)'
              : 'Deleted ${result.removedCount}; ${result.failedCount} could not be deleted',
          processedFiles: result.removedCount,
          result: result,
        );
      },
    );
  }

  bool unhide(Set<String> selection) {
    final ids = Set<String>.unmodifiable(selection);
    return controller.start(
      type: OperationType.unhide,
      fileIds: ids,
      initialProgress: OperationProgressState(totalFiles: ids.length),
      task: (job) async {
        final result = await FileImportService.instance.unhideFiles(
          fileIds: ids.toList(),
          removeFromVault: true,
          onProgress: job.batchProgress,
        );
        return OperationOutcome(
          kind: !result.success
              ? OperationOutcomeKind.error
              : result.errorCount > 0 || result.retainedInVault > 0
                  ? OperationOutcomeKind.warning
                  : OperationOutcomeKind.success,
          message:
              result.message ?? result.error ?? 'Files restored to gallery',
          processedFiles: result.unhiddenCount,
          result: result,
        );
      },
    );
  }

  bool encryption(Set<String> selection, OperationType type,
      EncryptionAlgorithm algorithm) {
    final ids = Set<String>.unmodifiable(selection);
    return controller.start(
      type: type,
      fileIds: ids,
      initialProgress: OperationProgressState(
        totalFiles: ids.length,
        isEncrypting: type != OperationType.decrypt,
      ),
      task: (job) async {
        final count = switch (type) {
          OperationType.encrypt => await vault.encryptVaultFiles(
              algorithm,
              isDecoy: isDecoy,
              fileFilter: ids,
              onProgress: job.encryptionProgress,
            ),
          OperationType.decrypt => await vault.removeEncryption(
              isDecoy: isDecoy,
              fileFilter: ids,
              onProgress: job.encryptionProgress,
            ),
          OperationType.reencrypt => await vault.reEncryptVault(
              algorithm,
              isDecoy: isDecoy,
              fileFilter: ids,
              onProgress: job.encryptionProgress,
            ),
          _ => throw ArgumentError.value(type),
        };
        return OperationOutcome(
          kind: count < 0
              ? OperationOutcomeKind.error
              : count < ids.length
                  ? OperationOutcomeKind.warning
                  : OperationOutcomeKind.success,
          message: count < 0
              ? '${type.title} failed. Some files may have been processed; review your files before retrying.'
              : '$count file(s) processed${count < ids.length ? ' · ${ids.length - count} skipped or unchanged' : ''}',
          processedFiles: count < 0 ? null : count,
          result: count,
        );
      },
    );
  }
}
