import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart' as xml;

/// Result of an Office document conversion
class ConversionResult {
  final bool success;
  final String? pdfPath;
  final Uint8List? pdfData;
  final String? error;
  final bool requiresExternalApp;

  ConversionResult({
    required this.success,
    this.pdfPath,
    this.pdfData,
    this.error,
    this.requiresExternalApp = false,
  });
}

/// Supported Office file types for conversion
enum OfficeFileType {
  docx, // Microsoft Word
  doc, // Legacy Microsoft Word
  odt, // LibreOffice Writer
  xlsx, // Microsoft Excel
  xls, // Legacy Microsoft Excel
  ods, // LibreOffice Calc
  pptx, // Microsoft PowerPoint
  ppt, // Legacy Microsoft PowerPoint
  odp, // LibreOffice Impress
  rtf, // Rich Text Format
  unknown,
}

/// Service for converting Office documents to PDF
class OfficeConverterService {
  static final OfficeConverterService _instance =
      OfficeConverterService._internal();
  factory OfficeConverterService() => _instance;
  OfficeConverterService._internal();

  /// List of supported Office extensions
  static const List<String> supportedExtensions = [
    'docx', 'doc', 'odt', // Word processors
    'xlsx', 'xls', 'ods', // Spreadsheets
    'pptx', 'ppt', 'odp', // Presentations
    'rtf', // Rich text
  ];

  /// List of extensions that can be converted on-device
  static const List<String> convertibleExtensions = [
    'docx', 'odt', 'rtf', // Currently supported for on-device conversion
  ];

  /// Check if a file extension is an Office document
  static bool isOfficeDocument(String extension) {
    return supportedExtensions.contains(extension.toLowerCase());
  }

  /// Check if a file can be converted on-device
  static bool canConvertOnDevice(String extension) {
    return convertibleExtensions.contains(extension.toLowerCase());
  }

  /// Get the Office file type from extension
  static OfficeFileType getFileType(String extension) {
    switch (extension.toLowerCase()) {
      case 'docx':
        return OfficeFileType.docx;
      case 'doc':
        return OfficeFileType.doc;
      case 'odt':
        return OfficeFileType.odt;
      case 'xlsx':
        return OfficeFileType.xlsx;
      case 'xls':
        return OfficeFileType.xls;
      case 'ods':
        return OfficeFileType.ods;
      case 'pptx':
        return OfficeFileType.pptx;
      case 'ppt':
        return OfficeFileType.ppt;
      case 'odp':
        return OfficeFileType.odp;
      case 'rtf':
        return OfficeFileType.rtf;
      default:
        return OfficeFileType.unknown;
    }
  }

  /// Get a human-readable name for the file type
  static String getFileTypeName(String extension) {
    switch (extension.toLowerCase()) {
      case 'docx':
        return 'Microsoft Word Document';
      case 'doc':
        return 'Microsoft Word Document (Legacy)';
      case 'odt':
        return 'LibreOffice Writer Document';
      case 'xlsx':
        return 'Microsoft Excel Spreadsheet';
      case 'xls':
        return 'Microsoft Excel Spreadsheet (Legacy)';
      case 'ods':
        return 'LibreOffice Calc Spreadsheet';
      case 'pptx':
        return 'Microsoft PowerPoint Presentation';
      case 'ppt':
        return 'Microsoft PowerPoint Presentation (Legacy)';
      case 'odp':
        return 'LibreOffice Impress Presentation';
      case 'rtf':
        return 'Rich Text Format Document';
      default:
        return 'Office Document';
    }
  }

  /// Convert an Office document to PDF
  /// Returns ConversionResult with the PDF data or path
  Future<ConversionResult> convertToPdf(
    Uint8List fileData,
    String fileName,
    String extension,
  ) async {
    final fileType = getFileType(extension);

    try {
      switch (fileType) {
        case OfficeFileType.docx:
          return await _convertDocxToPdf(fileData, fileName);
        case OfficeFileType.odt:
          return await _convertOdtToPdf(fileData, fileName);
        case OfficeFileType.rtf:
          return await _convertRtfToPdf(fileData, fileName);
        case OfficeFileType.xlsx:
        case OfficeFileType.xls:
        case OfficeFileType.ods:
        case OfficeFileType.pptx:
        case OfficeFileType.ppt:
        case OfficeFileType.odp:
        case OfficeFileType.doc:
          // These formats require external app opening
          return ConversionResult(
            success: false,
            requiresExternalApp: true,
            error: 'This file format requires an external app to view.',
          );
        case OfficeFileType.unknown:
          return ConversionResult(
            success: false,
            error: 'Unknown file format',
          );
      }
    } catch (e) {
      debugPrint('Error converting document: $e');
      return ConversionResult(
        success: false,
        error: 'Failed to convert document: $e',
      );
    }
  }

  /// Convert DOCX to PDF
  Future<ConversionResult> _convertDocxToPdf(
      Uint8List fileData, String fileName) async {
    try {
      // Extract text content from DOCX
      final content = await _extractDocxContent(fileData);

      if (content.isEmpty) {
        return ConversionResult(
          success: false,
          error: 'Could not extract content from document',
        );
      }

      // Create PDF with extracted content
      final pdfData = await _createPdfFromContent(content, fileName);

      return ConversionResult(
        success: true,
        pdfData: pdfData,
      );
    } catch (e) {
      debugPrint('Error converting DOCX: $e');
      return ConversionResult(
        success: false,
        error: 'Failed to convert DOCX: $e',
      );
    }
  }

  /// Convert ODT to PDF
  Future<ConversionResult> _convertOdtToPdf(
      Uint8List fileData, String fileName) async {
    try {
      // Extract text content from ODT
      final content = await _extractOdtContent(fileData);

      if (content.isEmpty) {
        return ConversionResult(
          success: false,
          error: 'Could not extract content from document',
        );
      }

      // Create PDF with extracted content
      final pdfData = await _createPdfFromContent(content, fileName);

      return ConversionResult(
        success: true,
        pdfData: pdfData,
      );
    } catch (e) {
      debugPrint('Error converting ODT: $e');
      return ConversionResult(
        success: false,
        error: 'Failed to convert ODT: $e',
      );
    }
  }

  /// Convert RTF to PDF
  Future<ConversionResult> _convertRtfToPdf(
      Uint8List fileData, String fileName) async {
    try {
      // Extract plain text from RTF
      final content = _extractRtfContent(fileData);

      if (content.isEmpty) {
        return ConversionResult(
          success: false,
          error: 'Could not extract content from document',
        );
      }

      // Create PDF with extracted content
      final pdfData = await _createPdfFromContent([content], fileName);

      return ConversionResult(
        success: true,
        pdfData: pdfData,
      );
    } catch (e) {
      debugPrint('Error converting RTF: $e');
      return ConversionResult(
        success: false,
        error: 'Failed to convert RTF: $e',
      );
    }
  }

  /// Extract text content from DOCX file
  Future<List<String>> _extractDocxContent(Uint8List fileData) async {
    final List<String> paragraphs = [];

    try {
      // DOCX is a ZIP archive containing XML files
      final archive = ZipDecoder().decodeBytes(fileData);

      // Find the main document.xml file
      final documentFile = archive.findFile('word/document.xml');
      if (documentFile == null) {
        return paragraphs;
      }

      final content = String.fromCharCodes(documentFile.content);
      final document = xml.XmlDocument.parse(content);

      // Extract text from all <w:t> elements (text runs)
      final textElements = document.findAllElements('w:t');

      StringBuffer currentParagraph = StringBuffer();
      String? lastParent;

      for (final element in textElements) {
        // Check if we're in a new paragraph
        final paragraph = element.ancestors
            .whereType<xml.XmlElement>()
            .where((e) => e.name.local == 'p')
            .firstOrNull;
        final paragraphId = paragraph?.hashCode.toString();

        if (lastParent != null &&
            lastParent != paragraphId &&
            currentParagraph.isNotEmpty) {
          paragraphs.add(currentParagraph.toString().trim());
          currentParagraph = StringBuffer();
        }

        currentParagraph.write(element.innerText);
        lastParent = paragraphId;
      }

      // Add the last paragraph
      if (currentParagraph.isNotEmpty) {
        paragraphs.add(currentParagraph.toString().trim());
      }
    } catch (e) {
      debugPrint('Error extracting DOCX content: $e');
    }

    return paragraphs.where((p) => p.isNotEmpty).toList();
  }

  /// Extract text content from ODT file
  Future<List<String>> _extractOdtContent(Uint8List fileData) async {
    final List<String> paragraphs = [];

    try {
      // ODT is a ZIP archive containing XML files
      final archive = ZipDecoder().decodeBytes(fileData);

      // Find content.xml file
      final contentFile = archive.findFile('content.xml');
      if (contentFile == null) {
        return paragraphs;
      }

      final content = String.fromCharCodes(contentFile.content);
      final document = xml.XmlDocument.parse(content);

      // Extract text from all <text:p> elements
      final textElements = document.findAllElements('text:p');

      for (final element in textElements) {
        final text = element.innerText.trim();
        if (text.isNotEmpty) {
          paragraphs.add(text);
        }
      }
    } catch (e) {
      debugPrint('Error extracting ODT content: $e');
    }

    return paragraphs;
  }

  /// Extract plain text from RTF
  String _extractRtfContent(Uint8List fileData) {
    try {
      final content = String.fromCharCodes(fileData);

      // Simple RTF text extraction - remove control words and groups
      final buffer = StringBuffer();
      int depth = 0;
      bool inControlWord = false;

      for (int i = 0; i < content.length; i++) {
        final char = content[i];

        if (char == '{') {
          depth++;
          inControlWord = false;
        } else if (char == '}') {
          depth--;
          inControlWord = false;
        } else if (char == '\\') {
          inControlWord = true;
        } else if (inControlWord &&
            (char == ' ' || char == '\n' || char == '\r')) {
          inControlWord = false;
        } else if (!inControlWord && depth <= 1) {
          // Only include text at top level
          if (char != '\n' && char != '\r') {
            buffer.write(char);
          } else {
            buffer.write('\n');
          }
        }
      }

      return buffer.toString().trim();
    } catch (e) {
      debugPrint('Error extracting RTF content: $e');
      return '';
    }
  }

  /// Create PDF from extracted text content
  Future<Uint8List> _createPdfFromContent(
      List<String> paragraphs, String fileName) async {
    // Create a new PDF document
    final PdfDocument document = PdfDocument();

    // Set document properties
    document.documentInformation.title = fileName;
    document.documentInformation.creator = 'Latch App';

    // Add a page
    PdfPage page = document.pages.add();
    final pageSize = page.getClientSize();

    // Try to load custom font, otherwise use standard
    PdfFont titleFont;
    PdfFont bodyFont;
    bool usingStandardFont = true;

    try {
      final fontData = await rootBundle.load('fonts/productsans_regular.ttf');
      final fontBytes = fontData.buffer.asUint8List();

      titleFont = PdfTrueTypeFont(fontBytes, 14, style: PdfFontStyle.bold);
      bodyFont = PdfTrueTypeFont(fontBytes, 11);
      usingStandardFont = false;
    } catch (e) {
      debugPrint('Could not load custom font for PDF: $e');
      titleFont = PdfStandardFont(PdfFontFamily.helvetica, 14,
          style: PdfFontStyle.bold);
      bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 11);
    }

    // Text formatting
    final PdfStringFormat format = PdfStringFormat();
    format.lineAlignment = PdfVerticalAlignment.top;
    format.paragraphIndent = 0;

    double yPosition = 20;
    const double lineHeight = 16;
    const double paragraphSpacing = 12;
    const double marginLeft = 40;
    const double marginRight = 40;
    final textWidth = pageSize.width - marginLeft - marginRight;

    // Helper to sanitize text
    String sanitize(String text) {
      // Always remove the Unicode replacement character (0xFFFD) as it often causes font issues
      var processed = text.replaceAll('\uFFFD', '?');

      if (!usingStandardFont) return processed;

      // Standard PDF fonts only support Latin-1
      return processed.replaceAll(RegExp(r'[^\x00-\xFF]'), '?');
    }

    // Draw title
    final titleText = sanitize(fileName.replaceAll(RegExp(r'\.[^.]+$'), ''));
    page.graphics.drawString(
      titleText,
      titleFont,
      bounds: Rect.fromLTWH(marginLeft, yPosition, textWidth, 30),
      format: format,
    );
    yPosition += 40;

    // Draw separator line
    page.graphics.drawLine(
      PdfPen(PdfColor(200, 200, 200), width: 0.5),
      Offset(marginLeft, yPosition),
      Offset(pageSize.width - marginRight, yPosition),
    );
    yPosition += 20;

    // Draw content paragraphs
    for (final rawParagraph in paragraphs) {
      if (rawParagraph.isEmpty) continue;

      final paragraph = sanitize(rawParagraph);

      // Calculate text height
      final textSize = bodyFont.measureString(
        paragraph,
        layoutArea: Size(textWidth, double.infinity),
        format: format,
      );

      // Check if we need a new page
      if (yPosition + textSize.height > pageSize.height - 40) {
        page = document.pages.add();
        yPosition = 40;
      }

      // Draw paragraph
      page.graphics.drawString(
        paragraph,
        bodyFont,
        bounds: Rect.fromLTWH(
            marginLeft, yPosition, textWidth, textSize.height + lineHeight),
        format: format,
      );

      yPosition += textSize.height + paragraphSpacing;
    }

    // Add page numbers
    final pageCount = document.pages.count;
    final pageNumberFont = PdfStandardFont(PdfFontFamily.helvetica, 9);
    for (int i = 0; i < pageCount; i++) {
      final pg = document.pages[i];
      final pgSize = pg.getClientSize();
      pg.graphics.drawString(
        'Page ${i + 1} of $pageCount',
        pageNumberFont,
        bounds: Rect.fromLTWH(0, pgSize.height - 20, pgSize.width, 20),
        format: PdfStringFormat(
          alignment: PdfTextAlignment.center,
          lineAlignment: PdfVerticalAlignment.middle,
        ),
      );
    }

    // Save and return the PDF bytes
    final pdfBytes = Uint8List.fromList(await document.save());
    document.dispose();

    return pdfBytes;
  }

  /// Save PDF data to a temporary file
  Future<String> savePdfToTemp(
      Uint8List pdfData, String originalFileName) async {
    final tempDir = await getTemporaryDirectory();
    final pdfFileName =
        '${originalFileName.replaceAll(RegExp(r'\.[^.]+$'), '')}_converted.pdf';
    final pdfFile = File('${tempDir.path}/$pdfFileName');
    await pdfFile.writeAsBytes(pdfData);
    return pdfFile.path;
  }
}
