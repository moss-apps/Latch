import 'package:flutter/material.dart';
import '../models/operation_progress.dart';
import '../themes/app_colors.dart';

export '../models/operation_progress.dart';

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
  final VoidCallback? onMinimize;
  final VoidCallback? onDone;
  final OperationOutcome? outcome;

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
    this.onMinimize,
    this.onDone,
    this.outcome,
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
        top: false,
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
                            fontFamily: 'GoogleSansFlex',
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getSubtitle(),
                          style: TextStyle(
                            fontSize: 14,
                            fontFamily: 'GoogleSansFlex',
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
                    onPressed: widget.onDone ?? () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.accentColor,
                      elevation: 0,
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
                        fontFamily: 'GoogleSansFlex',
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                if (widget.onMinimize != null)
                  Center(
                    child: TextButton(
                      onPressed: widget.onMinimize,
                      child: const Text('Minimize'),
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
        color = widget.isEncrypting ? Colors.orange : context.accentColor;
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
    return widget.operationType.title;
  }

  String _getSubtitle() {
    if (widget.isComplete) {
      return switch (widget.outcome?.kind) {
        OperationOutcomeKind.error => 'Operation failed',
        OperationOutcomeKind.warning => 'Completed with issues',
        OperationOutcomeKind.info => 'Operation finished',
        _ => 'Completed successfully',
      };
    }
    final base = widget.totalFiles > 0
        ? '${widget.currentFile} of ${widget.totalFiles} files'
        : 'Working on files...';
    if (widget.isEncrypting) {
      return '$base - Encrypting...';
    }
    return base;
  }

  Widget _buildProgressSection(double progress, double sizeProgress) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              'Progress',
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'GoogleSansFlex',
                color: context.textSecondary,
              ),
            ),
            Text(
              widget.totalFiles > 0 || widget.totalSizeBytes > 0
                  ? '${(progress * 100).clamp(0, 100).toInt()}%'
                  : 'Working',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFamily: 'GoogleSansFlex',
                color: context.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: widget.totalFiles > 0 || widget.totalSizeBytes > 0
                ? progress
                : null,
            backgroundColor: context.dividerColor,
            valueColor: AlwaysStoppedAnimation(context.accentColor),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              'Data Processed',
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'GoogleSansFlex',
                color: context.textSecondary,
              ),
            ),
            Text(
              widget.totalSizeBytes > 0
                  ? '${_formatSize(widget.processedSizeBytes)} / ${_formatSize(widget.totalSizeBytes)}'
                  : 'Calculating...',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFamily: 'GoogleSansFlex',
                color: context.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: widget.totalSizeBytes > 0 ? sizeProgress : null,
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
                    fontFamily: 'GoogleSansFlex',
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
                    fontFamily: 'GoogleSansFlex',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(builder: (context, constraints) {
          final cancel = OperationCancelButton(onCancel: widget.onCancel);
          if (widget.onMinimize == null) {
            return SizedBox(width: double.infinity, child: cancel);
          }
          final minimize = OutlinedButton.icon(
            onPressed: widget.onMinimize,
            icon: const Icon(Icons.remove_rounded, size: 20),
            label: const Text('Minimize'),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.textPrimary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(color: context.borderColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
          if (constraints.maxWidth < 280 ||
              MediaQuery.textScalerOf(context).scale(14) > 20) {
            return Column(children: [
              SizedBox(width: double.infinity, child: cancel),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: minimize),
            ]);
          }
          return Row(children: [
            Expanded(child: cancel),
            const SizedBox(width: 12),
            Expanded(child: minimize),
          ]);
        }),
        if (widget.onCancel == null) ...[
          const SizedBox(height: 12),
          Text(
            'This operation cannot be cancelled safely. Minimize to keep browsing.',
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'GoogleSansFlex',
              color: context.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCompleteState() {
    final kind = widget.outcome?.kind;
    final successColor = switch (kind) {
      OperationOutcomeKind.error => AppColors.error,
      OperationOutcomeKind.warning => AppColors.warning,
      OperationOutcomeKind.info => context.accentColor,
      _ => context.isDarkMode ? AppColors.darkSuccess : AppColors.success,
    };
    final icon = switch (kind) {
      OperationOutcomeKind.error => Icons.error_outline,
      OperationOutcomeKind.warning => Icons.warning_amber_rounded,
      OperationOutcomeKind.info => Icons.info_outline,
      _ => Icons.check_circle,
    };
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
              Icon(icon, color: successColor, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.outcome?.message ??
                      '${widget.totalFiles} files processed successfully',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'GoogleSansFlex',
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
              value: widget.totalSizeBytes > 0
                  ? _formatSize(widget.totalSizeBytes)
                  : '—',
            ),
            const SizedBox(width: 12),
            _buildStatCard(
              icon: Icons.check_circle_outline,
              label: 'Status',
              value: kind == OperationOutcomeKind.error ? 'Failed' : 'Finished',
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
                fontFamily: 'GoogleSansFlex',
                color: context.textTertiary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFamily: 'GoogleSansFlex',
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

/// The deeper red keeps the white label readable in both app themes.
class OperationCancelButton extends StatelessWidget {
  const OperationCancelButton({super.key, this.onCancel, this.compact = false});

  final VoidCallback? onCancel;

  /// When true, keeps the button's default [FilledButton] size and shape so it
  /// matches a plain filled action (the floating panel's Dismiss button)
  /// instead of the sheet's full-width control geometry.
  final bool compact;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: onCancel == null
            ? 'Cancellation is not supported safely for this operation'
            : 'Cancel operation',
        child: FilledButton(
          onPressed: onCancel,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFB3261E),
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFF8C4542),
            disabledForegroundColor: Colors.white,
            padding: compact ? null : const EdgeInsets.symmetric(vertical: 16),
            shape: compact
                ? null
                : RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
          ),
          child: compact
              ? const Text('Cancel')
              : const Text(
                  'Cancel',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'GoogleSansFlex',
                  ),
                ),
        ),
      );
}
