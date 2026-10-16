import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/operation_progress.dart';
import '../services/file_import_service.dart';
import '../services/operation_controller.dart';
import '../services/vault_operation_runner.dart';
import '../utils/toast_utils.dart';
import 'explorer_providers.dart';
import 'note_providers.dart';
import 'password_providers.dart';
import 'vault_providers.dart';

final operationControllerProvider = Provider<OperationController>((ref) {
  final controller = OperationController(
    onBusy: () => ToastUtils.showInfo(
        'A file operation is already running. You can keep browsing.'),
    onFinished: (outcome) {
      if (!ref.mounted) return;
      // Refresh at app scope, even if the initiating screen was popped.
      ref.invalidate(vaultNotifierProvider);
      ref.invalidate(filteredFilesProvider);
      ref.invalidate(fileByIdProvider);
      ref.invalidate(albumsNotifierProvider);
      ref.invalidate(foldersNotifierProvider);
      ref.invalidate(totalStorageProvider);
      ref.invalidate(vaultSettingsProvider);
      ref.invalidate(notesNotifierProvider);
      ref.invalidate(passwordsNotifierProvider);
      ref.invalidate(explorerSubfoldersProvider);
      switch (outcome.kind) {
        case OperationOutcomeKind.success:
          ToastUtils.showSuccess(outcome.message);
        case OperationOutcomeKind.info:
          ToastUtils.showInfo(outcome.message);
        case OperationOutcomeKind.warning:
          ToastUtils.showWarning(outcome.message);
        case OperationOutcomeKind.error:
          ToastUtils.showError(outcome.message);
      }
    },
  );
  ref.onDispose(controller.dispose);
  return controller;
});

final vaultOperationRunnerProvider = Provider<VaultOperationRunner>((ref) =>
    VaultOperationRunner(ref.watch(operationControllerProvider),
        ref.watch(vaultServiceProvider), ref.watch(isDecoyModeProvider)));

final operationNavigatorObserverProvider =
    Provider<OperationNavigatorObserver>((ref) {
  final observer = OperationNavigatorObserver();
  ref.onDispose(observer.popupVisible.dispose);
  return observer;
});

/// Floating progress stays above pages, but never above other modal controls.
class OperationNavigatorObserver extends NavigatorObserver {
  final popupVisible = ValueNotifier(false);

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    popupVisible.value = topRoute is PopupRoute;
  }
}

OperationOutcome importOutcome(ImportResult result) {
  if (result.importedCount == 0) {
    final onlyDuplicates = result.skippedDuplicates > 0 &&
        result.failedCount == 0 &&
        result.error == null;
    return OperationOutcome(
      kind: onlyDuplicates
          ? OperationOutcomeKind.info
          : OperationOutcomeKind.error,
      message: onlyDuplicates
          ? 'Skipped ${result.skippedDuplicates} duplicate(s) already in vault'
          : result.error ?? result.message ?? 'No files imported',
      processedFiles: 0,
      result: result,
    );
  }
  final parts = ['Imported ${result.importedCount}'];
  if (result.skippedDuplicates > 0) {
    parts.add('${result.skippedDuplicates} duplicate(s) skipped');
  }
  if (result.failedCount > 0) parts.add('${result.failedCount} failed');
  if (result.retainedOriginals > 0) {
    parts.add('${result.retainedOriginals} original(s) retained');
  } else if (result.deletedOriginals) {
    parts.add('originals hidden');
  }
  return OperationOutcome(
    kind: result.failedCount > 0 || result.retainedOriginals > 0
        ? OperationOutcomeKind.warning
        : OperationOutcomeKind.success,
    message: parts.join(' · '),
    processedFiles: result.importedCount,
    result: result,
  );
}

OperationOutcome officeImportOutcome(OfficeImportResult result) {
  final imported = importOutcome(ImportResult(
    success: result.success,
    error: result.error,
    message: result.message,
    importedFiles: result.importedFiles,
    deletedOriginals: result.deletedOriginals,
    retainedOriginals: result.retainedOriginals,
    failedCount: result.failedCount,
  ));
  return OperationOutcome(
    kind: result.skippedFiles.isNotEmpty && result.importedCount > 0
        ? OperationOutcomeKind.warning
        : imported.kind,
    message: [
      imported.message,
      if (result.convertedCount > 0)
        '${result.convertedCount} converted to PDF',
      if (result.skippedFiles.isNotEmpty)
        '${result.skippedFiles.length} skipped: ${result.skippedFiles.join(', ')}',
    ].join(' · '),
    processedFiles: result.importedCount,
    result: result,
  );
}
