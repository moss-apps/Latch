import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/vaulted_file.dart';
import '../models/vault_folder.dart';
import 'auto_kill_service.dart';
import 'decoy_service.dart';
import 'media_scanner_service.dart';
import 'office_converter_service.dart';
import 'permission_service.dart';
import 'vault_service.dart';

/// Service for importing files from various sources
class FileImportService {
  FileImportService._();
  static final FileImportService instance = FileImportService._();

  final ImagePicker _imagePicker = ImagePicker();
  final PermissionService _permissionService = PermissionService.instance;
  final VaultService _vaultService = VaultService.instance;
  final MediaScannerService _mediaScannerService = MediaScannerService.instance;
  final DecoyService _decoyService = DecoyService.instance;

  /// Import images from gallery using photo_manager for proper deletion support
  Future<ImportResult> importImagesFromGallery({
    bool deleteOriginals = true,
    Function(int current, int total)? onProgress,
  }) async {
    try {
      // Request permission
      final permission = await AutoKillService.runSafe(
          () => PhotoManager.requestPermissionExtend());
      if (!permission.hasAccess) {
        return ImportResult(
          success: false,
          error: 'Photo library permission denied',
          importedFiles: [],
        );
      }

      // Check if we have all files access for deletion
      final hasAllFilesAccess = await _permissionService.hasAllFilesAccess();
      if (deleteOriginals && !hasAllFilesAccess) {
        debugPrint(
            '[FileImport] Warning: All Files Access not granted. Original files may not be deleted from gallery.');
      }

      // Pick multiple images using image_picker for UI
      final images =
          await AutoKillService.runSafe(() => _imagePicker.pickMultiImage(
                imageQuality: 100,
              ));

      if (images.isEmpty) {
        return ImportResult(
          success: true,
          importedFiles: [],
          message: 'No images selected',
        );
      }

      debugPrint('[FileImport] Selected ${images.length} images for import');

      // Track assets to delete BEFORE importing (so we can find them by filename)
      List<AssetEntity> assetsToDelete = [];
      if (deleteOriginals) {
        final fileNames = images.map((i) => i.name).toList();
        debugPrint(
            '[FileImport] Looking for assets to delete with names: $fileNames');
        assetsToDelete =
            await _findMatchingAssets(fileNames, RequestType.image);
        debugPrint(
            '[FileImport] Found ${assetsToDelete.length} matching assets in gallery');
      }

      // Convert to FileToVault list
      final filesToVault = <FileToVault>[];
      for (final image in images) {
        final mimeType = lookupMimeType(image.path) ?? 'image/jpeg';
        filesToVault.add(FileToVault(
          sourcePath: image.path,
          originalName: image.name,
          type: VaultedFileType.image,
          mimeType: mimeType,
        ));
      }

      // Add to vault
      final imported = await _vaultService.addFiles(
        files: filesToVault,
        deleteOriginals: false, // We handle deletion via PhotoManager
        isDecoy: _decoyService.isDecoyModeActive,
        onProgress: onProgress,
      );

      debugPrint('[FileImport] Imported ${imported.length} files to vault');

      // Delete originals from gallery if requested and import was successful
      bool deletedFromGallery = false;
      if (deleteOriginals && imported.isNotEmpty && assetsToDelete.isNotEmpty) {
        debugPrint(
            '[FileImport] Attempting to delete ${assetsToDelete.length} assets from gallery');
        deletedFromGallery = await _deleteAssetsFromGallery(assetsToDelete);
        debugPrint('[FileImport] Gallery deletion result: $deletedFromGallery');
      }

      return ImportResult(
        success: true,
        importedFiles: imported,
        message: 'Imported ${imported.length} image(s)',
        deletedOriginals: deletedFromGallery,
      );
    } catch (e) {
      debugPrint('[FileImport] Error importing images from gallery: $e');
      return ImportResult(
        success: false,
        error: 'Failed to import images: $e',
        importedFiles: [],
      );
    }
  }

  /// Import media directly from AssetEntity objects (from custom media picker)
  /// This is the preferred method as it gives us direct access to the original files
  Future<ImportResult> importFromAssets({
    required List<AssetEntity> assets,
    bool deleteOriginals = true,
    Function(int current, int total, {int currentSize, int totalSize})?
        onProgress,
    Function(FileProgressInfo)? onFileProgress,
  }) async {
    if (assets.isEmpty) {
      return ImportResult(
        success: true,
        importedFiles: [],
        message: 'No assets selected',
      );
    }

    try {
      debugPrint('[FileImport] Importing ${assets.length} assets directly');
      final isDecoy = _decoyService.isDecoyModeActive;

      // Check if we have all files access for deletion
      final hasAllFilesAccess = await _permissionService.hasAllFilesAccess();
      if (deleteOriginals && !hasAllFilesAccess) {
        debugPrint(
            '[FileImport] Warning: All Files Access not granted. Original files may not be deleted from gallery.');
      }

      final filesToVault = <FileToVault>[];
      final validAssets = <AssetEntity>[];
      final fileSizesByPath = <String, int>{};

      for (final asset in assets) {
        try {
          // Get the actual file from the asset
          final file = await asset.file;
          if (file == null) {
            debugPrint(
                '[FileImport] Could not get file for asset: ${asset.title}');
            continue;
          }

          final filePath = file.path;
          final fileName =
              asset.title ?? 'unknown_${DateTime.now().millisecondsSinceEpoch}';

          final fileSize = await file.length();
          fileSizesByPath[filePath] = fileSize;

          // Determine file type
          VaultedFileType type;
          String mimeType;

          if (asset.type == AssetType.video) {
            type = VaultedFileType.video;
            mimeType = lookupMimeType(filePath) ?? 'video/mp4';
          } else if (asset.type == AssetType.image) {
            type = VaultedFileType.image;
            mimeType = lookupMimeType(filePath) ?? 'image/jpeg';
          } else {
            type = VaultedFileType.other;
            mimeType = lookupMimeType(filePath) ?? 'application/octet-stream';
          }

          filesToVault.add(FileToVault(
            sourcePath: filePath,
            originalName: fileName,
            type: type,
            mimeType: mimeType,
          ));
          validAssets.add(asset);

          debugPrint(
              '[FileImport] Prepared asset for import: $fileName (path: $filePath, size: $fileSize)');
        } catch (e) {
          debugPrint('[FileImport] Error processing asset ${asset.title}: $e');
        }
      }

      if (filesToVault.isEmpty) {
        return ImportResult(
          success: false,
          error: 'Could not access any of the selected files',
          importedFiles: [],
        );
      }

      debugPrint('[FileImport] Adding ${filesToVault.length} files to vault');

      // Check for potential duplicates before importing
      final existingFiles = await _vaultService.getAllFiles(isDecoy: isDecoy);
      final existingNames =
          existingFiles.map((f) => f.originalName.toLowerCase()).toSet();

      // Filter out files that might already be in vault
      final filesToImport = <FileToVault>[];
      final skippedDuplicates = <String>[];

      for (final file in filesToVault) {
        if (existingNames.contains(file.originalName.toLowerCase())) {
          debugPrint(
              '[FileImport] Potential duplicate detected: ${file.originalName}');
          skippedDuplicates.add(file.originalName);
        } else {
          filesToImport.add(file);
        }
      }

      if (skippedDuplicates.isNotEmpty) {
        debugPrint(
            '[FileImport] Skipping ${skippedDuplicates.length} potential duplicates');
      }

      if (filesToImport.isEmpty) {
        return ImportResult(
          success: false,
          error: 'All selected files already exist in vault',
          importedFiles: [],
        );
      }

      final totalSize = filesToImport.fold<int>(
        0,
        (sum, file) => sum + (fileSizesByPath[file.sourcePath] ?? 0),
      );

      debugPrint('[FileImport] Total size to import: $totalSize bytes');
      onProgress?.call(0, filesToImport.length,
          currentSize: 0, totalSize: totalSize);

      // Add to vault (copy files to vault directory)
      final imported = await _vaultService.addFiles(
        files: filesToImport,
        deleteOriginals: false, // We handle deletion via PhotoManager
        isDecoy: isDecoy,
        onProgress: (current, total) {
          // Map the vault service progress - estimate size progress proportionally
          final estimatedSize =
              totalSize > 0 ? (current / total * totalSize).round() : 0;
          onProgress?.call(current, total,
              currentSize: estimatedSize, totalSize: totalSize);
        },
        onFileProgress: onFileProgress,
      );

      debugPrint('[FileImport] Imported ${imported.length} files to vault');

      // Delete originals from gallery if requested and import was successful
      bool deletedFromGallery = false;
      if (deleteOriginals && imported.isNotEmpty && validAssets.isNotEmpty) {
        debugPrint(
            '[FileImport] Attempting to delete ${validAssets.length} assets from gallery');

        // Only delete the assets that were successfully imported
        final importedNames =
            imported.map((f) => f.originalName.toLowerCase()).toSet();
        final assetsToDelete = validAssets.where((asset) {
          final title = asset.title?.toLowerCase() ?? '';
          return importedNames.contains(title);
        }).toList();

        if (assetsToDelete.isNotEmpty) {
          deletedFromGallery = await _deleteAssetsFromGallery(assetsToDelete);

          if (deletedFromGallery) {
            debugPrint(
                '[FileImport] Successfully deleted ${assetsToDelete.length} assets from gallery');
          } else {
            debugPrint(
                '[FileImport] Failed to delete assets from gallery. Files are imported but originals remain.');
            debugPrint(
                '[FileImport] This creates duplicates - one in vault, one in gallery.');
            debugPrint(
                '[FileImport] User may need to manually delete from gallery or grant "All Files Access" permission.');
          }
        }
      }

      return ImportResult(
        success: true,
        importedFiles: imported,
        message:
            'Imported ${imported.length} file(s)${deletedFromGallery ? " and removed from gallery" : ""}',
        deletedOriginals: deletedFromGallery,
      );
    } catch (e, stackTrace) {
      debugPrint('[FileImport] Error importing from assets: $e');
      debugPrint('[FileImport] Stack trace: $stackTrace');
      return ImportResult(
        success: false,
        error: 'Failed to import files: $e',
        importedFiles: [],
      );
    }
  }

  /// Unhide files from vault - restores them back to the device gallery
  Future<UnhideResult> unhideFiles({
    required List<String> fileIds,
    bool removeFromVault = true,
    Function(int current, int total, {int currentSize, int totalSize})?
        onProgress,
  }) async {
    if (fileIds.isEmpty) {
      return UnhideResult(
        success: true,
        unhiddenCount: 0,
        message: 'No files selected',
      );
    }

    try {
      debugPrint('[FileImport] Unhiding ${fileIds.length} files');
      final isDecoy = _decoyService.isDecoyModeActive;

      // Check if we have all files access
      final hasAllFilesAccess = await _permissionService.hasAllFilesAccess();
      if (!hasAllFilesAccess) {
        debugPrint(
            '[FileImport] Warning: All Files Access not granted. Unhiding may fail.');
      }

      // First pass: get all vaulted files and calculate total size
      final vaultedFiles = <MapEntry<String, VaultedFile>>[];
      int totalSize = 0;
      int processedSize = 0;

      for (final fileId in fileIds) {
        try {
          final vaultedFile = await _vaultService.getFileById(
            fileId,
            isDecoy: isDecoy,
          );
          if (vaultedFile != null) {
            vaultedFiles.add(MapEntry(fileId, vaultedFile));
            totalSize += vaultedFile.fileSize;
          }
        } catch (e) {
          debugPrint('[FileImport] Could not get file info for $fileId: $e');
        }
      }

      debugPrint('[FileImport] Total size to unhide: $totalSize bytes');
      onProgress?.call(0, vaultedFiles.length,
          currentSize: 0, totalSize: totalSize);

      // Get the destination directory (DCIM/Restored)
      final dcimDir = Directory('/storage/emulated/0/DCIM/Restored');
      if (!await dcimDir.exists()) {
        await dcimDir.create(recursive: true);
      }

      int successCount = 0;
      int errorCount = 0;
      final List<String> restoredPaths = [];

      for (int i = 0; i < vaultedFiles.length; i++) {
        try {
          final entry = vaultedFiles[i];
          final fileId = entry.key;
          final vaultedFile = entry.value;
          final bytesBeforeFile = processedSize;

          // Determine destination path with original filename
          String destinationPath =
              '${dcimDir.path}/${vaultedFile.originalName}';

          // Handle duplicate filenames
          int counter = 1;
          while (await File(destinationPath).exists()) {
            final extension = vaultedFile.extension;
            final nameWithoutExt =
                vaultedFile.originalName.replaceAll('.$extension', '');
            destinationPath =
                '${dcimDir.path}/${nameWithoutExt}_$counter.$extension';
            counter++;
          }

          // Export the file from vault
          final exportedFile = await _vaultService.exportFile(
            fileId,
            destinationPath,
            isDecoy: isDecoy,
            onProgress: (fileProcessed, fileTotal) {
              final safeTotal =
                  fileTotal > 0 ? fileTotal : vaultedFile.fileSize;
              final clampedProcessed =
                  fileProcessed.clamp(0, safeTotal).toInt();
              onProgress?.call(i + 1, vaultedFiles.length,
                  currentSize: bytesBeforeFile + clampedProcessed,
                  totalSize: totalSize);
            },
          );

          if (exportedFile != null && await exportedFile.exists()) {
            processedSize = bytesBeforeFile + vaultedFile.fileSize;
            debugPrint('[FileImport] Exported file to: $destinationPath');

            // Notify MediaStore to scan the file (without creating duplicates)
            await _notifyMediaStore(destinationPath);

            restoredPaths.add(destinationPath);
            successCount++;

            // Remove from vault if requested
            if (removeFromVault) {
              await _vaultService.removeFile(fileId, isDecoy: isDecoy);
              debugPrint('[FileImport] Removed file from vault: $fileId');
            }
          } else {
            debugPrint(
                '[FileImport] Failed to export file: ${vaultedFile.originalName}');
            errorCount++;
          }

          onProgress?.call(i + 1, vaultedFiles.length,
              currentSize: processedSize, totalSize: totalSize);
        } catch (e) {
          debugPrint('[FileImport] Error unhiding file: $e');
          errorCount++;
        }
      }

      final message = successCount > 0
          ? 'Restored $successCount file(s) to gallery${errorCount > 0 ? ' ($errorCount failed)' : ''}'
          : 'Failed to restore files';

      return UnhideResult(
        success: successCount > 0,
        unhiddenCount: successCount,
        errorCount: errorCount,
        restoredPaths: restoredPaths,
        message: message,
      );
    } catch (e, stackTrace) {
      debugPrint('[FileImport] Error unhiding files: $e');
      debugPrint('[FileImport] Stack trace: $stackTrace');
      return UnhideResult(
        success: false,
        unhiddenCount: 0,
        error: 'Failed to unhide files: $e',
      );
    }
  }

  /// Notify MediaStore to scan a file so it appears in the gallery
  /// This method scans the existing file instead of creating a duplicate
  Future<void> _notifyMediaStore(String filePath) async {
    try {
      debugPrint('[FileImport] Notifying MediaStore about file: $filePath');

      // Use the media scanner service to scan the file without creating duplicates
      final success = await _mediaScannerService.scanFile(filePath);

      if (success) {
        debugPrint('[FileImport] Successfully scanned file: $filePath');
      } else {
        debugPrint(
            '[FileImport] Media scan may have failed, but file is still in DCIM');
      }
    } catch (e) {
      debugPrint('[FileImport] Error notifying MediaStore: $e');
      // Even if MediaStore notification fails, the file is still restored to DCIM
    }
  }

  /// Import videos from gallery with proper deletion support
  Future<ImportResult> importVideosFromGallery({
    bool deleteOriginals = true,
    Function(int current, int total)? onProgress,
  }) async {
    try {
      // Request permission
      final permission = await AutoKillService.runSafe(
          () => PhotoManager.requestPermissionExtend());
      if (!permission.hasAccess) {
        return ImportResult(
          success: false,
          error: 'Video library permission denied',
          importedFiles: [],
        );
      }

      // Check if we have all files access for deletion
      final hasAllFilesAccess = await _permissionService.hasAllFilesAccess();
      if (deleteOriginals && !hasAllFilesAccess) {
        debugPrint(
            '[FileImport] Warning: All Files Access not granted. Original videos may not be deleted from gallery.');
      }

      // Pick videos using file_picker for multiple selection
      final result = await AutoKillService.runSafe(() => FilePicker.pickFiles(
            type: FileType.video,
            allowMultiple: true,
          ));

      if (result == null || result.files.isEmpty) {
        return ImportResult(
          success: true,
          importedFiles: [],
          message: 'No videos selected',
        );
      }

      debugPrint(
          '[FileImport] Selected ${result.files.length} videos for import');

      // Track assets to delete BEFORE importing
      List<AssetEntity> assetsToDelete = [];
      if (deleteOriginals) {
        final fileNames = result.files.map((f) => f.name).toList();
        debugPrint(
            '[FileImport] Looking for video assets to delete with names: $fileNames');
        assetsToDelete =
            await _findMatchingAssets(fileNames, RequestType.video);
        debugPrint(
            '[FileImport] Found ${assetsToDelete.length} matching video assets in gallery');
      }

      // Convert to FileToVault list
      final filesToVault = <FileToVault>[];
      for (final file in result.files) {
        if (file.path == null) continue;

        final mimeType = lookupMimeType(file.path!) ?? 'video/mp4';
        filesToVault.add(FileToVault(
          sourcePath: file.path!,
          originalName: file.name,
          type: VaultedFileType.video,
          mimeType: mimeType,
        ));
      }

      // Add to vault
      final imported = await _vaultService.addFiles(
        files: filesToVault,
        deleteOriginals: false, // We handle deletion via PhotoManager
        isDecoy: _decoyService.isDecoyModeActive,
        onProgress: onProgress,
      );

      debugPrint('[FileImport] Imported ${imported.length} videos to vault');

      // Delete originals from gallery if requested and import was successful
      bool deletedFromGallery = false;
      if (deleteOriginals && imported.isNotEmpty && assetsToDelete.isNotEmpty) {
        debugPrint(
            '[FileImport] Attempting to delete ${assetsToDelete.length} video assets from gallery');
        deletedFromGallery = await _deleteAssetsFromGallery(assetsToDelete);
        debugPrint('[FileImport] Gallery deletion result: $deletedFromGallery');
      }

      return ImportResult(
        success: true,
        importedFiles: imported,
        message: 'Imported ${imported.length} video(s)',
        deletedOriginals: deletedFromGallery,
      );
    } catch (e) {
      debugPrint('[FileImport] Error importing videos from gallery: $e');
      return ImportResult(
        success: false,
        error: 'Failed to import videos: $e',
        importedFiles: [],
      );
    }
  }

  /// Capture photo from camera
  Future<ImportResult> capturePhotoFromCamera() async {
    try {
      // Request camera permission
      final hasPermission = await AutoKillService.runSafe(
          () => _permissionService.requestCameraPermission());
      if (!hasPermission) {
        return ImportResult(
          success: false,
          error: 'Camera permission denied',
          importedFiles: [],
        );
      }

      // Capture photo
      final image = await AutoKillService.runSafe(() => _imagePicker.pickImage(
            source: ImageSource.camera,
            imageQuality: 100,
          ));

      if (image == null) {
        return ImportResult(
          success: true,
          importedFiles: [],
          message: 'No photo captured',
        );
      }

      final mimeType = lookupMimeType(image.path) ?? 'image/jpeg';
      final imported = await _vaultService.addFile(
        sourcePath: image.path,
        originalName: image.name,
        type: VaultedFileType.image,
        mimeType: mimeType,
        deleteOriginal: true, // Camera captures are temporary
        isDecoy: _decoyService.isDecoyModeActive,
      );

      if (imported == null) {
        return ImportResult(
          success: false,
          error: 'Failed to save photo to vault',
          importedFiles: [],
        );
      }

      return ImportResult(
        success: true,
        importedFiles: [imported],
        message: 'Photo captured and saved',
        deletedOriginals: true,
      );
    } catch (e) {
      debugPrint('Error capturing photo: $e');
      return ImportResult(
        success: false,
        error: 'Failed to capture photo: $e',
        importedFiles: [],
      );
    }
  }

  /// Record video from camera
  Future<ImportResult> recordVideoFromCamera({
    Duration? maxDuration,
  }) async {
    try {
      // Request permissions
      final hasCamera = await AutoKillService.runSafe(
          () => _permissionService.requestCameraPermission());
      final hasMic = await AutoKillService.runSafe(
          () => _permissionService.requestMicrophonePermission());

      if (!hasCamera) {
        return ImportResult(
          success: false,
          error: 'Camera permission denied',
          importedFiles: [],
        );
      }

      if (!hasMic) {
        return ImportResult(
          success: false,
          error: 'Microphone permission denied',
          importedFiles: [],
        );
      }

      // Record video
      final video = await AutoKillService.runSafe(() => _imagePicker.pickVideo(
            source: ImageSource.camera,
            maxDuration: maxDuration ?? const Duration(minutes: 10),
          ));

      if (video == null) {
        return ImportResult(
          success: true,
          importedFiles: [],
          message: 'No video recorded',
        );
      }

      final mimeType = lookupMimeType(video.path) ?? 'video/mp4';
      final imported = await _vaultService.addFile(
        sourcePath: video.path,
        originalName: video.name,
        type: VaultedFileType.video,
        mimeType: mimeType,
        deleteOriginal: true, // Camera captures are temporary
        isDecoy: _decoyService.isDecoyModeActive,
      );

      if (imported == null) {
        return ImportResult(
          success: false,
          error: 'Failed to save video to vault',
          importedFiles: [],
        );
      }

      return ImportResult(
        success: true,
        importedFiles: [imported],
        message: 'Video recorded and saved',
        deletedOriginals: true,
      );
    } catch (e) {
      debugPrint('Error recording video: $e');
      return ImportResult(
        success: false,
        error: 'Failed to record video: $e',
        importedFiles: [],
      );
    }
  }

  /// Import a single file from a path (e.g. from custom camera)
  Future<ImportResult> importFile({
    required String filePath,
    bool deleteOriginal = true,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return ImportResult(
          success: false,
          error: 'File does not exist',
          importedFiles: [],
        );
      }

      final fileName = file.path.split('/').last;
      final mimeType = lookupMimeType(filePath) ?? 'application/octet-stream';

      // Auto-detect type
      VaultedFileType type;
      if (mimeType.startsWith('image/')) {
        type = VaultedFileType.image;
      } else if (mimeType.startsWith('video/')) {
        type = VaultedFileType.video;
      } else {
        // Fallback or check extension
        type = getFileTypeFromMime(mimeType);
      }

      final imported = await _vaultService.addFile(
        sourcePath: filePath,
        originalName: fileName,
        type: type,
        mimeType: mimeType,
        deleteOriginal: deleteOriginal,
        isDecoy: _decoyService.isDecoyModeActive,
      );

      if (imported == null) {
        return ImportResult(
          success: false,
          error: 'Failed to save file to vault',
          importedFiles: [],
        );
      }

      return ImportResult(
        success: true,
        importedFiles: [imported],
        message: 'File imported successfully',
        deletedOriginals: deleteOriginal,
      );
    } catch (e) {
      debugPrint('Error importing file: $e');
      return ImportResult(
        success: false,
        error: 'Failed to import file: $e',
        importedFiles: [],
      );
    }
  }

  /// Import documents from file manager
  Future<ImportResult> importDocuments({
    bool deleteOriginals = true,
    Function(int current, int total)? onProgress,
  }) async {
    try {
      // Pick documents
      final result = await AutoKillService.runSafe(() => FilePicker.pickFiles(
            type: FileType.custom,
            allowedExtensions: supportedDocumentExtensions,
            allowMultiple: true,
          ));

      if (result == null || result.files.isEmpty) {
        return ImportResult(
          success: true,
          importedFiles: [],
          message: 'No documents selected',
        );
      }

      // Store original paths for deletion
      final originalPaths = <String>[];

      // Convert to FileToVault list
      final filesToVault = <FileToVault>[];
      for (final file in result.files) {
        if (file.path == null) continue;

        final mimeType =
            lookupMimeType(file.path!) ?? 'application/octet-stream';
        filesToVault.add(FileToVault(
          sourcePath: file.path!,
          originalName: file.name,
          type: VaultedFileType.document,
          mimeType: mimeType,
        ));

        // Try to get the original path (not cache path)
        final originalPath = await _getOriginalPath(file.path!, file.name);
        if (originalPath != null) {
          originalPaths.add(originalPath);
        }
      }

      // Add to vault
      final imported = await _vaultService.addFiles(
        files: filesToVault,
        deleteOriginals: false,
        isDecoy: _decoyService.isDecoyModeActive,
        onProgress: onProgress,
      );

      // Delete original files if requested
      if (deleteOriginals && imported.isNotEmpty) {
        await _deleteFiles(originalPaths);
      }

      return ImportResult(
        success: true,
        importedFiles: imported,
        message: 'Imported ${imported.length} document(s)',
        deletedOriginals: deleteOriginals && originalPaths.isNotEmpty,
      );
    } catch (e) {
      debugPrint('Error importing documents: $e');
      return ImportResult(
        success: false,
        error: 'Failed to import documents: $e',
        importedFiles: [],
      );
    }
  }

  /// Import files from file paths selected in the custom picker.
  Future<ImportResult> importFromDocumentFiles({
    required List<String> filePaths,
    bool deleteOriginals = true,
    Function(int current, int total)? onProgress,
  }) async {
    if (filePaths.isEmpty) {
      return ImportResult(
        success: true,
        importedFiles: [],
        message: 'No documents selected',
      );
    }

    try {
      debugPrint(
          '[FileImport] Importing ${filePaths.length} documents directly');

      final filesToVault = <FileToVault>[];
      final pathsToDelete = <String>[];
      int processed = 0;

      for (final path in filePaths) {
        try {
          final file = File(path);
          if (!await file.exists()) {
            debugPrint('[FileImport] File does not exist: $path');
            continue;
          }

          final fileName = path.split('/').last;
          final mimeType = lookupMimeType(path) ?? 'application/octet-stream';
          final type = getFileTypeFromMime(mimeType);

          filesToVault.add(FileToVault(
            sourcePath: path,
            originalName: fileName,
            type: type,
            mimeType: mimeType,
          ));

          pathsToDelete.add(path);

          processed++;
          onProgress?.call(processed, filePaths.length);

          debugPrint('[FileImport] Prepared file for import: $fileName');
        } catch (e) {
          debugPrint('[FileImport] Error processing document $path: $e');
        }
      }

      if (filesToVault.isEmpty) {
        return ImportResult(
          success: false,
          error: 'Could not access any of the selected files',
          importedFiles: [],
        );
      }

      debugPrint('[FileImport] Adding ${filesToVault.length} files to vault');

      // Add to vault
      final imported = await _vaultService.addFiles(
        files: filesToVault,
        deleteOriginals: false,
        isDecoy: _decoyService.isDecoyModeActive,
        onProgress: onProgress,
      );

      debugPrint('[FileImport] Imported ${imported.length} files to vault');

      // Delete originals if requested
      bool deletedOriginals = false;
      if (deleteOriginals && imported.isNotEmpty && pathsToDelete.isNotEmpty) {
        debugPrint(
            '[FileImport] Deleting ${pathsToDelete.length} original documents');
        await _deleteFiles(pathsToDelete);
        deletedOriginals = true;
      }

      return ImportResult(
        success: true,
        importedFiles: imported,
        message:
            'Imported ${imported.length} file(s)${deletedOriginals ? " and removed originals" : ""}',
        deletedOriginals: deletedOriginals,
      );
    } catch (e, stackTrace) {
      debugPrint('[FileImport] Error importing documents from files: $e');
      debugPrint('[FileImport] Stack trace: $stackTrace');
      return ImportResult(
        success: false,
        error: 'Failed to import files: $e',
        importedFiles: [],
      );
    }
  }

  /// Import documents from file paths with Office document conversion
  /// Office documents (docx, odt, rtf) will be converted to PDF before storing
  /// Returns OfficeConversionInfo for files that need conversion confirmation
  Future<OfficeImportResult> importFromDocumentFilesWithConversion({
    required List<String> filePaths,
    required Future<bool> Function(List<OfficeFileInfo> officeFiles)
        onConversionConfirmation,
    bool deleteOriginals = true,
    Function(int current, int total)? onProgress,
    Function(String message)? onStatusUpdate,
  }) async {
    if (filePaths.isEmpty) {
      return OfficeImportResult(
        success: true,
        importedFiles: [],
        convertedFiles: [],
        skippedFiles: [],
        message: 'No documents selected',
      );
    }

    try {
      debugPrint(
          '[FileImport] Processing ${filePaths.length} documents for import');

      // Separate Office documents from regular files
      final officeFiles = <OfficeFileInfo>[];
      final regularFilePaths = <String>[];

      for (final path in filePaths) {
        final ext = path.split('.').last.toLowerCase();
        if (OfficeConverterService.isOfficeDocument(ext)) {
          final fileName = path.split('/').last;
          final canConvert = OfficeConverterService.canConvertOnDevice(ext);
          officeFiles.add(OfficeFileInfo(
            path: path,
            fileName: fileName,
            extension: ext,
            canConvertOnDevice: canConvert,
          ));
        } else {
          regularFilePaths.add(path);
        }
      }

      debugPrint(
          '[FileImport] Found ${officeFiles.length} Office documents, ${regularFilePaths.length} regular files');

      // Ask for confirmation if there are Office documents to convert
      bool conversionConfirmed = true;
      if (officeFiles.isNotEmpty) {
        conversionConfirmed = await onConversionConfirmation(officeFiles);
        if (!conversionConfirmed) {
          return OfficeImportResult(
            success: false,
            importedFiles: [],
            convertedFiles: [],
            skippedFiles: officeFiles.map((f) => f.fileName).toList(),
            message: 'Conversion cancelled by user',
          );
        }
      }

      final filesToVault = <FileToVault>[];
      final pathsToDelete = <String>[];
      final convertedFiles = <String>[];
      final skippedFiles = <String>[];
      int processed = 0;
      final totalFiles = regularFilePaths.length + officeFiles.length;

      // Process regular files first
      for (final path in regularFilePaths) {
        try {
          final file = File(path);
          if (!await file.exists()) {
            debugPrint('[FileImport] File does not exist: $path');
            continue;
          }

          final fileName = path.split('/').last;
          final mimeType = lookupMimeType(path) ?? 'application/octet-stream';

          filesToVault.add(FileToVault(
            sourcePath: path,
            originalName: fileName,
            type: VaultedFileType.document,
            mimeType: mimeType,
          ));

          pathsToDelete.add(path);
          processed++;
          onProgress?.call(processed, totalFiles);

          debugPrint(
              '[FileImport] Prepared regular document for import: $fileName');
        } catch (e) {
          debugPrint('[FileImport] Error processing document $path: $e');
        }
      }

      // Process Office documents with conversion
      final converter = OfficeConverterService();
      final tempDir = await getTemporaryDirectory();

      for (final officeFile in officeFiles) {
        try {
          if (!officeFile.canConvertOnDevice) {
            // Cannot convert on device, import original
            debugPrint(
                '[FileImport] Importing original (non-convertible): ${officeFile.fileName}');

            final mimeType =
                lookupMimeType(officeFile.path) ?? 'application/octet-stream';
            filesToVault.add(FileToVault(
              sourcePath: officeFile.path,
              originalName: officeFile.fileName,
              type: VaultedFileType.document,
              mimeType: mimeType,
            ));

            pathsToDelete.add(officeFile.path);
            processed++;
            onProgress?.call(processed, totalFiles);
            continue;
          }

          onStatusUpdate?.call('Converting ${officeFile.fileName}...');

          final file = File(officeFile.path);
          if (!await file.exists()) {
            debugPrint(
                '[FileImport] Office file does not exist: ${officeFile.path}');
            skippedFiles.add(officeFile.fileName);
            processed++;
            onProgress?.call(processed, totalFiles);
            continue;
          }

          // Read file data
          final fileData = await file.readAsBytes();

          // Convert to PDF
          final result = await converter.convertToPdf(
            Uint8List.fromList(fileData),
            officeFile.fileName,
            officeFile.extension,
          );

          if (result.success && result.pdfData != null) {
            // Save converted PDF to temp location
            final pdfFileName =
                '${officeFile.fileName.replaceAll(RegExp(r'\.[^.]+$'), '')}.pdf';
            final tempPdfPath = '${tempDir.path}/$pdfFileName';
            await File(tempPdfPath).writeAsBytes(result.pdfData!);

            filesToVault.add(FileToVault(
              sourcePath: tempPdfPath,
              originalName: pdfFileName,
              type: VaultedFileType.document,
              mimeType: 'application/pdf',
            ));

            pathsToDelete.add(officeFile.path);
            convertedFiles.add('${officeFile.fileName} → $pdfFileName');

            debugPrint(
                '[FileImport] Converted and prepared: ${officeFile.fileName} -> $pdfFileName');
          } else {
            debugPrint(
                '[FileImport] Failed to convert: ${officeFile.fileName} - ${result.error}');
            debugPrint('[FileImport] Fallback: Importing original file');

            // Fallback to original file
            final mimeType =
                lookupMimeType(officeFile.path) ?? 'application/octet-stream';
            filesToVault.add(FileToVault(
              sourcePath: officeFile.path,
              originalName: officeFile.fileName,
              type: VaultedFileType.document,
              mimeType: mimeType,
            ));

            pathsToDelete.add(officeFile.path);
            // Don't add to convertedFiles, maybe add to a 'fallback' list or just implicitly handled
          }

          processed++;
          onProgress?.call(processed, totalFiles);
        } catch (e) {
          debugPrint(
              '[FileImport] Error converting/importing ${officeFile.fileName}: $e');
          // Try one last time to import original if generic error occurred
          try {
            final mimeType =
                lookupMimeType(officeFile.path) ?? 'application/octet-stream';
            filesToVault.add(FileToVault(
              sourcePath: officeFile.path,
              originalName: officeFile.fileName,
              type: VaultedFileType.document,
              mimeType: mimeType,
            ));
            pathsToDelete.add(officeFile.path);
          } catch (e2) {
            skippedFiles.add(officeFile.fileName);
          }
          processed++;
          onProgress?.call(processed, totalFiles);
        }
      }

      if (filesToVault.isEmpty) {
        String errorMessage = 'Could not process any of the selected files';

        if (skippedFiles.isNotEmpty) {
          errorMessage += '. (${skippedFiles.length} files skipped/failed)';
        }

        return OfficeImportResult(
          success: false,
          error: errorMessage,
          importedFiles: [],
          convertedFiles: convertedFiles,
          skippedFiles: skippedFiles,
        );
      }

      onStatusUpdate?.call('Adding files to vault...');
      debugPrint(
          '[FileImport] Adding ${filesToVault.length} documents to vault');

      // Add to vault
      final imported = await _vaultService.addFiles(
        files: filesToVault,
        deleteOriginals: false,
        isDecoy: _decoyService.isDecoyModeActive,
        onProgress: onProgress,
      );

      debugPrint('[FileImport] Imported ${imported.length} documents to vault');

      // Delete originals if requested
      bool deletedOriginals = false;
      if (deleteOriginals && imported.isNotEmpty && pathsToDelete.isNotEmpty) {
        debugPrint(
            '[FileImport] Deleting ${pathsToDelete.length} original documents');
        await _deleteFiles(pathsToDelete);
        deletedOriginals = true;
      }

      final messageBuilder =
          StringBuffer('Imported ${imported.length} document(s)');
      if (convertedFiles.isNotEmpty) {
        messageBuilder.write(' (${convertedFiles.length} converted to PDF)');
      }
      if (skippedFiles.isNotEmpty) {
        messageBuilder.write(' (${skippedFiles.length} skipped)');
      }
      if (deletedOriginals) {
        messageBuilder.write(' and removed originals');
      }

      return OfficeImportResult(
        success: true,
        importedFiles: imported,
        convertedFiles: convertedFiles,
        skippedFiles: skippedFiles,
        message: messageBuilder.toString(),
        deletedOriginals: deletedOriginals,
      );
    } catch (e, stackTrace) {
      debugPrint('[FileImport] Error importing documents with conversion: $e');
      debugPrint('[FileImport] Stack trace: $stackTrace');
      return OfficeImportResult(
        success: false,
        error: 'Failed to import documents: $e',
        importedFiles: [],
        convertedFiles: [],
        skippedFiles: [],
      );
    }
  }

  /// Import any files from file manager
  Future<ImportResult> importAnyFiles({
    bool deleteOriginals = true,
    Function(int current, int total)? onProgress,
  }) async {
    try {
      // Pick any files
      final result = await AutoKillService.runSafe(() => FilePicker.pickFiles(
            type: FileType.any,
            allowMultiple: true,
          ));

      if (result == null || result.files.isEmpty) {
        return ImportResult(
          success: true,
          importedFiles: [],
          message: 'No files selected',
        );
      }

      // Store info for deletion
      final mediaFileNames = <String>[];
      final nonMediaPaths = <String>[];

      // Convert to FileToVault list with auto-detected types
      final filesToVault = <FileToVault>[];
      for (final file in result.files) {
        if (file.path == null) continue;

        final mimeType =
            lookupMimeType(file.path!) ?? 'application/octet-stream';
        final extension = file.extension ?? '';
        final type = getFileTypeFromExtension(extension);

        filesToVault.add(FileToVault(
          sourcePath: file.path!,
          originalName: file.name,
          type: type,
          mimeType: mimeType,
        ));

        // Categorize for deletion
        if (type == VaultedFileType.image || type == VaultedFileType.video) {
          mediaFileNames.add(file.name);
        } else {
          final originalPath = await _getOriginalPath(file.path!, file.name);
          if (originalPath != null) {
            nonMediaPaths.add(originalPath);
          } else if (await File(file.path!).exists()) {
            // Fall back to the picker path when we can access the file directly
            nonMediaPaths.add(file.path!);
          }
        }
      }

      // Add to vault
      final imported = await _vaultService.addFiles(
        files: filesToVault,
        deleteOriginals: false,
        isDecoy: _decoyService.isDecoyModeActive,
        onProgress: onProgress,
      );

      // Delete originals if requested
      if (deleteOriginals && imported.isNotEmpty) {
        // Delete media files via PhotoManager
        if (mediaFileNames.isNotEmpty) {
          final assets = await _findMatchingAssets(
            mediaFileNames,
            RequestType.common,
          );
          await _deleteAssetsFromGallery(assets);
        }
        // Delete non-media files directly
        if (nonMediaPaths.isNotEmpty) {
          await _deleteFiles(nonMediaPaths);
        }
      }

      return ImportResult(
        success: true,
        importedFiles: imported,
        message: 'Imported ${imported.length} file(s)',
        deletedOriginals: deleteOriginals,
      );
    } catch (e) {
      debugPrint('Error importing files: $e');
      return ImportResult(
        success: false,
        error: 'Failed to import files: $e',
        importedFiles: [],
      );
    }
  }

  /// Import media (images and videos) from gallery
  Future<ImportResult> importMediaFromGallery({
    bool deleteOriginals = true,
    Function(int current, int total)? onProgress,
  }) async {
    try {
      // Request permissions
      final permission = await AutoKillService.runSafe(
          () => PhotoManager.requestPermissionExtend());
      if (!permission.hasAccess) {
        return ImportResult(
          success: false,
          error: 'Media permission denied',
          importedFiles: [],
        );
      }

      // Check if we have all files access for deletion
      final hasAllFilesAccess = await _permissionService.hasAllFilesAccess();
      if (deleteOriginals && !hasAllFilesAccess) {
        debugPrint(
            '[FileImport] Warning: All Files Access not granted. Original media may not be deleted from gallery.');
      }

      // Pick media files (images and videos)
      final result = await AutoKillService.runSafe(() => FilePicker.pickFiles(
            type: FileType.media,
            allowMultiple: true,
          ));

      if (result == null || result.files.isEmpty) {
        return ImportResult(
          success: true,
          importedFiles: [],
          message: 'No media selected',
        );
      }

      debugPrint(
          '[FileImport] Selected ${result.files.length} media files for import');

      // Track assets to delete BEFORE importing
      List<AssetEntity> assetsToDelete = [];
      if (deleteOriginals) {
        final fileNames = result.files.map((f) => f.name).toList();
        debugPrint(
            '[FileImport] Looking for media assets to delete with names: $fileNames');
        assetsToDelete =
            await _findMatchingAssets(fileNames, RequestType.common);
        debugPrint(
            '[FileImport] Found ${assetsToDelete.length} matching media assets in gallery');
      }

      // Convert to FileToVault list
      final filesToVault = <FileToVault>[];
      for (final file in result.files) {
        if (file.path == null) continue;

        final mimeType =
            lookupMimeType(file.path!) ?? 'application/octet-stream';
        final type = getFileTypeFromMime(mimeType);

        filesToVault.add(FileToVault(
          sourcePath: file.path!,
          originalName: file.name,
          type: type,
          mimeType: mimeType,
        ));
      }

      // Add to vault
      final imported = await _vaultService.addFiles(
        files: filesToVault,
        deleteOriginals: false, // We handle deletion via PhotoManager
        isDecoy: _decoyService.isDecoyModeActive,
        onProgress: onProgress,
      );

      debugPrint(
          '[FileImport] Imported ${imported.length} media files to vault');

      // Delete originals from gallery if requested and import was successful
      bool deletedFromGallery = false;
      if (deleteOriginals && imported.isNotEmpty && assetsToDelete.isNotEmpty) {
        debugPrint(
            '[FileImport] Attempting to delete ${assetsToDelete.length} media assets from gallery');
        deletedFromGallery = await _deleteAssetsFromGallery(assetsToDelete);
        debugPrint('[FileImport] Gallery deletion result: $deletedFromGallery');
      }

      return ImportResult(
        success: true,
        importedFiles: imported,
        message: 'Imported ${imported.length} media file(s)',
        deletedOriginals: deletedFromGallery,
      );
    } catch (e) {
      debugPrint('[FileImport] Error importing media: $e');
      return ImportResult(
        success: false,
        error: 'Failed to import media: $e',
        importedFiles: [],
      );
    }
  }

  /// Find matching assets in the gallery by filename
  Future<List<AssetEntity>> _findMatchingAssets(
    List<String> fileNames,
    RequestType type,
  ) async {
    final matchingAssets = <AssetEntity>[];

    try {
      debugPrint(
          '[FileImport] Finding matching assets for ${fileNames.length} files');

      // Get all albums
      final albums = await PhotoManager.getAssetPathList(type: type);
      debugPrint('[FileImport] Found ${albums.length} albums to search');

      if (albums.isEmpty) {
        debugPrint('[FileImport] No albums found, cannot match assets');
        return matchingAssets;
      }

      // Convert filenames to a set for faster lookup (with and without extension)
      final fileNameSet = <String>{};
      for (final name in fileNames) {
        final lower = name.toLowerCase();
        fileNameSet.add(lower);
        final dotIndex = lower.lastIndexOf('.');
        if (dotIndex > 0) {
          fileNameSet.add(lower.substring(0, dotIndex));
        }
      }

      debugPrint('[FileImport] Looking for files matching: $fileNameSet');

      // Search through all albums - fetch all assets per album at once
      int totalAssetsSearched = 0;
      for (final album in albums) {
        final count = await album.assetCountAsync;
        if (count == 0) continue;

        final assets = await album.getAssetListRange(start: 0, end: count);
        totalAssetsSearched += assets.length;

        for (final asset in assets) {
          final title = asset.title?.toLowerCase() ?? '';
          final titleNoExt = title.contains('.')
              ? title.substring(0, title.lastIndexOf('.'))
              : title;
          if (fileNameSet.contains(title) || fileNameSet.contains(titleNoExt)) {
            debugPrint(
                '[FileImport] Found matching asset: ${asset.title} (id: ${asset.id})');
            matchingAssets.add(asset);
            fileNameSet.remove(title);
            fileNameSet.remove(titleNoExt);

            if (fileNameSet.isEmpty) {
              debugPrint(
                  '[FileImport] Found all ${matchingAssets.length} matching assets');
              return matchingAssets;
            }
          }
        }
      }

      debugPrint('[FileImport] Searched $totalAssetsSearched assets total');
      if (fileNameSet.isNotEmpty) {
        debugPrint('[FileImport] Could not find matches for: $fileNameSet');
      }
    } catch (e, stackTrace) {
      debugPrint('[FileImport] Error finding matching assets: $e');
      debugPrint('[FileImport] Stack trace: $stackTrace');
    }

    debugPrint(
        '[FileImport] Returning ${matchingAssets.length} matching assets');
    return matchingAssets;
  }

  /// Delete assets from gallery using PhotoManager
  Future<bool> _deleteAssetsFromGallery(List<AssetEntity> assets) async {
    if (assets.isEmpty) {
      debugPrint('[FileImport] No assets to delete');
      return true;
    }

    try {
      // Log asset details for debugging (avoid asset.file to prevent decode errors)
      for (final asset in assets) {
        debugPrint(
            '[FileImport] Deleting asset: ${asset.title} (id: ${asset.id})');
      }

      final ids = assets.map((a) => a.id).toList();
      debugPrint(
          '[FileImport] Calling PhotoManager.editor.deleteWithIds with ${ids.length} IDs');

      final result = await AutoKillService.runSafe(
          () => PhotoManager.editor.deleteWithIds(ids));

      debugPrint(
          '[FileImport] Delete result: ${result.length} assets deleted successfully');

      if (result.length < assets.length) {
        debugPrint(
            '[FileImport] Warning: Not all assets were deleted. Requested: ${assets.length}, Deleted: ${result.length}');
        debugPrint(
            '[FileImport] This may be due to missing "All Files Access" permission on Android 11+');
      }

      return result.isNotEmpty;
    } catch (e, stackTrace) {
      debugPrint('[FileImport] Error deleting assets from gallery: $e');
      debugPrint('[FileImport] Stack trace: $stackTrace');
      return false;
    }
  }

  /// Try to get the original path from a cached/picked file path
  Future<String?> _getOriginalPath(String cachedPath, String fileName) async {
    // Common locations to check
    final possibleDirs = [
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Documents',
      '/storage/emulated/0/DCIM',
      '/sdcard/Download',
      '/sdcard/Documents',
    ];

    for (final dir in possibleDirs) {
      final possiblePath = '$dir/$fileName';
      if (await File(possiblePath).exists()) {
        return possiblePath;
      }
    }

    return null;
  }

  /// Import a folder from the device filesystem
  Future<FolderImportResult> importFolder({
    required String folderPath,
    String? parentFolderId,
    bool recursive = true,
    bool deleteOriginals = false,
    Function(int current, int total)? onProgress,
    Function(String fileName, int fileNumber, int total)? onFileProgress,
  }) async {
    try {
      final hasAllFilesAccess = await _permissionService.hasAllFilesAccess();
      if (!hasAllFilesAccess) {
        return FolderImportResult(
          success: false,
          error: 'All Files Access permission required to import folders',
          foldersCreated: 0,
          filesImported: 0,
          importedFiles: [],
          importedFolders: [],
        );
      }

      final dir = Directory(folderPath);
      if (!await dir.exists()) {
        return FolderImportResult(
          success: false,
          error: 'Directory does not exist: $folderPath',
          foldersCreated: 0,
          filesImported: 0,
          importedFiles: [],
          importedFolders: [],
        );
      }

      final result = await _vaultService.importDeviceFolder(
        folderPath,
        parentFolderId: parentFolderId,
        recursive: recursive,
        deleteOriginals: deleteOriginals,
        encrypt: false,
        isDecoy: _decoyService.isDecoyModeActive,
        onProgress: onProgress,
        onFileProgress: onFileProgress,
      );

      return FolderImportResult(
        success: true,
        foldersCreated: result.foldersCreated,
        filesImported: result.filesImported,
        errors: result.errors,
        rootFolder: result.rootFolder,
        importedFiles: [],
        importedFolders: [],
        message: 'Imported ${result.filesImported} file(s) into ${result.foldersCreated} folder(s)',
      );
    } catch (e, stackTrace) {
      debugPrint('[FileImport] Error importing folder: $e');
      debugPrint('[FileImport] Stack trace: $stackTrace');
      return FolderImportResult(
        success: false,
        error: 'Failed to import folder: $e',
        foldersCreated: 0,
        filesImported: 0,
        importedFiles: [],
        importedFolders: [],
      );
    }
  }

  /// Delete files directly (for non-gallery files)
  Future<void> _deleteFiles(List<String> paths) async {
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          debugPrint('Deleted file: $path');
        }
      } catch (e) {
        debugPrint('Error deleting file: $path - $e');
      }
    }
  }
}

/// Result of an import operation
class ImportResult {
  final bool success;
  final String? error;
  final String? message;
  final List<VaultedFile> importedFiles;
  final bool deletedOriginals;

  const ImportResult({
    required this.success,
    this.error,
    this.message,
    required this.importedFiles,
    this.deletedOriginals = false,
  });

  int get importedCount => importedFiles.length;

  @override
  String toString() {
    if (success) {
      return 'ImportResult: Success - ${message ?? "Imported $importedCount file(s)"}${deletedOriginals ? " (originals deleted)" : ""}';
    }
    return 'ImportResult: Failed - $error';
  }
}

/// Result of an unhide operation
class UnhideResult {
  final bool success;
  final int unhiddenCount;
  final int errorCount;
  final String? error;
  final String? message;
  final List<String> restoredPaths;

  const UnhideResult({
    required this.success,
    required this.unhiddenCount,
    this.errorCount = 0,
    this.error,
    this.message,
    this.restoredPaths = const [],
  });

  @override
  String toString() {
    if (success) {
      return 'UnhideResult: Success - ${message ?? "Unhidden $unhiddenCount file(s)"}';
    }
    return 'UnhideResult: Failed - $error';
  }
}

/// Info about an Office file to be converted
class OfficeFileInfo {
  final String path;
  final String fileName;
  final String extension;
  final bool canConvertOnDevice;

  const OfficeFileInfo({
    required this.path,
    required this.fileName,
    required this.extension,
    required this.canConvertOnDevice,
  });

  String get typeName {
    switch (extension.toLowerCase()) {
      case 'docx':
        return 'Word Document';
      case 'doc':
        return 'Word Document (Legacy)';
      case 'odt':
        return 'LibreOffice Writer';
      case 'xlsx':
        return 'Excel Spreadsheet';
      case 'xls':
        return 'Excel Spreadsheet (Legacy)';
      case 'ods':
        return 'LibreOffice Calc';
      case 'pptx':
        return 'PowerPoint Presentation';
      case 'ppt':
        return 'PowerPoint Presentation (Legacy)';
      case 'odp':
        return 'LibreOffice Impress';
      case 'rtf':
        return 'Rich Text Format';
      default:
        return 'Office Document';
    }
  }
}

/// Result of an import operation with Office conversion
class OfficeImportResult {
  final bool success;
  final String? error;
  final String? message;
  final List<VaultedFile> importedFiles;
  final List<String> convertedFiles;
  final List<String> skippedFiles;
  final bool deletedOriginals;

  const OfficeImportResult({
    required this.success,
    this.error,
    this.message,
    required this.importedFiles,
    required this.convertedFiles,
    required this.skippedFiles,
    this.deletedOriginals = false,
  });

  int get importedCount => importedFiles.length;
  int get convertedCount => convertedFiles.length;
  int get skippedCount => skippedFiles.length;

  @override
  String toString() {
    if (success) {
      return 'OfficeImportResult: Success - ${message ?? "Imported $importedCount file(s), converted $convertedCount, skipped $skippedCount"}';
    }
    return 'OfficeImportResult: Failed - $error';
  }
}

/// Result of a folder import operation
class FolderImportResult {
  final bool success;
  final String? error;
  final String? message;
  final int foldersCreated;
  final int filesImported;
  final List<VaultedFile> importedFiles;
  final List<VaultFolder> importedFolders;
  final VaultFolder? rootFolder;
  final List<String> errors;

  const FolderImportResult({
    required this.success,
    this.error,
    this.message,
    required this.foldersCreated,
    required this.filesImported,
    required this.importedFiles,
    required this.importedFolders,
    this.rootFolder,
    this.errors = const [],
  });

  @override
  String toString() {
    if (success) {
      return 'FolderImportResult: Success - ${message ?? "Imported $filesImported file(s) into $foldersCreated folder(s)"}';
    }
    return 'FolderImportResult: Failed - $error';
  }
}
