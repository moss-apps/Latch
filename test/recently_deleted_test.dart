import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/deleted_vault_item.dart';
import 'package:locker/models/encryption_algorithm.dart';
import 'package:locker/models/note.dart';
import 'package:locker/models/password_entry.dart';
import 'package:locker/models/sync_conflict.dart';
import 'package:locker/models/sync_profile.dart';
import 'package:locker/models/vault_settings.dart';
import 'package:locker/services/backup_service.dart';
import 'package:locker/services/encryption_service.dart';
import 'package:locker/services/file_operation_gate.dart';
import 'package:locker/services/note_service.dart';
import 'package:locker/services/password_service.dart';
import 'package:locker/services/recently_deleted_service.dart';
import 'package:locker/services/sync_service.dart';
import 'package:locker/services/sync_state_store.dart';
import 'package:locker/services/vault_service.dart';
import 'package:locker/services/vault_store.dart';

import 'support/recovery_fixture.dart';

class _DeletionCrypto implements EncryptionService {
  final erased = <String>[];
  String? failPath;
  @override
  Future<bool> secureDelete(String path) async {
    erased.add(path);
    if (path == failPath) return false;
    await File(path).delete();
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecoveryFixture fixture;
  late _DeletionCrypto crypto;
  late DateTime now;
  late RecentlyDeletedService recovery;

  setUp(() async {
    fixture = RecoveryFixture();
    await fixture.initialize();
    crypto = _DeletionCrypto();
    now = DateTime.now().toUtc();
    recovery =
        RecentlyDeletedService(fixture.vault.store, crypto, clock: () => now);
  });
  tearDown(() async {
    recovery.dispose();
    await fixture.dispose();
  });

  test('retention defaults, supported options and corrupt values are safe', () {
    expect(const VaultSettings().recentlyDeletedRetentionDays, 30);
    for (final days in VaultSettings.retentionOptions) {
      final settings = VaultSettings(recentlyDeletedRetentionDays: days);
      expect(
          VaultSettings.fromJson(settings.toJson())
              .recentlyDeletedRetentionDays,
          days);
      expect(settings.copyWith().recentlyDeletedRetentionDays, days);
    }
    expect(
        VaultSettings.fromJson({'recentlyDeletedRetentionDays': -1})
            .recentlyDeletedRetentionDays,
        30);
  });

  test('encrypted payload and thumbnail survive restart and restore exactly',
      () async {
    final key = Uint8List.fromList(List.generate(32, (i) => i));
    final plain = Uint8List.fromList(List.generate(2048, (i) => i % 255));
    final original = await fixture.file('encrypted');
    final thumbnailPath = '${original.vaultPath}.thumb';
    final encrypted = await EncryptionService.instance
        .encryptBytesStreamedGcm(plain, original.vaultPath, derivedKey: key);
    final thumbnail = await EncryptionService.instance.encryptBytesStreamedGcm(
        Uint8List.fromList([7, 8]), thumbnailPath,
        derivedKey: key);
    final file = original.copyWith(
        isEncrypted: true,
        encryptionIv: encrypted.iv,
        encryptionAlgorithm: EncryptionAlgorithm.aes256Gcm,
        keyDerivationSalt: 'original-salt',
        kdfIterations: 120000,
        thumbnailPath: thumbnailPath,
        thumbnailIv: thumbnail.iv,
        tags: ['kept'],
        isFavorite: true,
        notes: 'original metadata');
    final ciphertext = await File(file.vaultPath).readAsBytes();
    final thumbCiphertext = await File(thumbnailPath).readAsBytes();
    await fixture.seed([file]);
    expect(await recovery.delete(file), isTrue);
    expect(await fixture.vault.getAllFiles(), isEmpty);
    final receipt = (await fixture.vault.store.loadDeletedItems()).single;
    expect(receipt.expiresAt, now.add(const Duration(days: 30)));
    expect(await recovery.storageUsed(),
        ciphertext.length + thumbCiphertext.length);
    expect((await SyncStateStore.deletions()).containsKey(file.id), isTrue);
    final reopened = await fixture.reopen();
    now = now.add(const Duration(days: 1));
    final resumed =
        RecentlyDeletedService(reopened.store, crypto, clock: () => now);
    expect(await resumed.restore(file.id), isTrue);
    resumed.dispose();
    final restored = (await reopened.getAllFiles()).single;
    expect(restored.id, file.id);
    expect(restored.vaultPath, isNot(file.vaultPath));
    expect(restored.dateAdded, file.dateAdded);
    expect(restored.encryptionIv, file.encryptionIv);
    expect(restored.keyDerivationSalt, file.keyDerivationSalt);
    expect(restored.kdfIterations, file.kdfIterations);
    expect(restored.thumbnailIv, file.thumbnailIv);
    expect(restored.tags, file.tags);
    expect(restored.isFavorite, isTrue);
    expect(restored.notes, file.notes);
    expect(restored.modifiedAt, now);
    expect(await File(restored.vaultPath).readAsBytes(), ciphertext);
    expect(await File(restored.thumbnailPath!).readAsBytes(), thumbCiphertext);
    final decrypted = await EncryptionService.instance
        .decryptStreamedFileToMemoryGcm(
            restored.vaultPath, restored.encryptionIv!,
            derivedKey: key);
    expect(decrypted.success, isTrue);
    expect(decrypted.data, plain);
    expect(await reopened.store.loadDeletedItems(), isEmpty);
    expect((await SyncStateStore.deletions()).containsKey(file.id), isFalse);
  });

  test('expiry boundary blocks restore and removes payload and thumbnail',
      () async {
    await fixture.vault
        .updateSettings(const VaultSettings(recentlyDeletedRetentionDays: 7));
    final file = await fixture.file('expires');
    final thumb = '${file.vaultPath}.thumb';
    await File(thumb).writeAsBytes([4, 5]);
    final withThumb = file.copyWith(thumbnailPath: thumb);
    await fixture.seed([withThumb]);
    expect(await recovery.delete(withThumb), isTrue);
    final receipt = (await fixture.vault.store.loadDeletedItems()).single;
    await fixture.vault
        .updateSettings(const VaultSettings(recentlyDeletedRetentionDays: 90));
    expect((await fixture.vault.store.loadDeletedItems()).single.expiresAt,
        receipt.expiresAt);
    now = receipt.expiresAt;
    expect(await recovery.restore(file.id), isFalse);
    expect(await recovery.maintain(), isTrue);
    expect(crypto.erased,
        containsAll([receipt.payloadPath, receipt.thumbnailPath]));
    expect(await recovery.storageUsed(), 0);
    expect(await fixture.vault.store.loadDeletedItems(), isEmpty);
    expect((await SyncStateStore.deletions()).containsKey(file.id), isTrue);
  });

  test('immediate deletion bypasses recovery; secure-delete off unlinks',
      () async {
    await fixture.vault.updateSettings(const VaultSettings(
        recentlyDeletedRetentionDays: 0, secureDelete: false));
    final file = await fixture.file('immediate');
    await fixture.seed([file]);
    expect(await recovery.delete(file), isTrue);
    expect(await recovery.restore(file.id), isFalse);
    expect(await fixture.vault.store.loadDeletedItems(), isEmpty);
    expect(await fixture.vault.getAllFiles(), isEmpty);
    expect(await File(file.vaultPath).exists(), isFalse);
    expect(crypto.erased, isEmpty);
  });

  test('failed initial receipt write changes no payload, index or tombstone',
      () async {
    final file = await fixture.file('receipt-write');
    await fixture.seed([file]);
    fixture.failWrite = (key, _) => key == VaultStore.recentlyDeletedKey(false);
    expect(await recovery.delete(file), isFalse);
    expect(await File(file.vaultPath).readAsBytes(), [1, 2, 3]);
    expect((await fixture.vault.getAllFiles()).single.id, file.id);
    expect(await SyncStateStore.deletions(), isEmpty);
  });

  test('failed active-index write stays hidden and replays after restart',
      () async {
    final file = await fixture.file('index-write');
    await fixture.seed([file]);
    fixture.failWrite = (key, _) => key == VaultStore.vaultIndexKey;
    expect(await recovery.delete(file), isFalse);
    final receipt = (await fixture.vault.store.loadDeletedItems()).single;
    expect(receipt.stage, DeletionStage.deleting);
    expect(await File(receipt.payloadPath).readAsBytes(), [1, 2, 3]);
    fixture.failWrite = null;
    final reopened = await fixture.reopen();
    expect(await reopened.getAllFiles(), isEmpty);
    expect(await reopened.recentlyDeleted.maintain(), isTrue);
    expect((await reopened.store.loadDeletedItems()).single.stage,
        DeletionStage.trashed);
    expect(await reopened.recentlyDeleted.restore(file.id), isTrue);
    expect((await reopened.getAllFiles()).single.id, file.id);
  });

  test('thumbnail move failure is replayable without losing moved payload',
      () async {
    final file = await fixture.file('thumbnail-retry');
    final path = '${file.vaultPath}.thumb';
    await Directory(path).create();
    final withThumb = file.copyWith(thumbnailPath: path);
    await fixture.seed([withThumb]);
    expect(await recovery.delete(withThumb), isFalse);
    final receipt = (await fixture.vault.store.loadDeletedItems()).single;
    expect(await File(receipt.payloadPath).readAsBytes(), [1, 2, 3]);
    expect((await SyncStateStore.deletions()).containsKey(file.id), isTrue);
    await Directory(path).delete();
    await File(path).writeAsBytes([9]);
    expect(await recovery.maintain(), isTrue);
    expect(await recovery.restore(file.id), isTrue);
    final restored = (await fixture.vault.getAllFiles()).single;
    expect(await File(restored.thumbnailPath!).readAsBytes(), [9]);
  });

  test('partial permanent deletion is non-restorable and retries safely',
      () async {
    final file = await fixture.file('purge-retry');
    final thumb = '${file.vaultPath}.thumb';
    await File(thumb).writeAsBytes([9]);
    final withThumb = file.copyWith(thumbnailPath: thumb);
    await fixture.seed([withThumb]);
    expect(await recovery.delete(withThumb), isTrue);
    final receipt = (await fixture.vault.store.loadDeletedItems()).single;
    crypto.failPath = receipt.thumbnailPath;
    expect(await recovery.permanentlyDelete(file.id), isFalse);
    expect(await File(receipt.payloadPath).exists(), isFalse);
    expect(await File(receipt.thumbnailPath!).readAsBytes(), [9]);
    expect((await fixture.vault.store.loadDeletedItems()).single.stage,
        DeletionStage.purging);
    expect(await recovery.restore(file.id), isFalse);
    crypto.failPath = null;
    expect(await recovery.maintain(), isTrue);
    expect(await fixture.vault.store.loadDeletedItems(), isEmpty);
  });

  test('interrupted restore resumes its unique destination without clobbering',
      () async {
    final file = await fixture.file('restore-write');
    await fixture.seed([file]);
    expect(await recovery.delete(file), isTrue);
    // A different file can now occupy the original location.
    await File(file.vaultPath).writeAsBytes([99]);
    fixture.failWrite = (key, _) => key == VaultStore.vaultIndexKey;
    expect(await recovery.restore(file.id), isFalse);
    final receipt = (await fixture.vault.store.loadDeletedItems()).single;
    expect(receipt.stage, DeletionStage.restoring);
    expect(
        await File(receipt.restoredFile!.vaultPath).readAsBytes(), [1, 2, 3]);
    fixture.failWrite = null;
    final reopened = await fixture.reopen();
    expect(await reopened.recentlyDeleted.maintain(), isTrue);
    expect(await File(file.vaultPath).readAsBytes(), [99]);
    expect((await reopened.getAllFiles()).single.vaultPath,
        receipt.restoredFile!.vaultPath);
    expect(await reopened.store.loadDeletedItems(), isEmpty);
  });

  test('real and decoy receipts, restoration and tombstones stay separate',
      () async {
    final real = await fixture.file('same-id');
    final decoy = await fixture.file('same-id', decoy: true, bytes: [8]);
    await fixture.seed([real]);
    await fixture.seed([decoy], decoy: true);
    expect(await recovery.delete(decoy, isDecoy: true), isTrue);
    expect(await fixture.vault.store.loadDeletedItems(), isEmpty);
    expect(await SyncStateStore.deletions(), isEmpty);
    expect((await fixture.vault.getAllFiles()).single.id, real.id);
    expect(await recovery.restore(decoy.id), isFalse);
    expect(await recovery.restore(decoy.id, isDecoy: true), isTrue);
    final restored = (await fixture.vault.getAllFiles(isDecoy: true)).single;
    expect(restored.isDecoy, isTrue);
    expect(await File(restored.vaultPath).readAsBytes(), [8]);
    expect(await File(real.vaultPath).readAsBytes(), [1, 2, 3]);
  });

  test('busy operations and corrupt receipt storage fail closed', () async {
    final file = await fixture.file('busy');
    await fixture.seed([file]);
    final gate = FileOperationGate.instance;
    final lease = gate.acquire({file.id})!;
    expect(await recovery.delete(file), isFalse);
    expect(await recovery.maintain(), isFalse);
    await gate.run(lease, () async {});
    fixture.storage[VaultStore.recentlyDeletedKey(false)] = '{corrupt';
    expect(await recovery.delete(file), isFalse);
    await expectLater(fixture.vault.getAllFiles(), throwsFormatException);
    expect(await File(file.vaultPath).readAsBytes(), [1, 2, 3]);
  });

  test('lock after receipt commit stops moves and resumes after unlocking',
      () async {
    final file = await fixture.file('lock-during-delete');
    await fixture.seed([file]);
    Future<void>? drained;
    fixture.failWrite = (key, _) {
      if (key == VaultStore.recentlyDeletedKey(false)) {
        drained = FileOperationGate.instance.invalidateAndDrain();
      }
      return false;
    };
    expect(await recovery.delete(file), isFalse);
    await drained;
    expect(await File(file.vaultPath).readAsBytes(), [1, 2, 3]);
    expect((await fixture.vault.store.loadDeletedItems()).single.stage,
        DeletionStage.deleting);
    fixture.failWrite = null;
    expect(await recovery.maintain(), isTrue);
    expect(await recovery.restore(file.id), isTrue);
    final restored = (await fixture.vault.getAllFiles()).single;
    expect(await File(restored.vaultPath).readAsBytes(), [1, 2, 3]);
  });

  test('failed password index removal is hidden from autofill and retryable',
      () async {
    final file = (await fixture.file('login'))
        .copyWith(metadata: {'passwordId': 'login'});
    final password = PasswordEntry(
        id: 'login',
        title: 'Retained login',
        encryptedContentPath: file.vaultPath,
        iv: 'kept-iv',
        keyDerivationSalt: 'kept-salt',
        createdAt: now,
        updatedAt: now);
    fixture.storage['locker_passwords_index'] = jsonEncode([password.toJson()]);
    await fixture.seed([file]);
    expect(await PasswordService.instance.loadPasswords(), hasLength(1));
    fixture.failWrite = (key, _) => key == 'locker_passwords_index';
    expect(await recovery.delete(file), isFalse);
    expect(
        jsonDecode(fixture.storage['locker_passwords_index']!), hasLength(1));
    expect(await PasswordService.instance.loadPasswords(), isEmpty);
    fixture.failWrite = null;
    expect(await recovery.maintain(), isTrue);
    expect(await recovery.restore(file.id), isTrue);
    PasswordService.instance.clearCache();
    final restored = (await PasswordService.instance.loadPasswords()).single;
    expect(restored.iv, password.iv);
    expect(restored.keyDerivationSalt, password.keyDerivationSalt);
    expect(await File(restored.encryptedContentPath).readAsBytes(), [1, 2, 3]);
  });

  test('editor deletion and restoration preserve note/password crypto records',
      () async {
    final noteFile =
        (await fixture.file('note')).copyWith(metadata: {'noteId': 'note'});
    final passwordFile = (await fixture.file('password'))
        .copyWith(metadata: {'passwordId': 'password'});
    final note = Note(
        id: 'note',
        title: 'A note',
        encryptedContentPath: noteFile.vaultPath,
        iv: 'note-iv',
        keyDerivationSalt: 'note-salt',
        isEncrypted: true,
        createdAt: now,
        updatedAt: now,
        isPinned: true);
    final password = PasswordEntry(
        id: 'password',
        title: 'A login',
        encryptedContentPath: passwordFile.vaultPath,
        iv: 'password-iv',
        keyDerivationSalt: 'password-salt',
        isEncrypted: true,
        createdAt: now,
        updatedAt: now,
        tags: ['work']);
    fixture.storage['locker_notes_index'] = jsonEncode([note.toJson()]);
    fixture.storage['locker_passwords_index'] = jsonEncode([password.toJson()]);
    await fixture.seed([noteFile, passwordFile]);
    final singleton = VaultService.instance;
    await singleton.loadIndexesForTesting();
    singleton.clearEditorCaches();
    expect(await NoteService.instance.loadNotes(), hasLength(1));
    expect(await PasswordService.instance.loadPasswords(), hasLength(1));
    await NoteService.instance.deleteNote(note);
    await PasswordService.instance.deletePassword(password);
    expect(await NoteService.instance.loadNotes(), isEmpty);
    expect(await PasswordService.instance.loadPasswords(), isEmpty);
    expect(jsonDecode(fixture.storage['locker_passwords_index']!), isEmpty);
    expect(await singleton.recentlyDeleted.restore('note'), isTrue);
    expect(await singleton.recentlyDeleted.restore('password'), isTrue);
    final restoredNote = (await NoteService.instance.loadNotes()).single;
    final restoredPassword =
        (await PasswordService.instance.loadPasswords()).single;
    expect(restoredNote.iv, note.iv);
    expect(restoredNote.keyDerivationSalt, note.keyDerivationSalt);
    expect(restoredNote.isPinned, isTrue);
    expect(restoredPassword.iv, password.iv);
    expect(restoredPassword.keyDerivationSalt, password.keyDerivationSalt);
    expect(restoredPassword.tags, password.tags);
    expect(
        await File(restoredNote.encryptedContentPath).readAsBytes(), [1, 2, 3]);
    expect(await File(restoredPassword.encryptedContentPath).readAsBytes(),
        [1, 2, 3]);
  });

  test(
      'new ZIP backup excludes trash and its password metadata even with stale selection',
      () async {
    final active = await fixture.file('active');
    final deleted = (await fixture.file('deleted'))
        .copyWith(metadata: {'passwordId': 'deleted'});
    fixture.storage['locker_passwords_index'] = jsonEncode([
      {'id': 'deleted', 'title': 'secret'}
    ]);
    await fixture.seed([active, deleted]);
    expect(await recovery.delete(deleted), isTrue);
    final result = await BackupService(vaultService: fixture.vault)
        .createBackup('${fixture.root.path}/backup', files: [active, deleted]);
    expect(result.success, isTrue, reason: result.error);
    final zip =
        ZipDecoder().decodeBytes(await File(result.zipPath!).readAsBytes());
    expect(zip.files.map((e) => e.name), contains('documents/active.dat'));
    expect(
        zip.files.map((e) => e.name), isNot(contains('documents/deleted.dat')));
    final records = jsonDecode(utf8
        .decode(zip.findFile('_passwords_index.json')!.content as List<int>));
    expect(records, isEmpty);
    expect(await recovery.storageUsed(), 3);
  });

  test('remote conflict choices cannot overwrite a retained local item',
      () async {
    final file = await fixture.file('conflict');
    await fixture.seed([file]);
    expect(await recovery.delete(file), isTrue);
    final sync = SyncService(fixture.vault.store, EncryptionService.instance);
    const profile =
        SyncProfile(id: 'profile', serverUrl: 'https://example.com');
    for (final choice in [ConflictChoice.remote, ConflictChoice.both]) {
      await expectLater(
          sync.chooseConflict(profile, file.id, choice), throwsStateError);
    }
    expect(
        await File((await fixture.vault.store.loadDeletedItems())
                .single
                .payloadPath)
            .readAsBytes(),
        [1, 2, 3]);
  });
}
