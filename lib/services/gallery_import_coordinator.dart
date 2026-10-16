import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../models/encryption_algorithm.dart';
import '../models/operation_progress.dart';
import '../models/vaulted_file.dart';
import '../providers/operation_provider.dart';
import '../providers/vault_providers.dart';
import '../screens/audio_recorder_screen.dart';
import '../screens/camera_screen.dart';
import '../screens/document_picker_screen.dart';
import '../screens/folder_import_picker_screen.dart';
import '../screens/media_picker_screen.dart';
import '../utils/toast_utils.dart';
import '../widgets/gallery/gallery_import_sheet.dart';
import '../widgets/office_conversion_confirm_dialog.dart';
import '../widgets/per_file_encryption_sheet.dart';
import 'file_import_service.dart';
import 'office_converter_service.dart';
import 'operation_controller.dart';

typedef _EncryptionChoices
    = Map<String, ({bool encrypt, EncryptionAlgorithm algorithm})>;

/// Coordinates picker routes and confirmations before dispatching session-owned
/// jobs. Jobs never retain a route context or read a disposed widget ref.
class GalleryImportCoordinator {
  GalleryImportCoordinator(this.context, this.ref);

  final BuildContext context;
  final WidgetRef ref;
  bool get _mounted => context.mounted;

  void show() {
    if (!ref.read(operationControllerProvider).checkAvailable()) return;
    showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => GalleryImportSheet(actions: {
              GalleryImportAction.images: () => _media(RequestType.image),
              GalleryImportAction.videos: () => _media(RequestType.video),
              GalleryImportAction.media: () => _media(RequestType.common),
              GalleryImportAction.photo: () => _capture(CameraMode.photo),
              GalleryImportAction.video: () => _capture(CameraMode.video),
              GalleryImportAction.audio: _recordAudio,
              GalleryImportAction.songs: () => _documents(songs: true),
              GalleryImportAction.documents: () => _documents(songs: false),
              GalleryImportAction.files: _files,
              GalleryImportAction.folder: _folder,
            }));
  }

  void _start(int count, Future<OperationOutcome> Function(OperationJob) task) {
    if (!_mounted) return;
    ref.read(operationControllerProvider).start(
        type: OperationType.hide,
        initialProgress: OperationProgressState(totalFiles: count),
        task: task);
  }

  void _importPaths(List<String> paths, {_EncryptionChoices? choices}) =>
      _start(
          paths.length,
          (job) async => importOutcome(await FileImportService.instance
              .importFromDocumentFiles(
                  filePaths: paths,
                  deleteOriginals: true,
                  perFileEncryption: choices,
                  onProgress: job.batchProgress,
                  onFileProgress: job.fileProgress)));

  Future<_EncryptionChoices?> _chooseEncryption(
      List<({String name, String path, int size})> files) async {
    final settings = await ref.read(vaultSettingsProvider.future);
    if (!context.mounted) return null;
    final choices = await PerFileEncryptionSheet.show(context,
        files: [
          for (final file in files)
            PerFileEncryptionSettings(
                fileName: file.name,
                filePath: file.path,
                fileSize: file.size,
                encrypt: settings.encryptionEnabled,
                algorithm: settings.encryptionAlgorithm)
        ],
        encryptionEnabled: settings.encryptionEnabled,
        defaultAlgorithm: settings.encryptionAlgorithm);
    if (!_mounted || choices == null) return null;
    return {
      for (final choice in choices)
        choice.filePath: (encrypt: choice.encrypt, algorithm: choice.algorithm)
    };
  }

  Future<void> _media(RequestType type) async {
    Navigator.pop(context);
    final label = type == RequestType.image
        ? 'Images'
        : type == RequestType.video
            ? 'Videos'
            : 'Media';
    final assets = await Navigator.push<List<AssetEntity>>(
        context,
        MaterialPageRoute(
            builder: (_) => MediaPickerScreen(
                requestType: type, title: 'Select $label to Hide')));
    if (!_mounted) return;
    if (assets == null || assets.isEmpty) {
      ToastUtils.showInfo('No ${label.toLowerCase()} selected');
      return;
    }
    _EncryptionChoices? choices;
    if (type != RequestType.common) {
      final files = <({String name, String path, int size})>[];
      for (final asset in assets) {
        final file = await asset.file;
        files.add((
          name: asset.title ?? 'Unknown',
          path: file?.path ?? '',
          size: file == null ? 0 : await file.length()
        ));
      }
      if (!_mounted) return;
      choices = await _chooseEncryption(files);
      if (choices == null || !_mounted) return;
    }
    final encryption = choices;
    _start(
        assets.length,
        (job) async => importOutcome(await FileImportService.instance
            .importFromAssets(
                assets: assets,
                deleteOriginals: true,
                perFileEncryption: encryption,
                onProgress: job.batchProgress,
                onFileProgress: job.fileProgress)));
  }

  Future<void> _capture(CameraMode mode) async {
    Navigator.pop(context);
    final path = await Navigator.push<String>(context,
        MaterialPageRoute(builder: (_) => CameraScreen(initialMode: mode)));
    if (path != null && _mounted) _importPaths([path]);
  }

  Future<void> _recordAudio() async {
    Navigator.pop(context);
    final path = await Navigator.push<String>(context,
        MaterialPageRoute(builder: (_) => const AudioRecorderScreen()));
    if (path != null && _mounted) _importPaths([path]);
  }

  Future<void> _documents({required bool songs}) async {
    Navigator.pop(context);
    final selected = await Navigator.push<List<DocumentFile>>(
        context,
        MaterialPageRoute(
            builder: (_) => songs
                ? const DocumentPickerScreen(
                    title: 'Select Songs to Hide',
                    allowedExtensions: supportedAudioExtensions,
                    itemLabel: 'song',
                    itemLabelPlural: 'songs',
                    stateIcon: Icons.music_note_outlined)
                : const DocumentPickerScreen(
                    title: 'Select Documents to Hide')));
    if (!_mounted) return;
    if (selected == null || selected.isEmpty) {
      ToastUtils.showInfo('No ${songs ? 'songs' : 'documents'} selected');
      return;
    }
    final files = <({String name, String path, int size})>[];
    for (final doc in selected) {
      final file = File(doc.path);
      files.add((
        name: doc.name,
        path: doc.path,
        size: await file.exists() ? await file.length() : 0
      ));
    }
    if (!_mounted) return;
    final choices = await _chooseEncryption(files);
    if (choices == null || !_mounted) return;
    final paths = selected.map((doc) => doc.path).toList();
    if (songs) {
      _importPaths(paths, choices: choices);
      return;
    }
    final officeFiles = <OfficeFileInfo>[];
    for (final doc in selected) {
      final extension = doc.path.split('.').last.toLowerCase();
      if (OfficeConverterService.isOfficeDocument(extension)) {
        officeFiles.add(OfficeFileInfo(
            path: doc.path,
            fileName: doc.name,
            extension: extension,
            canConvertOnDevice:
                OfficeConverterService.canConvertOnDevice(extension)));
      }
    }
    if (officeFiles.isNotEmpty) {
      if (!context.mounted) return;
      final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => OfficeConversionConfirmDialog(
              officeFiles: officeFiles,
              onConfirm: () => Navigator.pop(context, true),
              onCancel: () => Navigator.pop(context, false)));
      if (confirmed != true || !_mounted) return;
    }
    _start(
        paths.length,
        (job) async => officeImportOutcome(await FileImportService.instance
            .importFromDocumentFilesWithConversion(
                filePaths: paths,
                deleteOriginals: true,
                perFileEncryption: choices,
                onConversionConfirmation: (_) async => true,
                onFileProgress: job.fileProgress,
                onStatusUpdate: (message) {
                  job.value = job.value.copyWith(statusMessage: message);
                })));
  }

  Future<void> _files() async {
    Navigator.pop(context);
    final result =
        await FilePicker.pickFiles(type: FileType.any, allowMultiple: true);
    if (!_mounted) return;
    if (result == null || result.files.isEmpty) {
      ToastUtils.showInfo('No files selected');
      return;
    }
    final files = [
      for (final file in result.files)
        if (file.path != null)
          (name: file.name, path: file.path!, size: file.size)
    ];
    if (files.isEmpty) {
      ToastUtils.showInfo('No valid files selected');
      return;
    }
    final choices = await _chooseEncryption(files);
    if (choices == null || !_mounted) return;
    _importPaths(files.map((file) => file.path).toList(), choices: choices);
  }

  Future<void> _folder() async {
    Navigator.pop(context);
    final path = await Navigator.push<String>(context,
        MaterialPageRoute(builder: (_) => const FolderImportPickerScreen()));
    if (path == null || !_mounted) return;
    _start(0, (job) async {
      final result = await FileImportService.instance.importFolder(
          folderPath: path,
          recursive: true,
          deleteOriginals: false,
          onProgress: (current, total) {
            job.value = job.value.copyWith(
                statusMessage:
                    'Importing folder: $current of $total files in this folder');
          },
          onFileProgress: (name, current, total) {
            job.value = job.value.copyWith(
                currentFileName: name, statusMessage: 'Importing $name...');
          });
      return OperationOutcome(
          kind: !result.success
              ? OperationOutcomeKind.error
              : result.errors.isNotEmpty
                  ? OperationOutcomeKind.warning
                  : result.filesImported == 0
                      ? OperationOutcomeKind.info
                      : OperationOutcomeKind.success,
          message: [
            result.message ?? result.error ?? 'No files found in folder',
            if (result.errors.isNotEmpty) result.errors.join(' · ')
          ].join(' · '),
          processedFiles: result.filesImported,
          result: result);
    });
  }
}
