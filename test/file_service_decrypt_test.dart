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

/// Mirrors the isolate worker: write `destination.tmp`, then rename it into
/// place. Sharing a destination makes the second rename fail, which is the
/// race this test guards against.
class _FakeEncryption implements EncryptionService {
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
    final tmp = File('$destinationPath.tmp');
    await tmp.writeAsString('decrypted:$encryptedPath');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tmp.rename(destinationPath);
    return FileDecryptionResult(
      success: true,
      decryptedPath: destinationPath,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('concurrent decryptions of one file use independent destinations',
      () async {
    final root = await Directory.systemTemp.createTemp('latch_decrypt_test');
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
    final crypto = _FakeEncryption();
    final store = _FakeStore(root, [file]);
    final service = FileService(store, crypto, ThumbnailService(store, crypto));

    final results = await Future.wait([
      service.getVaultedFile(file.id),
      service.getVaultedFile(file.id),
    ]);

    expect(results[0], isNotNull);
    expect(results[1], isNotNull);
    expect(results[0]!.path, isNot(results[1]!.path));
    expect(await results[0]!.exists(), isTrue);
    expect(await results[1]!.exists(), isTrue);
  });

  test('waits for a transient file reservation instead of returning null',
      () async {
    final root = await Directory.systemTemp.createTemp('latch_decrypt_gate');
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
    final crypto = _FakeEncryption();
    final store = _FakeStore(root, [file]);
    final service = FileService(store, crypto, ThumbnailService(store, crypto));

    final gate = FileOperationGate.instance;
    addTearDown(gate.invalidateAndDrain);
    final lease = gate.acquire({file.id})!;
    final holder = gate.run(
      lease,
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );

    // A metadata commit used to reserve the id only briefly. The reader must
    // wait for that lease instead of reporting a decrypt failure.
    final result = await service.getVaultedFile(file.id);
    await holder;

    expect(result, isNotNull);
    expect(await result!.exists(), isTrue);
  });
}
