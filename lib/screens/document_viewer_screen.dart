import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import '../utils/path_utils.dart';
import 'package:pdfrx/pdfrx.dart';
import '../models/vaulted_file.dart';
import '../providers/vault_providers.dart';
import '../services/auto_kill_service.dart';
import '../services/office_converter_service.dart';
import '../services/vault_service.dart';
import '../themes/app_colors.dart';
import '../utils/toast_utils.dart';
import '../widgets/conversion_warning_dialog.dart';
import '../widgets/file_info_sheet.dart';

/// Document viewer for PDFs and text files
class DocumentViewerScreen extends ConsumerStatefulWidget {
  final VaultedFile file;

  /// A decrypted file prepared by the caller. When supplied, decryption is not
  /// performed on the main thread.
  final File? decryptedFile;

  const DocumentViewerScreen({
    super.key,
    required this.file,
    this.decryptedFile,
  });

  @override
  ConsumerState<DocumentViewerScreen> createState() =>
      _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends ConsumerState<DocumentViewerScreen> {
  bool _isLoading = true;
  bool _isConverting = false;
  String? _error;
  Uint8List? _decryptedData;
  String? _textContent;
  PdfViewerController? _pdfController;
  int _currentPage = 1;
  int _totalPages = 1;
  bool _isOfficeDocument = false;
  // PdfViewer.file so pdfrx loads off the main isolate (PdfViewer.data ANRs on big PDFs).
  String? _pdfPath;
  String? _convertedPdfPath;

  @override
  void initState() {
    super.initState();
    _pdfController = PdfViewerController();
    _isOfficeDocument =
        OfficeConverterService.isOfficeDocument(widget.file.extension);

    if (_isOfficeDocument) {
      // For Office documents, show warning dialog first
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showConversionDialog();
      });
    } else {
      _loadDocument();
    }
  }

  @override
  void dispose() {
    // Clear decrypted data from memory
    _decryptedData = null;
    // Clean up the converted-PDF temp file we wrote.
    final convPath = _convertedPdfPath;
    if (convPath != null) {
      try {
        File(convPath).deleteSync();
      } catch (_) {}
    }
    // Clean up temp decrypted files to prevent disk leaks
    _cleanupTempFiles();
    super.dispose();
  }

  void _cleanupTempFiles() {
    try {
      VaultService.instance.cleanupTemp();
    } catch (e) {
      debugPrint('Error cleaning up temp files: $e');
    }
  }

  /// Show conversion warning dialog for Office documents
  Future<void> _showConversionDialog() async {
    final canConvert =
        OfficeConverterService.canConvertOnDevice(widget.file.extension);

    final shouldConvert = await showConversionWarningDialog(
      context: context,
      fileName: widget.file.originalName,
      extension: widget.file.extension,
      onOpenExternal: !canConvert ? () => _openWithExternalApp() : null,
    );

    if (!mounted) return;

    if (shouldConvert) {
      await _loadAndConvertDocument();
    } else if (!canConvert) {
      // User chose external app or cancelled - stay on screen to show options
      setState(() {
        _isLoading = false;
      });
    } else {
      // User cancelled
      Navigator.pop(context);
    }
  }

  /// Load and convert Office document to PDF
  Future<void> _loadAndConvertDocument() async {
    setState(() {
      _isLoading = true;
      _isConverting = true;
      _error = null;
    });

    try {
      // Get file data. Prefer the decrypted file prepared by the caller, and
      // otherwise read/convert in an isolate where possible.
      Uint8List? fileData;
      if (widget.decryptedFile != null) {
        fileData = await widget.decryptedFile!.readAsBytes();
      } else if (widget.file.isEncrypted && widget.file.encryptionIv != null) {
        final decryptedFile =
            await ref.read(vaultServiceProvider).getVaultedFile(widget.file.id);
        fileData = decryptedFile != null
            ? await decryptedFile.readAsBytes()
            : await ref
                .read(vaultServiceProvider)
                .getDecryptedFileData(widget.file.id);
      } else {
        fileData = await File(widget.file.vaultPath).readAsBytes();
      }

      if (fileData == null) {
        setState(() {
          _error = 'Failed to read document';
          _isLoading = false;
          _isConverting = false;
        });
        return;
      }

      // Convert to PDF
      final converter = OfficeConverterService();
      final result = await converter.convertToPdf(
        fileData,
        widget.file.originalName,
        widget.file.extension,
      );

      if (!mounted) return;

      if (result.success && result.pdfData != null) {
        // Write the converted PDF to a temp file so pdfrx can stream it
        // instead of parsing the bytes on the main isolate.
        final tempDir = await Directory.systemTemp.createTemp('lkr_conv');
        final tempPath = '${tempDir.path}/${widget.file.originalName}.pdf';
        await File(tempPath).writeAsBytes(result.pdfData!);
        if (!mounted) {
          await tempDir.delete(recursive: true);
          return;
        }
        setState(() {
          _convertedPdfPath = tempPath;
          _isLoading = false;
          _isConverting = false;
        });
      } else if (result.requiresExternalApp) {
        setState(() {
          _error = result.error ?? 'This format requires an external app';
          _isLoading = false;
          _isConverting = false;
        });
      } else {
        setState(() {
          _error = result.error ?? 'Failed to convert document';
          _isLoading = false;
          _isConverting = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to convert document';
        _isLoading = false;
        _isConverting = false;
      });
    }
  }

  Future<void> _loadDocument() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (_isPdf) {
        // PDFs: resolve the file path only. Reading bytes into a Uint8List
        // forced PdfViewer.data to parse on the main isolate (ANR on large
        // PDFs). PdfViewer.file lets pdfrx load in the background.
        if (widget.decryptedFile != null) {
          _pdfPath = widget.decryptedFile!.path;
        } else if (widget.file.isEncrypted &&
            widget.file.encryptionIv != null) {
          final decryptedFile = await ref
              .read(vaultServiceProvider)
              .getVaultedFile(widget.file.id);
          if (decryptedFile == null || !await decryptedFile.exists()) {
            setState(() {
              _error = 'Failed to decrypt document';
              _isLoading = false;
            });
            return;
          }
          _pdfPath = decryptedFile.path;
        } else {
          _pdfPath = widget.file.vaultPath;
        }
      } else if (_isTextFile) {
        Uint8List? bytes;
        if (widget.decryptedFile != null) {
          bytes = await widget.decryptedFile!.readAsBytes();
        } else if (widget.file.isEncrypted &&
            widget.file.encryptionIv != null) {
          final decryptedFile = await ref
              .read(vaultServiceProvider)
              .getVaultedFile(widget.file.id);
          bytes = decryptedFile != null
              ? await decryptedFile.readAsBytes()
              : await ref
                  .read(vaultServiceProvider)
                  .getDecryptedFileData(widget.file.id);
          if (bytes == null) {
            setState(() {
              _error = 'Failed to decrypt document';
              _isLoading = false;
            });
            return;
          }
        } else {
          bytes = await File(widget.file.vaultPath).readAsBytes();
        }
        _decryptedData = bytes;
        await _loadTextContent();
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _error = 'Failed to load document';
        _isLoading = false;
      });
    }
  }

  bool get _isPdf =>
      widget.file.extension.toLowerCase() == 'pdf' ||
      widget.file.mimeType == 'application/pdf';

  bool get _isTextFile {
    final ext = widget.file.extension.toLowerCase();
    return ext == 'txt' ||
        ext == 'md' ||
        ext == 'json' ||
        ext == 'xml' ||
        ext == 'csv' ||
        ext == 'log' ||
        widget.file.mimeType.startsWith('text/');
  }

  bool get _isConvertedPdf => _convertedPdfPath != null;

  Future<void> _loadTextContent() async {
    try {
      final bytes = _decryptedData;
      if (bytes != null) {
        _textContent = String.fromCharCodes(bytes);
      } else {
        final file = File(widget.file.vaultPath);
        _textContent = await file.readAsString();
      }
    } catch (e) {
      debugPrint('Error reading text file: $e');
      _textContent = 'Unable to read file content';
    }
  }

  void _toggleFavorite() async {
    await ref
        .read(vaultNotifierProvider.notifier)
        .toggleFavorite(widget.file.id);
    ToastUtils.showSuccess(
      widget.file.isFavorite ? 'Removed from favorites' : 'Added to favorites',
    );
  }

  Future<void> _exportToDownloads() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          content: Row(
            children: [
              CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(AppColors.accent)),
              const SizedBox(width: 20),
              Expanded(
                  child: Text('Exporting ${widget.file.originalName}...',
                      style: const TextStyle(fontFamily: 'ProductSans'))),
            ],
          ),
        ),
      );

      final downloadsDir = await PathUtils.getDownloadsDirectory();

      if (downloadsDir == null) {
        if (mounted) Navigator.pop(context);
        ToastUtils.showError('Could not access Downloads folder');
        return;
      }

      final destinationPath =
          '${downloadsDir.path}/${widget.file.originalName}';
      final vaultService = ref.read(vaultServiceProvider);
      final exportedFile =
          await vaultService.exportFile(widget.file.id, destinationPath);

      if (mounted) Navigator.pop(context);

      if (exportedFile != null) {
        ToastUtils.showSuccess(
            'Exported to Downloads/${widget.file.originalName}');
      } else {
        ToastUtils.showError('Failed to export file');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint('Error exporting file: $e');
      ToastUtils.showError('Failed to export file');
    }
  }

  Future<void> _openWithExternalApp() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          content: Row(
            children: [
              CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(AppColors.accent)),
              const SizedBox(width: 20),
              Expanded(
                  child: Text('Preparing ${widget.file.originalName}...',
                      style: const TextStyle(fontFamily: 'ProductSans'))),
            ],
          ),
        ),
      );

      final decryptedFile = widget.decryptedFile ??
          await ref.read(vaultServiceProvider).getVaultedFile(widget.file.id);

      if (mounted) Navigator.pop(context);

      if (decryptedFile != null && await decryptedFile.exists()) {
        final result = await AutoKillService.runSafe(
            () => OpenFilex.open(decryptedFile.path));
        if (result.type != ResultType.done) {
          ToastUtils.showError('No app found to open this file type');
        }
      } else {
        ToastUtils.showError('Failed to prepare file');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint('Error opening file: $e');
      ToastUtils.showError('Failed to open file');
    }
  }

  void _showFileInfo() {
    FileInfoSheet.show(
      context,
      widget.file,
      title: 'Document Information',
      extraRows: (_isPdf && _totalPages > 0)
          ? [('Pages', _totalPages.toString())]
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: context.textPrimary,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.file.originalName,
              style: const TextStyle(
                fontFamily: 'ProductSans',
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (_isPdf && _totalPages > 0)
              Text(
                'Page $_currentPage of $_totalPages',
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  fontSize: 12,
                  color: context.textTertiary,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              widget.file.isFavorite ? Icons.favorite : Icons.favorite_border,
              color: widget.file.isFavorite ? Colors.red : null,
            ),
            onPressed: _toggleFavorite,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showFileInfo,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.accent),
            const SizedBox(height: 16),
            Text(
              _isConverting ? 'Converting to PDF...' : 'Loading document...',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: context.textSecondary,
              ),
            ),
            if (_isConverting) ...[
              const SizedBox(height: 8),
              Text(
                'This may take a moment',
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  fontSize: 12,
                  color: context.textTertiary,
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: context.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadDocument,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_isPdf) {
      return _buildPdfViewer();
    } else if (_isConvertedPdf) {
      return _buildConvertedPdfViewer();
    } else if (_isTextFile) {
      return _buildTextViewer();
    } else {
      return _buildUnsupportedViewer();
    }
  }

  Widget _buildConvertedPdfViewer() {
    if (_convertedPdfPath == null) {
      return Center(
        child: Text(
          'No PDF data available',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textSecondary,
          ),
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: context.accentColor.withValues(alpha: 0.1),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: context.accentColor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Converted from ${widget.file.extension.toUpperCase()} to PDF',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    color: context.accentColor.withValues(alpha: 0.8),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        // PDF viewer
        Expanded(
          child: PdfViewer.file(
            _convertedPdfPath!,
            controller: _pdfController,
            params: PdfViewerParams(
              pageDropShadow: BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
              scrollPhysics: const ClampingScrollPhysics(),
              viewerOverlayBuilder: (context, size, handleLinkTap) => [
                PdfViewerScrollThumb(
                  controller: _pdfController!,
                  thumbBuilder: (context, thumbSize, pageNumber, controller) =>
                      _buildScrollThumb(thumbSize, pageNumber),
                ),
              ],
              onViewerReady: (document, controller) {
                setState(() {
                  _totalPages = document.pages.length;
                });
              },
              onPageChanged: (page) {
                setState(() {
                  _currentPage = page ?? 1;
                });
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPdfViewer() {
    if (_pdfPath == null) {
      return Center(
        child: Text(
          'No PDF data available',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textSecondary,
          ),
        ),
      );
    }

    return PdfViewer.file(
      _pdfPath!,
      controller: _pdfController,
      params: PdfViewerParams(
        pageDropShadow: BoxShadow(
          color: Colors.black.withValues(alpha: 0.1),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
        scrollPhysics: const ClampingScrollPhysics(),
        viewerOverlayBuilder: (context, size, handleLinkTap) => [
          PdfViewerScrollThumb(
            controller: _pdfController!,
            thumbBuilder: (context, thumbSize, pageNumber, controller) =>
                _buildScrollThumb(thumbSize, pageNumber),
          ),
        ],
        onViewerReady: (document, controller) {
          setState(() {
            _totalPages = document.pages.length;
          });
        },
        onPageChanged: (page) {
          setState(() {
            _currentPage = page ?? 1;
          });
        },
      ),
    );
  }

  Widget _buildTextViewer() {
    return Container(
      color: context.backgroundColor,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          _textContent ?? 'No content',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
            color: context.textPrimary,
            height: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildUnsupportedViewer() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _getDocumentIcon(),
            size: 80,
            color: _getDocumentColor(),
          ),
          const SizedBox(height: 24),
          Text(
            widget.file.originalName,
            style: TextStyle(
              fontFamily: 'ProductSans',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            widget.file.formattedSize,
            style: TextStyle(
              fontFamily: 'ProductSans',
              color: context.textTertiary,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _getDocumentColor().withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              widget.file.extension.toUpperCase(),
              style: TextStyle(
                fontFamily: 'ProductSans',
                fontWeight: FontWeight.w600,
                color: _getDocumentColor(),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Preview not available for this document type',
            style: TextStyle(
              fontFamily: 'ProductSans',
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _exportToDownloads,
                icon: const Icon(Icons.download),
                label: const Text('Export'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: _openWithExternalApp,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open with...'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  side: BorderSide(color: AppColors.accent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScrollThumb(Size thumbSize, int? pageNumber) {
    return Container(
      width: thumbSize.width,
      height: thumbSize.height,
      decoration: BoxDecoration(
        color: context.backgroundColor,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: context.dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Text(
          pageNumber?.toString() ?? '',
          style: TextStyle(
            fontSize: 12,
            color: context.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  IconData _getDocumentIcon() {
    switch (widget.file.extension.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'txt':
      case 'md':
        return Icons.text_snippet;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getDocumentColor() {
    switch (widget.file.extension.toLowerCase()) {
      case 'pdf':
        return Colors.red;
      case 'doc':
      case 'docx':
        return Colors.blue;
      case 'xls':
      case 'xlsx':
        return Colors.green;
      case 'ppt':
      case 'pptx':
        return Colors.orange;
      case 'txt':
      case 'md':
        return Colors.grey;
      default:
        return Colors.blueGrey;
    }
  }
}
