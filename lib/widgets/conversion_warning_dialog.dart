import 'package:flutter/material.dart';
import '../themes/app_colors.dart';
import '../services/office_converter_service.dart';

/// Dialog shown before converting Office documents to PDF
class ConversionWarningDialog extends StatelessWidget {
  final String fileName;
  final String extension;
  final VoidCallback onConvert;
  final VoidCallback onCancel;
  final VoidCallback? onOpenExternal;

  const ConversionWarningDialog({
    super.key,
    required this.fileName,
    required this.extension,
    required this.onConvert,
    required this.onCancel,
    this.onOpenExternal,
  });

  @override
  Widget build(BuildContext context) {
    final fileTypeName = OfficeConverterService.getFileTypeName(extension);
    final canConvert = OfficeConverterService.canConvertOnDevice(extension);

    return AlertDialog(
      backgroundColor: context.backgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(
            Icons.transform,
            color: AppColors.accent,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Convert to PDF',
              style: TextStyle(
                fontFamily: 'ProductSans',
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
                fontSize: 20,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // File info card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.backgroundSecondary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _getFileColor(extension).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _getFileIcon(extension),
                    color: _getFileColor(extension),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName,
                        style: TextStyle(
                          fontFamily: 'ProductSans',
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        fileTypeName,
                        style: TextStyle(
                          fontFamily: 'ProductSans',
                          color: context.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Message
          Text(
            canConvert
                ? 'This document will be converted to PDF for viewing. The conversion extracts text content while preserving basic formatting.'
                : 'This document format cannot be converted on-device. Would you like to open it with an external app?',
            style: TextStyle(
              fontFamily: 'ProductSans',
              color: context.textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 16),

          // Info button
          Builder(
            builder: (context) => InkWell(
              onTap: () => _showWhyConversionDialog(context),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: context.accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: context.accentColor,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Why is this needed?',
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        color: context.accentColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (!canConvert && extension.toLowerCase() != 'doc') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Complex formatting may not be fully preserved.',
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        color: Colors.orange.shade800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
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
        if (!canConvert && onOpenExternal != null)
          OutlinedButton.icon(
            onPressed: onOpenExternal,
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Open External'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.blue,
              side: const BorderSide(color: Colors.blue),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        if (canConvert)
          ElevatedButton.icon(
            onPressed: onConvert,
            icon: const Icon(Icons.picture_as_pdf, size: 18),
            label: const Text('Convert'),
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
              'Security First',
              'Converting documents locally keeps your files secure. No data is sent to external servers.',
            ),
            const SizedBox(height: 16),
            _buildExplanationItem(
              context,
              Icons.devices,
              'Universal Viewing',
              'PDF is a universal format that works consistently across all devices without needing special software.',
            ),
            const SizedBox(height: 16),
            _buildExplanationItem(
              context,
              Icons.lock,
              'Vault Protection',
              'Your original encrypted document remains safe in the vault. Only a temporary PDF is created for viewing.',
            ),
            const SizedBox(height: 16),
            _buildExplanationItem(
              context,
              Icons.warning_amber,
              'Limitations',
              'Complex formatting, images, charts, and special fonts may not be perfectly preserved during conversion.',
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

/// Shows the conversion warning dialog and returns true if conversion should proceed
Future<bool> showConversionWarningDialog({
  required BuildContext context,
  required String fileName,
  required String extension,
  VoidCallback? onOpenExternal,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => ConversionWarningDialog(
      fileName: fileName,
      extension: extension,
      onConvert: () => Navigator.pop(context, true),
      onCancel: () => Navigator.pop(context, false),
      onOpenExternal: onOpenExternal != null
          ? () {
              Navigator.pop(context, false);
              onOpenExternal();
            }
          : null,
    ),
  );
  return result ?? false;
}
