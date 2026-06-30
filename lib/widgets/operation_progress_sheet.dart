import 'package:flutter/material.dart';
import '../themes/app_colors.dart';

enum OperationType { hide, unhide, delete, encrypt, decrypt, reencrypt }

class OperationProgressSheet extends StatefulWidget {
  final OperationType operationType;
  final int totalFiles;
  final int currentFile;
  final String currentFileName;
  final int totalSizeBytes;
  final int processedSizeBytes;
  final String statusMessage;
  final bool isProcessing;
  final bool isComplete;
  final bool isEncrypting;
  final VoidCallback? onCancel;

  const OperationProgressSheet({
    super.key,
    required this.operationType,
    required this.totalFiles,
    required this.currentFile,
    required this.currentFileName,
    required this.totalSizeBytes,
    required this.processedSizeBytes,
    required this.statusMessage,
    required this.isProcessing,
    this.isComplete = false,
    this.isEncrypting = false,
    this.onCancel,
  });

  @override
  State<OperationProgressSheet> createState() => _OperationProgressSheetState();
}

class _OperationProgressSheetState extends State<OperationProgressSheet> {
  @override
  Widget build(BuildContext context) {
    final fileProgress = widget.totalFiles > 0
        ? (widget.currentFile / widget.totalFiles).clamp(0.0, 1.0)
        : 0.0;
    final sizeProgress = widget.totalSizeBytes > 0
        ? (widget.processedSizeBytes / widget.totalSizeBytes).clamp(0.0, 1.0)
        : 0.0;
    final progress = widget.totalSizeBytes > 0 ? sizeProgress : fileProgress;

    return Container(
      decoration: BoxDecoration(
        color: context.backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.borderColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _buildOperationIcon(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getTitle(),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'ProductSans',
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getSubtitle(),
                          style: TextStyle(
                            fontSize: 14,
                            fontFamily: 'ProductSans',
                            color: context.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (widget.isComplete) ...[
                _buildCompleteState(),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.accentColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'ProductSans',
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                _buildProgressSection(progress, sizeProgress),
                const SizedBox(height: 20),
                _buildCurrentFileInfo(),
                const SizedBox(height: 20),
                _buildActionButton(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOperationIcon() {
    IconData icon;
    Color color;

    switch (widget.operationType) {
      case OperationType.hide:
        icon = widget.isEncrypting
            ? Icons.enhanced_encryption_outlined
            : Icons.lock_outline;
        color = widget.isEncrypting ? Colors.orange : AppColors.accent;
        break;
      case OperationType.unhide:
        icon = Icons.lock_open_outlined;
        color = Colors.green;
        break;
      case OperationType.delete:
        icon = Icons.delete_outline;
        color = AppColors.error;
        break;
      case OperationType.encrypt:
        icon = Icons.enhanced_encryption_outlined;
        color = Colors.orange;
        break;
      case OperationType.decrypt:
        icon = Icons.lock_open_outlined;
        color = Colors.green;
        break;
      case OperationType.reencrypt:
        icon = Icons.autorenew;
        color = Colors.blue;
        break;
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: widget.isProcessing || widget.isComplete
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: widget.isComplete
                  ? Icon(icon, color: color, size: 24)
                  : CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
            )
          : Icon(icon, color: color, size: 24),
    );
  }

  String _getTitle() {
    switch (widget.operationType) {
      case OperationType.hide:
        return 'Hiding Files';
      case OperationType.unhide:
        return 'Unhiding Files';
      case OperationType.delete:
        return 'Deleting Files';
      case OperationType.encrypt:
        return 'Encrypting Files';
      case OperationType.decrypt:
        return 'Removing Encryption';
      case OperationType.reencrypt:
        return 'Re-encrypting Files';
    }
  }

  String _getSubtitle() {
    if (widget.isComplete) {
      return 'Completed successfully';
    }
    final base = '${widget.currentFile} of ${widget.totalFiles} files';
    if (widget.isEncrypting) {
      return '$base - Encrypting...';
    }
    return base;
  }

  Widget _buildProgressSection(double progress, double sizeProgress) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Progress',
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'ProductSans',
                color: context.textSecondary,
              ),
            ),
            Text(
              '${(progress * 100).clamp(0, 100).toInt()}%',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFamily: 'ProductSans',
                color: context.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: context.dividerColor,
            valueColor: AlwaysStoppedAnimation(AppColors.accent),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Data Processed',
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'ProductSans',
                color: context.textSecondary,
              ),
            ),
            Text(
              '${_formatSize(widget.processedSizeBytes)} / ${_formatSize(widget.totalSizeBytes)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFamily: 'ProductSans',
                color: context.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: sizeProgress,
            backgroundColor: context.dividerColor,
            valueColor: AlwaysStoppedAnimation(Colors.green),
            minHeight: 6,
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentFileInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.backgroundSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Icon(
            _getFileIcon(),
            color: context.textTertiary,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.currentFileName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'ProductSans',
                    color: context.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.statusMessage,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'ProductSans',
                    color: context.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon() {
    final name = widget.currentFileName.toLowerCase();
    if (name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.gif') ||
        name.endsWith('.webp') ||
        name.endsWith('.heic')) {
      return Icons.image_outlined;
    } else if (name.endsWith('.mp4') ||
        name.endsWith('.mov') ||
        name.endsWith('.avi') ||
        name.endsWith('.mkv') ||
        name.endsWith('.webm')) {
      return Icons.videocam_outlined;
    } else if (name.endsWith('.pdf') ||
        name.endsWith('.doc') ||
        name.endsWith('.docx') ||
        name.endsWith('.xls') ||
        name.endsWith('.xlsx') ||
        name.endsWith('.ppt') ||
        name.endsWith('.pptx')) {
      return Icons.description_outlined;
    } else if (name.endsWith('.mp3') ||
        name.endsWith('.wav') ||
        name.endsWith('.aac') ||
        name.endsWith('.flac')) {
      return Icons.audiotrack_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  Widget _buildActionButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: widget.onCancel,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          side: BorderSide(color: AppColors.error),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          'Cancel',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'ProductSans',
            color: AppColors.error,
          ),
        ),
      ),
    );
  }

  Widget _buildCompleteState() {
    final successColor =
        context.isDarkMode ? AppColors.darkSuccess : AppColors.success;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: successColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: successColor, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${widget.totalFiles} files processed successfully',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'ProductSans',
                    color: context.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildStatCard(
              icon: Icons.storage_outlined,
              label: 'Total Size',
              value: _formatSize(widget.totalSizeBytes),
            ),
            const SizedBox(width: 12),
            _buildStatCard(
              icon: Icons.check_circle_outline,
              label: 'Status',
              value: 'Complete',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.backgroundSecondary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: context.textTertiary, size: 20),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'ProductSans',
                color: context.textTertiary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFamily: 'ProductSans',
                color: context.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }
}

class OperationProgressState {
  final int totalFiles;
  final int currentFile;
  final String currentFileName;
  final int totalSizeBytes;
  final int processedSizeBytes;
  final String statusMessage;
  final bool isProcessing;
  final bool isComplete;
  final bool isEncrypting;

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
  }) {
    return OperationProgressState(
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
}
