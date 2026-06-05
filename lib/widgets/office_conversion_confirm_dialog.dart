import 'package:flutter/material.dart';
import '../services/file_import_service.dart';
import '../themes/app_colors.dart';

/// Dialog shown to confirm conversion of Office documents during import
class OfficeConversionConfirmDialog extends StatelessWidget {
  final List<OfficeFileInfo> officeFiles;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const OfficeConversionConfirmDialog({
    super.key,
    required this.officeFiles,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final convertibleCount =
        officeFiles.where((f) => f.canConvertOnDevice).length;
    final nonConvertibleCount = officeFiles.length - convertibleCount;

    return AlertDialog(
      backgroundColor: context.backgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.transform, color: AppColors.accent, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Office Documents Detected',
              style: TextStyle(
                fontFamily: 'ProductSans',
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The following Office documents will be converted to PDF for secure storage and easy viewing:',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: context.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),

            // File list
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: context.backgroundSecondary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(12),
                itemCount: officeFiles.length,
                separatorBuilder: (_, __) => const Divider(height: 16),
                itemBuilder: (context, index) {
                  final file = officeFiles[index];
                  return Row(
                    children: [
                      Icon(
                        _getFileIcon(file.extension),
                        color: _getFileColor(file.extension),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              file.fileName,
                              style: TextStyle(
                                fontFamily: 'ProductSans',
                                fontWeight: FontWeight.w500,
                                color: context.textPrimary,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              file.typeName,
                              style: TextStyle(
                                fontFamily: 'ProductSans',
                                color: context.textTertiary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!file.canConvertOnDevice)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Skip',
                            style: TextStyle(
                              fontFamily: 'ProductSans',
                              color: Colors.orange.shade800,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '→ PDF',
                            style: TextStyle(
                              fontFamily: 'ProductSans',
                              color: Colors.green.shade800,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            // Summary
            if (convertibleCount > 0)
              _buildSummaryItem(
                context,
                Icons.check_circle_outline,
                Colors.green,
                '$convertibleCount file(s) will be converted to PDF',
              ),
            if (nonConvertibleCount > 0) ...[
              const SizedBox(height: 8),
              _buildSummaryItem(
                context,
                Icons.warning_amber,
                Colors.orange,
                '$nonConvertibleCount file(s) cannot be converted (unsupported format)',
              ),
            ],

            const SizedBox(height: 16),

            // Info button
            InkWell(
              onTap: () => _showWhyConversionDialog(context),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Why convert to PDF?',
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        color: Colors.blue,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: Text(
            'Cancel',
            style: TextStyle(
              fontFamily: 'ProductSans',
              color: context.textSecondary,
            ),
          ),
        ),
        ElevatedButton.icon(
          onPressed: onConfirm,
          icon: const Icon(Icons.picture_as_pdf, size: 18),
          label: Text('Convert & Import ($convertibleCount)'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryItem(
      BuildContext context, IconData icon, Color color, String text) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'ProductSans',
              color: context.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  void _showWhyConversionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.backgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.help_outline, color: AppColors.accent),
            const SizedBox(width: 12),
            Text(
              'Why Convert to PDF?',
              style: TextStyle(
                fontFamily: 'ProductSans',
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildExplanationItem(
              context,
              Icons.security,
              'Secure & Private',
              'Conversion happens entirely on your device. No data is sent to external servers.',
            ),
            const SizedBox(height: 16),
            _buildExplanationItem(
              context,
              Icons.visibility,
              'Easy Viewing',
              'PDF files can be viewed directly in the app without requiring external software.',
            ),
            const SizedBox(height: 16),
            _buildExplanationItem(
              context,
              Icons.devices,
              'Universal Format',
              'PDF works consistently across all devices and platforms.',
            ),
            const SizedBox(height: 16),
            _buildExplanationItem(
              context,
              Icons.warning_amber,
              'Limitations',
              'Complex formatting, images, and special fonts may not be perfectly preserved.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Got it',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: AppColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExplanationItem(
      BuildContext context, IconData icon, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.accent, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  color: context.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _getFileIcon(String extension) {
    switch (extension.toLowerCase()) {
      case 'docx':
      case 'doc':
      case 'odt':
      case 'rtf':
        return Icons.description;
      case 'xlsx':
      case 'xls':
      case 'ods':
        return Icons.table_chart;
      case 'pptx':
      case 'ppt':
      case 'odp':
        return Icons.slideshow;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileColor(String extension) {
    switch (extension.toLowerCase()) {
      case 'docx':
      case 'doc':
        return Colors.blue;
      case 'odt':
      case 'rtf':
        return Colors.blueGrey;
      case 'xlsx':
      case 'xls':
        return Colors.green;
      case 'ods':
        return Colors.teal;
      case 'pptx':
      case 'ppt':
        return Colors.orange;
      case 'odp':
        return Colors.deepOrange;
      default:
        return Colors.grey;
    }
  }
}

/// Shows the Office conversion confirmation dialog
/// Returns true if user confirms, false if cancelled
Future<bool> showOfficeConversionConfirmDialog({
  required BuildContext context,
  required List<OfficeFileInfo> officeFiles,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => OfficeConversionConfirmDialog(
      officeFiles: officeFiles,
      onConfirm: () => Navigator.pop(context, true),
      onCancel: () => Navigator.pop(context, false),
    ),
  );
  return result ?? false;
}
