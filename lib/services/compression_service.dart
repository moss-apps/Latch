import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_bicubic_resize/flutter_bicubic_resize.dart';
import 'package:path_provider/path_provider.dart';
import 'encryption_service.dart';

class CompressionService {
  CompressionService._();
  static final CompressionService instance = CompressionService._();

  static const int _jpegQuality = 95;
  final Set<Process> _processes = {};

  void clearSensitiveState() {
    for (final process in _processes) {
      process.kill(ProcessSignal.sigkill);
    }
    _processes.clear();
  }

  Future<String?> compressImage(String sourcePath) async {
    final crypto = EncryptionService.instance;
    final generation = crypto.cacheGeneration;
    final compressedBytes = await compressImageToBytes(sourcePath);
    if (compressedBytes == null) return null;

    final extension = sourcePath.split('.').last.toLowerCase();
    final tempDir = await getTemporaryDirectory();
    final compressedPath =
        '${tempDir.path}/lkr_compressed_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final compressedFile = File(compressedPath);
    if (!crypto.isCurrentSession(generation)) return null;
    await compressedFile.writeAsBytes(compressedBytes);
    if (!crypto.isCurrentSession(generation)) {
      if (await compressedFile.exists()) await compressedFile.delete();
      return null;
    }
    return compressedPath;
  }

  Future<Uint8List?> compressImageToBytes(String sourcePath) async {
    final crypto = EncryptionService.instance;
    final generation = crypto.cacheGeneration;
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
      if (!crypto.isCurrentSession(generation)) {
        compressedBytes.fillRange(0, compressedBytes.length, 0);
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
      // FFI resize runs in an isolate, off the UI thread during import.
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
    final crypto = EncryptionService.instance;
    final generation = crypto.cacheGeneration;
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        debugPrint('[Compression] Source file does not exist: $sourcePath');
        return null;
      }

      final tempDir = await getTemporaryDirectory();

      final outputPath =
          '${tempDir.path}/lkr_compressed_${DateTime.now().millisecondsSinceEpoch}.mp4';

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
      _processes.add(process);
      if (!crypto.isCurrentSession(generation)) {
        process.kill(ProcessSignal.sigkill);
      }
      final int exitCode;
      try {
        exitCode = await process.exitCode;
      } finally {
        _processes.remove(process);
      }
      if (!crypto.isCurrentSession(generation)) {
        final output = File(outputPath);
        if (await output.exists()) await output.delete();
        return null;
      }

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
