import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/encryption_algorithm.dart';
import 'package:locker/models/note.dart';
import 'package:locker/services/note_service.dart';
import 'package:locker/services/vault_service.dart';

import 'support/recovery_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = NoteService.instance;
  late RecoveryFixture fixture;
  setUp(() async {
    fixture = RecoveryFixture();
    await fixture.initialize();
    await VaultService.instance.loadIndexesForTesting();
    service.clearCache();
  });
  tearDown(() async => fixture.dispose());

  for (final encrypt in [false, true]) {
    test('failed ${encrypt ? 'encrypted' : 'plaintext'} edit keeps saved note',
        () async {
      final note = await service.createNote(
        title: 'Original',
        content: 'Saved body',
        encrypt: encrypt,
        isPinned: true,
        kdfIterations: 1000,
      );
      final file = File(note.encryptedContentPath);
      final originalBytes = await file.readAsBytes();
      fixture.failWrite = (key, _) => key == 'locker_notes_index';

      await expectLater(
        service.updateNote(note, title: 'Edited', content: 'Draft body'),
        throwsA(isA<PlatformException>()),
      );
      service.clearCache();
      final reloaded = (await service.loadNotes()).single;
      expect(reloaded.title, 'Original');
      expect(reloaded.isPinned, isTrue);
      expect(reloaded.iv, note.iv);
      expect(reloaded.keyDerivationSalt, note.keyDerivationSalt);
      expect(await file.readAsBytes(), originalBytes);
      expect(await service.decryptNoteContent(reloaded), 'Saved body');
      expect(await file.parent.list().map((file) => file.path).toList(),
          [file.path]);

      fixture.failWrite = null;
      final updated = await service.updateNote(
        reloaded,
        title: 'Edited',
        content: 'Draft body',
      );
      expect(await service.decryptNoteContent(updated), 'Draft body');
    });
  }

  test('failed creation leaves no orphan payload or index record', () async {
    fixture.failWrite = (key, _) => key == 'locker_notes_index';
    await expectLater(
      service.createNote(title: 'Draft', content: 'Unsaved body'),
      throwsA(isA<PlatformException>()),
    );
    expect(await service.loadNotes(forceReload: true), isEmpty);
    expect(
      await Directory('${fixture.root.path}/documents/.locker_vault/notes')
          .list()
          .isEmpty,
      isTrue,
    );
  });

  for (final (format, encrypt, mime) in [
    (NoteFileFormat.markdown, false, 'text/markdown'),
    (NoteFileFormat.html, true, 'text/html'),
  ]) {
    test(
        'new and legacy .${format.extension} notes retain their format on edit',
        () async {
      final vault = VaultService.instance;
      final isDecoy = encrypt;
      final body =
          format == NoteFileFormat.markdown ? '# Heading' : '<h1>Heading</h1>';
      final note = await service.createNote(
        title: 'Original',
        content: body,
        fileExtension: format.extension,
        isMarkdown: format == NoteFileFormat.markdown,
        encrypt: encrypt,
        encryptionAlgorithm: EncryptionAlgorithm.aes256Ctr,
        kdfIterations: 1000,
        isDecoy: isDecoy,
      );
      expect(note.fileFormat, format);
      expect(note.encryptedContentPath,
          endsWith(encrypt ? '.enc' : '.${format.extension}'));
      service.clearCache();
      final saved = (await service.loadNotes(isDecoy: isDecoy)).single;
      expect(saved.fileFormat, format);
      expect(await service.decryptNoteContent(saved, isDecoy: isDecoy), body);

      final key = isDecoy ? 'locker_notes_index_decoy' : 'locker_notes_index';
      final legacy = saved.toJson()..remove('fileExtension');
      fixture.storage[key] = jsonEncode([legacy]);
      service.clearCache();
      final oldNote = (await service.loadNotes(isDecoy: isDecoy)).single;
      expect(oldNote.fileFormat, isNull);
      expect(
          await service.resolveNoteFormat(oldNote, isDecoy: isDecoy), format);

      final renamed = await service.updateNote(oldNote,
          title: 'Renamed', isPinned: true, isDecoy: isDecoy);
      expect(renamed.iv, oldNote.iv);
      final updated = await service.updateNote(
        renamed,
        content: 'Updated body',
        isDecoy: isDecoy,
      );
      expect(updated.fileFormat, format);
      expect(updated.isEncrypted, encrypt);
      expect(updated.encryptionAlgorithm, saved.encryptionAlgorithm);
      expect(updated.kdfIterations, saved.kdfIterations);
      expect(updated.encryptedContentPath, saved.encryptedContentPath);
      expect(await service.decryptNoteContent(updated, isDecoy: isDecoy),
          'Updated body');
      final entry = await vault.getFileById(note.id, isDecoy: isDecoy);
      expect(entry?.originalName, 'Renamed.${format.extension}');
      expect(entry?.mimeType, mime);
      service.clearCache();
      expect((await service.loadNotes(isDecoy: isDecoy)).single.fileFormat,
          format);
    });
  }

  test('decoy notes decrypt in their own vault and stay out of previews',
      () async {
    final real =
        await service.createNote(title: 'Real', content: 'Plaintext body');
    final decoy = await service.createNote(
      title: 'Decoy',
      content: 'Private body',
      encrypt: true,
      isDecoy: true,
      isPinned: true,
      kdfIterations: 1000,
    );
    service.clearCache();
    expect((await service.loadNotes()).map((note) => note.id), [real.id]);
    final reloaded = (await service.loadNotes(isDecoy: true)).single;
    expect(reloaded.id, decoy.id);
    expect(reloaded.isPinned, isTrue);
    expect(await service.decryptNoteContent(reloaded, isDecoy: true),
        'Private body');
    await expectLater(service.decryptNoteContent(reloaded), throwsException);
    expect(await service.loadPlaintextContents([real, reloaded]),
        {real.id: 'Plaintext body'});
    await expectLater(
        service.updateNote(reloaded, title: 'Wrong vault'), throwsStateError);
  });
}
