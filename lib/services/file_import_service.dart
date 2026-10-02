import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/path_utils.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/encryption_algorithm.dart';
import '../models/vaulted_file.dart';
import '../models/vault_folder.dart';
import '../models/file_to_vault.dart';
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
      final fileSizesByPath = <String, int>{};
      for (final image in images) {
        final mimeType = lookupMimeType(image.path) ?? 'image/jpeg';
        fileSizesByPath[image.path] = await File(image.path).length();
        filesToVault.add(FileToVault(
          sourcePath: image.path,
          originalName: image.name,
          type: VaultedFileType.image,
          mimeType: mimeType,
        ));
      }

      final (filesToImport, skippedDuplicates) =
          await _filterDuplicates(filesToVault, fileSizesByPath);
      if (skippedDuplicates.isNotEmpty) {
        debugPrint(
            '[FileImport] Skipping ${skippedDuplicates.length} verified duplicates');
      }
      if (filesToImport.isEmpty) {
        return ImportResult(
          success: false,
          error: 'All selected files already exist in vault',
          importedFiles: [],
          skippedDuplicates: skippedDuplicates.length,
        );
      }

      // Add to vault
      final imported = await _vaultService.addFiles(
        files: filesToImport,
        deleteOriginals: false, // We handle deletion via PhotoManager
        isDecoy: _decoyService.isDecoyModeActive,
        onProgress: onProgress,
      );

      debugPrint('[FileImport] Imported ${imported.length} files to vault');

      // Delete originals from gallery if requested and import was successful
      int requestedOriginals = 0;
      int deletedOriginalsCount = 0;
      if (deleteOriginals && imported.isNotEmpty && assetsToDelete.isNotEmpty) {
        assetsToDelete = _gateAssetsToDelete(assetsToDelete, imported);
        requestedOriginals = assetsToDelete.length;
      }
      if (requestedOriginals > 0) {
        debugPrint(
            '[FileImport] Attempting to delete ${assetsToDelete.length} assets from gallery');
        deletedOriginalsCount = await _deleteAssetsFromGallery(assetsToDelete);
        debugPrint(
            '[FileImport] Gallery deletion result: $deletedOriginalsCount/$requestedOriginals');
      }
      final retainedOriginals =
          (requestedOriginals - deletedOriginalsCount).clamp(0, requestedOriginals);

      return ImportResult(
        success: true,
        importedFiles: imported,
        message:
            'Imported ${imported.length} image(s)${retainedOriginals > 0 ? " ($retainedOriginals original(s) still on device)" : ""}',
        deletedOriginals:
            requestedOriginals > 0 && retainedOriginals == 0,
        retainedOriginals: retainedOriginals,
        skippedDuplicates: skippedDuplicates.length,
        failedCount: (filesToImport.length - imported.length)
            .clamp(0, filesToImport.length),
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
    Map<String, ({bool encrypt, EncryptionAlgorithm algorithm})>? perFileEncryption,
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

          final perFileConfig = perFileEncryption?[filePath];
          filesToVault.add(FileToVault(
            sourcePath: filePath,
            originalName: fileName,
            type: type,
            mimeType: mimeType,
            encrypt: perFileConfig?.encrypt,
            encryptionAlgorithm: perFileConfig?.algorithm,
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

      // Delete gating needs the per-name attempt count across all picked
      // assets, including ones later verified as duplicates.
      final attemptedByName = <String, int>{};
      for (final file in filesToVault) {
        final lower = file.originalName.toLowerCase();
        attemptedByName[lower] = (attemptedByName[lower] ?? 0) + 1;
      }

      // Content-verified duplicate check: name+size shortlists candidates,
      // but only a matching stored payload hash counts as a duplicate.
      final (filesToImport, skippedDuplicates) =
          await _filterDuplicates(filesToVault, fileSizesByPath);

      if (skippedDuplicates.isNotEmpty) {
        debugPrint(
            '[FileImport] Skipping ${skippedDuplicates.length} verified duplicates');
      }

      if (filesToImport.isEmpty) {
        return ImportResult(
          success: false,
          error: 'All selected files already exist in vault',
          importedFiles: [],
          skippedDuplicates: skippedDuplicates.length,
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
      int requestedOriginals = 0;
      int deletedOriginalsCount = 0;
      if (deleteOriginals && imported.isNotEmpty && validAssets.isNotEmpty) {
        // Delete only when every picked file of a name is safely in the
        // vault (imported now or already present as a duplicate) — never
        // the gallery original of a failed/skipped-and-missing import.
        final importedByName = <String, int>{};
        for (final f in imported) {
          final lower = f.originalName.toLowerCase();
          importedByName[lower] = (importedByName[lower] ?? 0) + 1;
        }
        final skippedByName = <String, int>{};
        for (final name in skippedDuplicates) {
          final lower = name.toLowerCase();
          skippedByName[lower] = (skippedByName[lower] ?? 0) + 1;
        }
        final assetsToDelete = validAssets.where((asset) {
          final lower = asset.title?.toLowerCase() ?? '';
          if (!importedByName.containsKey(lower)) return false;
          final landed =
              (importedByName[lower] ?? 0) + (skippedByName[lower] ?? 0);
          return landed >= (attemptedByName[lower] ?? 0);
        }).toList();

        requestedOriginals = assetsToDelete.length;
        if (assetsToDelete.isNotEmpty) {
          debugPrint(
              '[FileImport] Attempting to delete ${assetsToDelete.length} assets from gallery');
          deletedOriginalsCount = await _deleteAssetsFromGallery(assetsToDelete);

          if (deletedOriginalsCount == requestedOriginals) {
            debugPrint(
                '[FileImport] Successfully deleted ${assetsToDelete.length} assets from gallery');
          } else {
            debugPrint(
                '[FileImport] Deleted $deletedOriginalsCount of $requestedOriginals gallery originals. Files are imported but some originals remain.');
            debugPrint(
                '[FileImport] User may need to manually delete from gallery or grant "All Files Access" permission.');
          }
        }
      }

      final retainedOriginals =
          (requestedOriginals - deletedOriginalsCount).clamp(0, requestedOriginals);
      final messageSuffix = retainedOriginals > 0
          ? ' ($retainedOriginals original(s) still on device)'
          : '';

      return ImportResult(
        success: true,
        importedFiles: imported,
        message: 'Imported ${imported.length} file(s)$messageSuffix',
        deletedOriginals: requestedOriginals > 0 && retainedOriginals == 0,
        retainedOriginals: retainedOriginals,
        skippedDuplicates: skippedDuplicates.length,
        failedCount: (filesToImport.length - imported.length)
            .clamp(0, filesToImport.length),
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

      final hasAllFilesAccess = await _permissionService.hasAllFilesAccess();
      if (!hasAllFilesAccess) {
        debugPrint(
            '[FileImport] Warning: All Files Access not granted. Unhiding may fail.');
      }

      final vaultedFiles = <MapEntry<String, VaultedFile>>[];
      int totalSize = 0;

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

      final dcimDir = Directory('/storage/emulated/0/DCIM/Restored');
      if (!await dcimDir.exists()) {
        await dcimDir.create(recursive: true);
      }

      final destinationPaths = <String, String>{};
      final usedPaths = <String>{};
      for (final entry in vaultedFiles) {
        final vaultedFile = entry.value;
        String destPath = '${dcimDir.path}/${vaultedFile.originalName}';
        int counter = 1;
        while (usedPaths.contains(destPath) ||
            await File(destPath).exists()) {
          final extension = vaultedFile.extension;
          final nameWithoutExt =
              vaultedFile.originalName.replaceAll('.$extension', '');
          destPath = '${dcimDir.path}/${nameWithoutExt}_$counter.$extension';
          counter++;
        }
        usedPaths.add(destPath);
        destinationPaths[entry.key] = destPath;
      }

      final fileProgress = <int, int>{};
      final exportResults = <int, File?>{};

      await Future.wait(
        vaultedFiles.asMap().entries.map((e) async {
          final index = e.key;
          final entry = e.value;
          final fileId = entry.key;
          final vaultedFile = entry.value;
          final destPath = destinationPaths[fileId]!;

          try {
            final exported = await _vaultService.exportFile(
              fileId,
              destPath,
              isDecoy: isDecoy,
              onProgress: (processed, total) {
                final safeTotal =
                    total > 0 ? total : vaultedFile.fileSize;
                fileProgress[index] =
                    processed.clamp(0, safeTotal).toInt();
                final totalProcessed =
                    fileProgress.values.fold(0, (a, b) => a + b);
                onProgress?.call(
                  index + 1,
                  vaultedFiles.length,
                  currentSize: totalProcessed,
                  totalSize: totalSize,
                );
              },
            );
            exportResults[index] = exported;
          } catch (e) {
            debugPrint('[FileImport] Error exporting ${vaultedFile.originalName}: $e');
            exportResults[index] = null;
          }
        }),
      );

      int successCount = 0;
      int errorCount = 0;
      final restoredPaths = <String>[];
      final successFileIds = <String>[];

      for (int i = 0; i < vaultedFiles.length; i++) {
        final entry = vaultedFiles[i];
        final fileId = entry.key;
        final vaultedFile = entry.value;
        final destPath = destinationPaths[fileId]!;
        final exported = exportResults[i];

        if (exported != null && await exported.exists()) {
          debugPrint('[FileImport] Exported file to: $destPath');
          await _notifyMediaStore(destPath);
          restoredPaths.add(destPath);
          successFileIds.add(fileId);
          successCount++;
        } else {
          debugPrint(
              '[FileImport] Failed to export: ${vaultedFile.originalName}');
          errorCount++;
        }

        onProgress?.call(i + 1, vaultedFiles.length,
            currentSize: totalSize, totalSize: totalSize);
      }

      if (removeFromVault) {
        for (final fileId in successFileIds) {
          try {
            await _vaultService.removeFile(fileId, isDecoy: isDecoy);
          } catch (e) {
            debugPrint('[FileImport] Failed to remove $fileId from vault: $e');
          }
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
      final fileSizesByPath = <String, int>{};
      for (final file in result.files) {
        if (file.path == null) continue;

        final mimeType = lookupMimeType(file.path!) ?? 'video/mp4';
        fileSizesByPath[file.path!] = file.size;
        filesToVault.add(FileToVault(
          sourcePath: file.path!,
          originalName: file.name,
          type: VaultedFileType.video,
          mimeType: mimeType,
        ));
      }

      final (filesToImport, skippedDuplicates) =
          await _filterDuplicates(filesToVault, fileSizesByPath);
      if (skippedDuplicates.isNotEmpty) {
        debugPrint(
            '[FileImport] Skipping ${skippedDuplicates.length} verified duplicates');
      }
      if (filesToImport.isEmpty) {
        return ImportResult(
          success: false,
          error: 'All selected files already exist in vault',
          importedFiles: [],
          skippedDuplicates: skippedDuplicates.length,
        );
      }

      // Add to vault
      final imported = await _vaultService.addFiles(
        files: filesToImport,
        deleteOriginals: false, // We handle deletion via PhotoManager
        isDecoy: _decoyService.isDecoyModeActive,
        onProgress: onProgress,
      );

      debugPrint('[FileImport] Imported ${imported.length} videos to vault');

      // Delete originals from gallery if requested and import was successful
      int requestedOriginals = 0;
      int deletedOriginalsCount = 0;
      if (deleteOriginals && imported.isNotEmpty && assetsToDelete.isNotEmpty) {
        assetsToDelete = _gateAssetsToDelete(assetsToDelete, imported);
        requestedOriginals = assetsToDelete.length;
      }
      if (requestedOriginals > 0) {
        debugPrint(
            '[FileImport] Attempting to delete ${assetsToDelete.length} video assets from gallery');
        deletedOriginalsCount = await _deleteAssetsFromGallery(assetsToDelete);
        debugPrint(
            '[FileImport] Gallery deletion result: $deletedOriginalsCount/$requestedOriginals');
      }
      final retainedOriginals =
          (requestedOriginals - deletedOriginalsCount).clamp(0, requestedOriginals);

      return ImportResult(
        success: true,
        importedFiles: imported,
        message:
            'Imported ${imported.length} video(s)${retainedOriginals > 0 ? " ($retainedOriginals original(s) still on device)" : ""}',
        deletedOriginals: requestedOriginals > 0 && retainedOriginals == 0,
        retainedOriginals: retainedOriginals,
        skippedDuplicates: skippedDuplicates.length,
        failedCount: (filesToImport.length - imported.length)
            .clamp(0, filesToImport.length),
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

      final originalRetained = await File(image.path).exists();
      return ImportResult(
        success: true,
        importedFiles: [imported],
        message: originalRetained
            ? 'Photo captured and saved (original still on device)'
            : 'Photo captured and saved',
        deletedOriginals: !originalRetained,
        retainedOriginals: originalRetained ? 1 : 0,
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

      final originalRetained = await File(video.path).exists();
      return ImportResult(
        success: true,
        importedFiles: [imported],
        message: originalRetained
            ? 'Video recorded and saved (original still on device)'
            : 'Video recorded and saved',
        deletedOriginals: !originalRetained,
        retainedOriginals: originalRetained ? 1 : 0,
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

      // `FileService` deletes the source when requested, but never reports
      // the outcome; confirm on disk before claiming the original is gone.
      final originalRetained =
          deleteOriginal && await File(filePath).exists();
      return ImportResult(
        success: true,
        importedFiles: [imported],
        message: originalRetained
            ? 'File imported (original still on device)'
            : 'File imported successfully',
        deletedOriginals: deleteOriginal && !originalRetained,
        retainedOriginals: originalRetained ? 1 : 0,
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

      // Delete original files if requested, only for documents that landed
      // in the vault.
      final importedNames = {
        for (final f in imported) f.originalName.toLowerCase()
      };
      final pathsToDelete = originalPaths
          .where((p) => importedNames.contains(p.split('/').last.toLowerCase()))
          .toList();
      int requestedOriginals = 0;
      int deletedOriginalsCount = 0;
      if (deleteOriginals && pathsToDelete.isNotEmpty) {
        requestedOriginals = pathsToDelete.length;
        deletedOriginalsCount = await _deleteFiles(pathsToDelete);
      }
      final retainedOriginals =
          (requestedOriginals - deletedOriginalsCount).clamp(0, requestedOriginals);

      return ImportResult(
        success: true,
        importedFiles: imported,
        message:
            'Imported ${imported.length} document(s)${retainedOriginals > 0 ? " ($retainedOriginals original(s) still on device)" : ""}',
        deletedOriginals: requestedOriginals > 0 && retainedOriginals == 0,
        retainedOriginals: retainedOriginals,
        failedCount: (filesToVault.length - imported.length)
            .clamp(0, filesToVault.length),
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
    Map<String, ({bool encrypt, EncryptionAlgorithm algorithm})>? perFileEncryption,
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

          final perFileConfig = perFileEncryption?[path];
          filesToVault.add(FileToVault(
            sourcePath: path,
            originalName: fileName,
            type: type,
            mimeType: mimeType,
            encrypt: perFileConfig?.encrypt,
            encryptionAlgorithm: perFileConfig?.algorithm,
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

      // Delete originals if requested, only for files that landed in the vault.
      final importedNames = {
        for (final f in imported) f.originalName.toLowerCase()
      };
      final deletablePaths = pathsToDelete
          .where((p) => importedNames.contains(p.split('/').last.toLowerCase()))
          .toList();
      int requestedOriginals = 0;
      int deletedOriginalsCount = 0;
      if (deleteOriginals && deletablePaths.isNotEmpty) {
        debugPrint(
            '[FileImport] Deleting ${deletablePaths.length} original documents');
        requestedOriginals = deletablePaths.length;
        deletedOriginalsCount = await _deleteFiles(deletablePaths);
      }
      final retainedOriginals =
          (requestedOriginals - deletedOriginalsCount).clamp(0, requestedOriginals);

      return ImportResult(
        success: true,
        importedFiles: imported,
        message:
            'Imported ${imported.length} file(s)${retainedOriginals > 0 ? " ($retainedOriginals original(s) still on device)" : ""}',
        deletedOriginals: requestedOriginals > 0 && retainedOriginals == 0,
        retainedOriginals: retainedOriginals,
        failedCount: (filesToVault.length - imported.length)
            .clamp(0, filesToVault.length),
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
    Function(FileProgressInfo)? onFileProgress,
    Function(String message)? onStatusUpdate,
    Map<String, ({bool encrypt, EncryptionAlgorithm algorithm})>? perFileEncryption,
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
      final pathsToDelete = <({String path, String name})>[];
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

          final perFileConfig = perFileEncryption?[path];
          filesToVault.add(FileToVault(
            sourcePath: path,
            originalName: fileName,
            type: VaultedFileType.document,
            mimeType: mimeType,
            encrypt: perFileConfig?.encrypt,
            encryptionAlgorithm: perFileConfig?.algorithm,
          ));

          pathsToDelete.add((path: path, name: fileName));
          processed++;
          onProgress?.call(processed, totalFiles);
          onFileProgress?.call(FileProgressInfo(
            current: processed,
            total: totalFiles,
            fileName: fileName,
            fileSize: 0,
            status: 'Preparing...',
          ));

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
            final perFileConfig = perFileEncryption?[officeFile.path];
            filesToVault.add(FileToVault(
              sourcePath: officeFile.path,
              originalName: officeFile.fileName,
              type: VaultedFileType.document,
              mimeType: mimeType,
              encrypt: perFileConfig?.encrypt,
              encryptionAlgorithm: perFileConfig?.algorithm,
            ));

            pathsToDelete.add((path: officeFile.path, name: officeFile.fileName));
            processed++;
            onProgress?.call(processed, totalFiles);
            onFileProgress?.call(FileProgressInfo(
              current: processed,
              total: totalFiles,
              fileName: officeFile.fileName,
              fileSize: 0,
              status: 'Preparing...',
            ));
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
            onFileProgress?.call(FileProgressInfo(
              current: processed,
              total: totalFiles,
              fileName: officeFile.fileName,
              fileSize: 0,
              status: 'File not found, skipping...',
            ));
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

            final perFileConfig = perFileEncryption?[officeFile.path];
            filesToVault.add(FileToVault(
              sourcePath: tempPdfPath,
              originalName: pdfFileName,
              type: VaultedFileType.document,
              mimeType: 'application/pdf',
              encrypt: perFileConfig?.encrypt,
              encryptionAlgorithm: perFileConfig?.algorithm,
            ));

            pathsToDelete.add((path: officeFile.path, name: pdfFileName));
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
            final perFileConfig = perFileEncryption?[officeFile.path];
            filesToVault.add(FileToVault(
              sourcePath: officeFile.path,
              originalName: officeFile.fileName,
              type: VaultedFileType.document,
              mimeType: mimeType,
              encrypt: perFileConfig?.encrypt,
              encryptionAlgorithm: perFileConfig?.algorithm,
            ));

            pathsToDelete.add((path: officeFile.path, name: officeFile.fileName));
            // Don't add to convertedFiles, maybe add to a 'fallback' list or just implicitly handled
          }

          processed++;
          onProgress?.call(processed, totalFiles);
          onFileProgress?.call(FileProgressInfo(
            current: processed,
            total: totalFiles,
            fileName: officeFile.fileName,
            fileSize: 0,
            status: result.success ? 'Converted' : 'Conversion failed, using original',
          ));
        } catch (e) {
          debugPrint(
              '[FileImport] Error converting/importing ${officeFile.fileName}: $e');
          // Try one last time to import original if generic error occurred
          try {
            final mimeType =
                lookupMimeType(officeFile.path) ?? 'application/octet-stream';
            final perFileConfig = perFileEncryption?[officeFile.path];
            filesToVault.add(FileToVault(
              sourcePath: officeFile.path,
              originalName: officeFile.fileName,
              type: VaultedFileType.document,
              mimeType: mimeType,
              encrypt: perFileConfig?.encrypt,
              encryptionAlgorithm: perFileConfig?.algorithm,
            ));
            pathsToDelete.add((path: officeFile.path, name: officeFile.fileName));
          } catch (e2) {
            skippedFiles.add(officeFile.fileName);
          }
          processed++;
          onProgress?.call(processed, totalFiles);
          onFileProgress?.call(FileProgressInfo(
            current: processed,
            total: totalFiles,
            fileName: officeFile.fileName,
            fileSize: 0,
            status: 'Importing original...',
          ));
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
          failedCount: totalFiles,
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
        onFileProgress: onFileProgress,
      );

      debugPrint('[FileImport] Imported ${imported.length} documents to vault');

      // Delete originals if requested, only for documents that landed in the
      // vault (converted files are matched by their PDF name).
      final importedNames = {
        for (final f in imported) f.originalName.toLowerCase()
      };
      final deletablePaths = pathsToDelete
          .where((p) => importedNames.contains(p.name.toLowerCase()))
          .toList();
      int requestedOriginals = 0;
      int deletedOriginalsCount = 0;
      if (deleteOriginals && deletablePaths.isNotEmpty) {
        debugPrint(
            '[FileImport] Deleting ${deletablePaths.length} original documents');
        requestedOriginals = deletablePaths.length;
        deletedOriginalsCount =
            await _deleteFiles(deletablePaths.map((p) => p.path).toList());
      }
      final retainedOriginals =
          (requestedOriginals - deletedOriginalsCount).clamp(0, requestedOriginals);
      final deletedOriginals =
          requestedOriginals > 0 && retainedOriginals == 0;

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
      } else if (retainedOriginals > 0) {
        messageBuilder.write(
            ' ($retainedOriginals original(s) still on device)');
      }

      return OfficeImportResult(
        success: true,
        importedFiles: imported,
        convertedFiles: convertedFiles,
        skippedFiles: skippedFiles,
        message: messageBuilder.toString(),
        deletedOriginals: deletedOriginals,
        retainedOriginals: retainedOriginals,
        failedCount:
            (totalFiles - imported.length).clamp(0, totalFiles),
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
        failedCount: filePaths.length,
      );
    }
  }

  /// Import any files from file manager
  Future<ImportResult> importAnyFiles({
    bool deleteOriginals = true,
    Function(int current, int total)? onProgress,
    Map<String, ({bool encrypt, EncryptionAlgorithm algorithm})>? perFileEncryption,
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
      final fileSizesByPath = <String, int>{};
      for (final file in result.files) {
        if (file.path == null) continue;

        final mimeType =
            lookupMimeType(file.path!) ?? 'application/octet-stream';
        final extension = file.extension ?? '';
        final type = getFileTypeFromExtension(extension);

        final perFileConfig = perFileEncryption?[file.path!];
        filesToVault.add(FileToVault(
          sourcePath: file.path!,
          originalName: file.name,
          type: type,
          mimeType: mimeType,
          encrypt: perFileConfig?.encrypt,
          encryptionAlgorithm: perFileConfig?.algorithm,
        ));
        fileSizesByPath[file.path!] = file.size;

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

      final (filesToImport, skippedDuplicates) =
          await _filterDuplicates(filesToVault, fileSizesByPath);
      if (skippedDuplicates.isNotEmpty) {
        debugPrint(
            '[FileImport] Skipping ${skippedDuplicates.length} verified duplicates');
      }
      if (filesToImport.isEmpty) {
        return ImportResult(
          success: false,
          error: 'All selected files already exist in vault',
          importedFiles: [],
          skippedDuplicates: skippedDuplicates.length,
        );
      }

      // Add to vault
      final imported = await _vaultService.addFiles(
        files: filesToImport,
        deleteOriginals: false,
        isDecoy: _decoyService.isDecoyModeActive,
        onProgress: onProgress,
      );

      // Delete originals only for files that actually landed in the vault.
      int requestedOriginals = 0;
      int deletedOriginalsCount = 0;
      if (deleteOriginals && imported.isNotEmpty) {
        final importedNames = {
          for (final f in imported) f.originalName.toLowerCase()
        };
        // Delete media files via PhotoManager
        if (mediaFileNames.isNotEmpty) {
          final mediaToCheck = mediaFileNames
              .where((n) => importedNames.contains(n.toLowerCase()))
              .toList();
          final assets = mediaToCheck.isEmpty
              ? <AssetEntity>[]
              : await _findMatchingAssets(
                  mediaToCheck,
                  RequestType.common,
                );
          final gated = _gateAssetsToDelete(assets, imported);
          if (gated.isNotEmpty) {
            requestedOriginals += gated.length;
            deletedOriginalsCount += await _deleteAssetsFromGallery(gated);
          }
        }
        // Delete non-media files directly
        if (nonMediaPaths.isNotEmpty) {
          final pathsToDelete = nonMediaPaths
              .where((p) =>
                  importedNames.contains(p.split('/').last.toLowerCase()))
              .toList();
          if (pathsToDelete.isNotEmpty) {
            requestedOriginals += pathsToDelete.length;
            deletedOriginalsCount += await _deleteFiles(pathsToDelete);
          }
        }
      }

      final retainedOriginals =
          (requestedOriginals - deletedOriginalsCount).clamp(0, requestedOriginals);

      return ImportResult(
        success: true,
        importedFiles: imported,
        message:
            'Imported ${imported.length} file(s)${retainedOriginals > 0 ? " ($retainedOriginals original(s) still on device)" : ""}',
        deletedOriginals: requestedOriginals > 0 && retainedOriginals == 0,
        retainedOriginals: retainedOriginals,
        skippedDuplicates: skippedDuplicates.length,
        failedCount: (filesToImport.length - imported.length)
            .clamp(0, filesToImport.length),
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
      final fileSizesByPath = <String, int>{};
      for (final file in result.files) {
        if (file.path == null) continue;

        final mimeType =
            lookupMimeType(file.path!) ?? 'application/octet-stream';
        final type = getFileTypeFromMime(mimeType);

        fileSizesByPath[file.path!] = file.size;
        filesToVault.add(FileToVault(
          sourcePath: file.path!,
          originalName: file.name,
          type: type,
          mimeType: mimeType,
        ));
      }

      final (filesToImport, skippedDuplicates) =
          await _filterDuplicates(filesToVault, fileSizesByPath);
      if (skippedDuplicates.isNotEmpty) {
        debugPrint(
            '[FileImport] Skipping ${skippedDuplicates.length} verified duplicates');
      }
      if (filesToImport.isEmpty) {
        return ImportResult(
          success: false,
          error: 'All selected files already exist in vault',
          importedFiles: [],
          skippedDuplicates: skippedDuplicates.length,
        );
      }

      // Add to vault
      final imported = await _vaultService.addFiles(
        files: filesToImport,
        deleteOriginals: false, // We handle deletion via PhotoManager
        isDecoy: _decoyService.isDecoyModeActive,
        onProgress: onProgress,
      );

      debugPrint(
          '[FileImport] Imported ${imported.length} media files to vault');

      // Delete originals from gallery if requested and import was successful
      int requestedOriginals = 0;
      int deletedOriginalsCount = 0;
      if (deleteOriginals && imported.isNotEmpty && assetsToDelete.isNotEmpty) {
        assetsToDelete = _gateAssetsToDelete(assetsToDelete, imported);
        requestedOriginals = assetsToDelete.length;
      }
      if (requestedOriginals > 0) {
        debugPrint(
            '[FileImport] Attempting to delete ${assetsToDelete.length} media assets from gallery');
        deletedOriginalsCount = await _deleteAssetsFromGallery(assetsToDelete);
        debugPrint(
            '[FileImport] Gallery deletion result: $deletedOriginalsCount/$requestedOriginals');
      }
      final retainedOriginals =
          (requestedOriginals - deletedOriginalsCount).clamp(0, requestedOriginals);

      return ImportResult(
        success: true,
        importedFiles: imported,
        message:
            'Imported ${imported.length} media file(s)${retainedOriginals > 0 ? " ($retainedOriginals original(s) still on device)" : ""}',
        deletedOriginals: requestedOriginals > 0 && retainedOriginals == 0,
        retainedOriginals: retainedOriginals,
        skippedDuplicates: skippedDuplicates.length,
        failedCount: (filesToImport.length - imported.length)
            .clamp(0, filesToImport.length),
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

  /// Duplicate filter shared by the picker-based import paths. Filename+size
  /// only shortlists candidates; a source is skipped only when a candidate's
  /// stored payload hash matches the source bytes.
  Future<(List<FileToVault>, List<String>)> _filterDuplicates(
    List<FileToVault> files,
    Map<String, int> sizesByPath,
  ) async {
    final existing = await _vaultService.getAllFiles(
        isDecoy: _decoyService.isDecoyModeActive);
    final existingByName = <String, List<VaultedFile>>{};
    for (final f in existing) {
      existingByName
          .putIfAbsent(f.originalName.toLowerCase(), () => <VaultedFile>[])
          .add(f);
    }
    final sourceHashes = <String, String?>{};
    final vaultHashes = <String, String?>{};
    final toImport = <FileToVault>[];
    final skipped = <String>[];
    for (final file in files) {
      final size = sizesByPath[file.sourcePath] ?? 0;
      final candidates = (existingByName[file.originalName.toLowerCase()] ??
              const <VaultedFile>[])
          .where((c) => c.fileSize == size);
      var duplicate = false;
      for (final candidate in candidates) {
        final sourceHash = await _sourceHash(file.sourcePath, sourceHashes);
        if (sourceHash == null) continue;
        final vaultHash = await _contentHash(candidate, vaultHashes);
        if (vaultHash != null && vaultHash == sourceHash) {
          duplicate = true;
          break;
        }
      }
      if (duplicate) {
        debugPrint(
            '[FileImport] Verified duplicate detected: ${file.originalName}');
        skipped.add(file.originalName);
      } else {
        toImport.add(file);
      }
    }
    return (toImport, skipped);
  }

  Future<String?> _sourceHash(String path, Map<String, String?> cache) async {
    if (cache.containsKey(path)) return cache[path];
    String? hash;
    try {
      hash = await _vaultService.hashFile(path);
    } catch (e) {
      debugPrint('[FileImport] Could not hash source file $path: $e');
    }
    cache[path] = hash;
    return hash;
  }

  Future<String?> _contentHash(
    VaultedFile file,
    Map<String, String?> cache,
  ) async {
    if (cache.containsKey(file.id)) return cache[file.id];
    String? hash;
    try {
      hash = file.contentHash ??
          await _vaultService.contentHashFor(
            file,
            isDecoy: _decoyService.isDecoyModeActive,
          );
    } catch (e) {
      debugPrint('[FileImport] Could not verify vault payload ${file.id}: $e');
    }
    cache[file.id] = hash;
    return hash;
  }

  /// Keep only matched assets whose name actually landed in the vault, so
  /// failed imports keep their gallery originals.
  List<AssetEntity> _gateAssetsToDelete(
    List<AssetEntity> assets,
    List<VaultedFile> imported,
  ) {
    final importedNames = {
      for (final f in imported) f.originalName.toLowerCase()
    };
    return assets
        .where((a) => importedNames.contains(a.title?.toLowerCase() ?? ''))
        .toList();
  }

  /// Find matching assets in the gallery by filename. Names that match MORE
  /// THAN ONE asset are ambiguous and skipped — deleting a name-matched
  /// asset we can't uniquely identify risks removing the wrong file (the
  /// picked original then survives as a "duplicate"). Full scan on purpose:
  /// ambiguity can only be detected after every album was searched.
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

      // Requested name (lowercased) -> candidate assets by id. Ids dedupe
      // the same asset appearing in several albums.
      final candidates = <String, Map<String, AssetEntity>>{
        for (final name in fileNames)
          name.toLowerCase(): <String, AssetEntity>{},
      };

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
          for (final entry in candidates.entries) {
            if (entry.value.containsKey(asset.id)) continue;
            final dotIndex = entry.key.lastIndexOf('.');
            final bare =
                dotIndex > 0 ? entry.key.substring(0, dotIndex) : entry.key;
            if (entry.key == title ||
                entry.key == titleNoExt ||
                bare == title ||
                bare == titleNoExt) {
              entry.value[asset.id] = asset;
            }
          }
        }
      }

      debugPrint('[FileImport] Searched $totalAssetsSearched assets total');
      for (final entry in candidates.entries) {
        if (entry.value.length == 1) {
          debugPrint('[FileImport] Unique match for "${entry.key}"');
          matchingAssets.add(entry.value.values.first);
        } else if (entry.value.length > 1) {
          debugPrint(
              '[FileImport] Ambiguous name "${entry.key}" matches ${entry.value.length} assets, skipping its deletion');
        }
      }
    } catch (e, stackTrace) {
      debugPrint('[FileImport] Error finding matching assets: $e');
      debugPrint('[FileImport] Stack trace: $stackTrace');
    }

    debugPrint(
        '[FileImport] Returning ${matchingAssets.length} matching assets');
    return matchingAssets;
  }

  /// Delete assets from gallery using PhotoManager.
  ///
  /// Returns the number of assets confirmed deleted. Callers must not report
  /// the originals as removed unless every requested asset was deleted.
  Future<int> _deleteAssetsFromGallery(List<AssetEntity> assets) async {
    if (assets.isEmpty) {
      debugPrint('[FileImport] No assets to delete');
      return 0;
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

      return result.length;
    } catch (e, stackTrace) {
      debugPrint('[FileImport] Error deleting assets from gallery: $e');
      debugPrint('[FileImport] Stack trace: $stackTrace');
      return 0;
    }
  }

  /// Try to get the original path from a cached/picked file path
  Future<String?> _getOriginalPath(String cachedPath, String fileName) async {
    // Common locations to check
    final possibleDirs = PathUtils.androidSourceRoots;

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

  /// Delete files directly (for non-gallery files).
  ///
  /// Returns the number of paths confirmed gone (already-missing paths count).
  Future<int> _deleteFiles(List<String> paths) async {
    int deleted = 0;
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          debugPrint('Deleted file: $path');
        }
        deleted++;
      } catch (e) {
        debugPrint('Error deleting file: $path - $e');
      }
    }
    return deleted;
  }
}

/// Result of an import operation
class ImportResult {
  final bool success;
  final String? error;
  final String? message;
  final List<VaultedFile> importedFiles;

  /// True only when every original that was requested for deletion is
  /// confirmed gone. Partial or failed deletion leaves this false.
  final bool deletedOriginals;

  /// Number of originals that were requested for deletion but remain on the
  /// device, so the user can remove them manually.
  final int retainedOriginals;

  /// Files skipped because the vault already holds a content-identical copy.
  final int skippedDuplicates;

  /// Files that were attempted but could not be added to the vault.
  final int failedCount;

  const ImportResult({
    required this.success,
    this.error,
    this.message,
    required this.importedFiles,
    this.deletedOriginals = false,
    this.retainedOriginals = 0,
    this.skippedDuplicates = 0,
    this.failedCount = 0,
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

  /// True only when every original requested for deletion is confirmed gone.
  final bool deletedOriginals;

  /// Number of originals requested for deletion that remain on the device.
  final int retainedOriginals;

  /// Files that were attempted but could not be added to the vault.
  final int failedCount;

  const OfficeImportResult({
    required this.success,
    this.error,
    this.message,
    required this.importedFiles,
    required this.convertedFiles,
    required this.skippedFiles,
    this.deletedOriginals = false,
    this.retainedOriginals = 0,
    this.failedCount = 0,
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
