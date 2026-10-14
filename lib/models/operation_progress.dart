enum OperationType { hide, unhide, delete, encrypt, decrypt, reencrypt }

extension OperationTypeLabel on OperationType {
  String get title => switch (this) {
        OperationType.hide => 'Hiding Files',
        OperationType.unhide => 'Unhiding Files',
        OperationType.delete => 'Deleting Files',
        OperationType.encrypt => 'Encrypting Files',
        OperationType.decrypt => 'Removing Encryption',
        OperationType.reencrypt => 'Re-encrypting Files',
      };

  String get shortLabel => switch (this) {
        OperationType.hide => 'Hiding',
        OperationType.unhide => 'Unhiding',
        OperationType.delete => 'Deleting',
        OperationType.encrypt => 'Encrypting',
        OperationType.decrypt => 'Decrypting',
        OperationType.reencrypt => 'Re-encrypting',
      };
}

enum OperationPresentation { sheet, pill, panel }

enum OperationOutcomeKind { success, info, warning, error }

class OperationOutcome {
  const OperationOutcome({
    required this.message,
    this.kind = OperationOutcomeKind.success,
    this.processedFiles,
    this.result,
  });

  final String message;
  final OperationOutcomeKind kind;
  final int? processedFiles;

  /// Keep partial service results available until the user dismisses the job.
  final Object? result;
}

class OperationProgressState {
  const OperationProgressState({
    this.totalFiles = 0,
    this.currentFile = 0,
    this.currentFileName = '',
    this.totalSizeBytes = 0,
    this.processedSizeBytes = 0,
    this.statusMessage = 'Preparing...',
    this.isProcessing = true,
    this.isComplete = false,
    this.isEncrypting = false,
  });

  final int totalFiles;
  final int currentFile;
  final String currentFileName;
  final int totalSizeBytes;
  final int processedSizeBytes;
  final String statusMessage;
  final bool isProcessing;
  final bool isComplete;
  final bool isEncrypting;

  double get fraction => (totalSizeBytes > 0
          ? processedSizeBytes / totalSizeBytes
          : totalFiles > 0
              ? currentFile / totalFiles
              : 0.0)
      .clamp(0.0, 1.0);

  OperationProgressState copyWith({
    int? totalFiles,
    int? currentFile,
    String? currentFileName,
    int? totalSizeBytes,
    int? processedSizeBytes,
    String? statusMessage,
    bool? isProcessing,
    bool? isComplete,
    bool? isEncrypting,
  }) =>
      OperationProgressState(
        totalFiles: totalFiles ?? this.totalFiles,
        currentFile: currentFile ?? this.currentFile,
        currentFileName: currentFileName ?? this.currentFileName,
        totalSizeBytes: totalSizeBytes ?? this.totalSizeBytes,
        processedSizeBytes: processedSizeBytes ?? this.processedSizeBytes,
        statusMessage: statusMessage ?? this.statusMessage,
        isProcessing: isProcessing ?? this.isProcessing,
        isComplete: isComplete ?? this.isComplete,
        isEncrypting: isEncrypting ?? this.isEncrypting,
      );
}
