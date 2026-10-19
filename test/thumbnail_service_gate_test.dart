import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/vaulted_file.dart';
import 'package:locker/services/encryption_service.dart';
import 'package:locker/services/file_operation_gate.dart';
import 'package:locker/services/file_service.dart';
import 'package:locker/services/thumbnail_service.dart';
import 'package:locker/services/vault_store.dart';

class _FakeStore implements VaultStore {
  _FakeStore(this.root, this.files);

  final Directory root;
  final List<VaultedFile> files;

  @override
  Future<List<VaultedFile>> loadFileIndex({
    bool isDecoy = false,
    bool forceReload = false,
  }) async =>
      files;

  @override
  Future<Directory> ensureVaultDirectory() async => root;

  @override
  Future<void> deleteFileIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeEncryption implements EncryptionService {
  final List<String> destinations = [];

  @override
  int get cacheGeneration => 0;

  @override
  bool isCurrentSession(int generation) => true;

  @override
  int detectFileFormat(String filePath) => 1;

  @override
  Future<FileDecryptionResult> decryptFileInIsolate(
    String encryptedPath,
    String destinationPath,
    String ivBase64, {
    bool isDecoy = false,
    Uint8List? derivedKey,
    Function(int bytesProcessed, int totalBytes)? onProgress,
    dynamic cancelToken,
  }) async {
    destinations.add(destinationPath);
    final tmp = File('$destinationPath.tmp');
    await tmp.writeAsString('decrypted:$encryptedPath');
    await tmp.rename(destinationPath);
    return FileDecryptionResult(
      success: true,
      decryptedPath: destinationPath,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SlowThumbnailService extends ThumbnailService {
  // ignore: use_super_parameters
  _SlowThumbnailService(VaultStore store, EncryptionService encryption)
      : super(store, encryption);

  final generationStarted = Completer<void>();
  final releaseGeneration = Completer<void>();

  @override
  Future<Uint8List?> generateThumbBytes(
      File plaintext, VaultedFileType type) async {
    if (!generationStarted.isCompleted) generationStarted.complete();
    await releaseGeneration.future;
    return Uint8List.fromList(const [1, 2, 3]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('thumbnail regeneration does not block decryption of the same file',
      () async {
    final root = await Directory.systemTemp.createTemp('latch_thumb_gate');
    addTearDown(() => root.delete(recursive: true));
    await Directory('${root.path}/temp').create();

    final encrypted = File('${root.path}/documents/clip.mp4');
    await encrypted.parent.create(recursive: true);
    await encrypted.writeAsBytes(const [1, 2, 3]);

    final file = VaultedFile(
      id: 'clip',
      originalName: 'clip.mp4',
      vaultPath: encrypted.path,
      type: VaultedFileType.video,
      mimeType: 'video/mp4',
      fileSize: 3,
      dateAdded: DateTime.utc(2024),
      isEncrypted: true,
      encryptionIv: 'iv',
    );

    final store = _FakeStore(root, [file]);
    final encryption = _FakeEncryption();
    final thumbnails = _SlowThumbnailService(store, encryption);
    final fileService = FileService(store, encryption, thumbnails);
    thumbnails.fileService = fileService;

    final thumbnailFuture = thumbnails.getThumbnailBytes(file);
    await thumbnails.generationStarted.future;

    final thumbnailPlaintext = File(encryption.destinations.single);
    expect(await thumbnailPlaintext.exists(), isTrue);

    File? viewerFile;
    try {
      // Video frame extraction is slow. A viewer swiping to this video must
      // still decrypt it instead of getting null from getVaultedFile.
      expect(
        FileOperationGate.instance.canRead(file.id),
        isTrue,
        reason: 'the viewer should be able to read the source during regen',
      );
      expect(
        FileOperationGate.instance.allowsMutation,
        isFalse,
        reason: 'thumbnail writes must still block concurrent mutations',
      );

      viewerFile = await fileService.getVaultedFile(file.id);
      expect(viewerFile, isNotNull, reason: 'the viewer decryption was blocked');
      if (viewerFile != null) {
        expect(await viewerFile.exists(), isTrue);
        expect(viewerFile.path, isNot(thumbnailPlaintext.path));
        expect(encryption.destinations.toSet(), hasLength(2));
      }
    } finally {
      thumbnails.releaseGeneration.complete();
      await thumbnailFuture;
    }

    expect(await thumbnailPlaintext.exists(), isFalse,
        reason: 'thumbnail cleanup deletes only its own plaintext');
    if (viewerFile != null) {
      expect(await viewerFile.exists(), isTrue,
          reason: 'thumbnail cleanup must not delete the viewer plaintext');
    }
    expect(FileOperationGate.instance.isBusy, isFalse);
  });
}
