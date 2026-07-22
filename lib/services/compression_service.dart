import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_bicubic_resize/flutter_bicubic_resize.dart';
import 'package:path_provider/path_provider.dart';

class CompressionService {
  CompressionService._();
  static final CompressionService instance = CompressionService._();

  static const int _jpegQuality = 95;

  Future<String?> compressImage(String sourcePath) async {
    final compressedBytes = await compressImageToBytes(sourcePath);
    if (compressedBytes == null) return null;

    final extension = sourcePath.split('.').last.toLowerCase();
    final tempDir = await getTemporaryDirectory();
    final compressedPath =
        '${tempDir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final compressedFile = File(compressedPath);
    await compressedFile.writeAsBytes(compressedBytes);
    return compressedPath;
  }

  Future<Uint8List?> compressImageToBytes(String sourcePath) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        debugPrint('[Compression] Source file does not exist: $sourcePath');
        return null;
      }

      final bytes = await sourceFile.readAsBytes();
      final extension = sourcePath.split('.').last.toLowerCase();

      Uint8List? compressedBytes;

      if (extension == 'jpg' || extension == 'jpeg') {
        compressedBytes = await _compressJpegKeepOriginalSize(bytes);
      } else if (extension == 'png') {
        compressedBytes = bytes;
      } else {
        compressedBytes = await _compressJpegKeepOriginalSize(bytes);
      }

      if (compressedBytes == null) {
        debugPrint('[Compression] Failed to compress image: $sourcePath');
        return null;
      }

      debugPrint(
          '[Compression] Compressed image: $sourcePath (${bytes.length} -> ${compressedBytes.length} bytes)');
      return compressedBytes;
    } catch (e) {
      debugPrint('[Compression] Error compressing image: $e');
      return null;
    }
  }

  Future<Uint8List?> _compressJpegKeepOriginalSize(Uint8List bytes) async {
    try {
      // ponytail: resizeJpegAsync runs the native FFI pipeline in an isolate
      // (package ships the wrapper). Keeps the decode→resize→encode off the UI
      // thread during image import.
      final result = await BicubicResizer.resizeJpegAsync(
        jpegBytes: bytes,
        outputWidth: 4096,
        outputHeight: 4096,
        quality: _jpegQuality,
      );
      return result;
    } catch (e) {
      debugPrint('[Compression] JPEG compression error: $e');
      return null;
    }
  }

  Future<String?> compressVideo(String sourcePath) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        debugPrint('[Compression] Source file does not exist: $sourcePath');
        return null;
      }

      final tempDir = await getTemporaryDirectory();

      final outputPath =
          '${tempDir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.mp4';

      debugPrint(
          '[Compression] Compressing video: $sourcePath (preserving original resolution)');

      final process = await Process.start(
        'ffmpeg',
        [
          '-i',
          sourcePath,
          '-vcodec',
          'libx264',
          '-preset',
          'fast',
          '-crf',
          '18',
          '-acodec',
          'aac',
          '-b:a',
          '192k',
          '-movflags',
          '+faststart',
          '-y',
          outputPath,
        ],
      );

      final exitCode = await process.exitCode;

      if (exitCode == 0) {
        final outputFile = File(outputPath);
        if (await outputFile.exists()) {
          final fileSize = await sourceFile.length();
          final outputSize = await outputFile.length();
          debugPrint(
              '[Compression] Compressed video: $sourcePath (${fileSize ~/ (1024 * 1024)}MB -> ${outputSize ~/ (1024 * 1024)}MB)');
          return outputPath;
        }
      }

      debugPrint(
          '[Compression] FFmpeg video compression failed with code: $exitCode');
      return null;
    } catch (e) {
      debugPrint('[Compression] Video compression error: $e');
      return null;
    }
  }
}
