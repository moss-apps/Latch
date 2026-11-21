import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/encryption_algorithm.dart';
import 'package:locker/models/note.dart';
import 'package:locker/providers/note_providers.dart';
import 'package:locker/providers/vault_providers.dart';
import 'package:locker/screens/note_editor_screen.dart';
import 'package:locker/screens/note_list_screen.dart';
import 'package:locker/services/note_service.dart';
import 'package:locker/themes/app_theme.dart';
import 'package:locker/widgets/note_card.dart';
import 'package:locker/widgets/toast_host.dart';
import 'package:shared_preferences/shared_preferences.dart';

Note _note(String id, String title,
    {bool encrypted = false, bool pin = false}) {
  return Note(
    id: id,
    title: title,
    folderId: 'folder',
    encryptedContentPath: '/unused/$id',
    iv: '',
    keyDerivationSalt: '',
    isEncrypted: encrypted,
    isPinned: pin,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

class _TestNotes implements NoteService {
  final List<Note> notes = [];
  final List<Note> decoyNotes = [];
  final Map<String, String> bodies = {};
  bool failSave = false;
  int saves = 0;
  bool? lastDecoyRead;

  @override
  Future<List<Note>> loadNotes({
    bool isDecoy = false,
    bool forceReload = false,
  }) async =>
      List.of(isDecoy ? decoyNotes : notes);

  @override
  Future<List<NoteFolder>> loadFolders({
    bool isDecoy = false,
    bool forceReload = false,
  }) async =>
      [];

  @override
  Future<Map<String, String>> loadPlaintextContents(List<Note> notes) async =>
      {for (final note in notes) note.id: bodies[note.id] ?? ''};

  @override
  Future<String> decryptNoteContent(Note note, {bool isDecoy = false}) async {
    lastDecoyRead = isDecoy;
    return bodies[note.id] ?? '';
  }

  @override
  Future<NoteFileFormat> resolveNoteFormat(Note note,
          {bool isDecoy = false}) async =>
      note.fileFormat ?? NoteFileFormat.plainText;

  @override
  Future<Note> createNote({
    required String title,
    required String content,
    String? folderId,
    bool isMarkdown = false,
    bool isPinned = false,
    String fileExtension = 'txt',
    bool encrypt = false,
    EncryptionAlgorithm encryptionAlgorithm = EncryptionAlgorithm.aes256Gcm,
    int kdfIterations = 100000,
    bool isDecoy = false,
    void Function(String, {bool isEncrypting})? onProgress,
  }) async {
    saves++;
    if (failSave) throw StateError('Save failed');
    final note =
        _note('new', title, encrypted: encrypt, pin: isPinned).copyWith(
      folderId: folderId,
      clearFolder: folderId == null,
      isMarkdown: isMarkdown,
      fileFormat: NoteFileFormat.fromExtension(fileExtension),
      encryptionAlgorithm: encryptionAlgorithm,
      kdfIterations: kdfIterations,
    );
    (isDecoy ? decoyNotes : notes).add(note);
    bodies[note.id] = content;
    return note;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _open(
  WidgetTester tester,
  _TestNotes service,
  Widget page, {
  bool decoy = false,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        noteServiceProvider.overrideWithValue(service),
        isDecoyModeProvider.overrideWith((ref) => decoy),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: ToastHost(child: child!),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => page),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Finder get _body => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.hintText == 'Note',
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('system Back saves a body-only pinned note in its folder',
      (tester) async {
    final service = _TestNotes();
    await _open(
        tester, service, const NoteEditorScreen(initialFolderId: 'work'));
    await tester.enterText(_body, '# Shopping list\nMilk');
    await tester.tap(find.text('Save options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Markdown (.md)'));
    await tester.tap(find.text('Apply options'));
    await tester.pumpAndSettle();
    expect(service.saves, 0);
    expect(find.text('.md · Not encrypted'), findsOneWidget);
    await tester.tap(find.byTooltip('Preview'));
    await tester.pumpAndSettle();
    expect(find.byType(Markdown), findsOneWidget);
    await tester.tap(find.byTooltip('Pin note'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(service.notes.single.title, 'Shopping list');
    expect(service.notes.single.isPinned, isTrue);
    expect(service.notes.single.folderId, 'work');
    expect(service.notes.single.fileFormat, NoteFileFormat.markdown);
    expect(service.notes.single.isMarkdown, isTrue);
    expect(service.bodies['new'], '# Shopping list\nMilk');
  });

  testWidgets('Done keeps a failed draft open; retry saves without title leak',
      (tester) async {
    final service = _TestNotes()..failSave = true;
    await _open(tester, service, const NoteEditorScreen());
    await tester.enterText(_body, 'Not for the index');
    await tester.tap(find.text('Save options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HTML (.html)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Encrypt note'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Advanced encryption'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('AES-256-CTR'));
    await tester.tap(find.text('AES-256-CTR'));
    await tester.ensureVisible(find.text('200K'));
    await tester.tap(find.text('200K'));
    final apply = find.text('Apply options');
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(find.text('.html · Encrypted'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save note. Your draft is still open.'),
        findsOneWidget);
    expect(
        tester.widget<TextField>(_body).controller!.text, 'Not for the index');
    expect(service.notes, isEmpty);

    service.failSave = false;
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(service.saves, 2);
    expect(service.notes.single.isEncrypted, isTrue);
    expect(service.notes.single.title, 'Untitled note');
    expect(service.notes.single.fileFormat, NoteFileFormat.html);
    expect(service.notes.single.encryptionAlgorithm,
        EncryptionAlgorithm.aes256Ctr);
    expect(service.notes.single.kdfIterations, 200000);
    expect(service.notes.single.isMarkdown, isFalse);
  });

  testWidgets('dismissing Save options does not apply the changes',
      (tester) async {
    final service = _TestNotes();
    await _open(tester, service, const NoteEditorScreen());
    await tester.enterText(_body, 'A plain draft');
    await tester.tap(find.text('Save options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HTML (.html)'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('.txt · Not encrypted'), findsOneWidget);
    expect(service.saves, 0);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(service.notes.single.fileFormat, NoteFileFormat.plainText);
  });

  testWidgets(
      'save options keep chips orderly and advanced details left aligned',
      (tester) async {
    final service = _TestNotes();
    await _open(tester, service, const NoteEditorScreen());
    await tester.tap(find.text('Save options'));
    await tester.pumpAndSettle();

    Finder chipFor(String label) => find.ancestor(
          of: find.text(label),
          matching: find.byType(ChoiceChip),
        );
    Finder checkIn(String label) => find.descendant(
          of: chipFor(label),
          matching: find.byIcon(Icons.check),
        );

    final unselectedChip = tester.getRect(chipFor('Markdown (.md)'));
    final htmlBefore = tester.getRect(chipFor('HTML (.html)'));
    expect(checkIn('Markdown (.md)'), findsNothing);

    // An unselected chip's label starts at the same inset a selected chip's
    // check icon uses, so unselected chips have no empty leading gap.
    final labelInset =
        tester.getTopLeft(find.text('Markdown (.md)')).dx - unselectedChip.left;

    await tester.tap(find.text('Markdown (.md)'));
    await tester.pumpAndSettle();

    final selectedChip = tester.getRect(chipFor('Markdown (.md)'));
    expect(checkIn('Markdown (.md)'), findsOneWidget);
    expect(tester.getTopLeft(checkIn('Markdown (.md)')).dx - selectedChip.left,
        labelInset);
    // Selecting a chip may widen it, but it stays on the same row and keeps
    // the following chip beside it instead of wrapping it somewhere else.
    expect(selectedChip.top, unselectedChip.top);
    expect(tester.getRect(chipFor('HTML (.html)')).top, htmlBefore.top);
    expect(tester.getRect(chipFor('HTML (.html)')).left,
        greaterThanOrEqualTo(selectedChip.right));

    await tester.tap(find.text('Encrypt note'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Advanced encryption'));
    await tester.pumpAndSettle();

    expect(find.byType(Divider), findsOneWidget);
    final advanced = tester.widget<ExpansionTile>(find.byType(ExpansionTile));
    expect(advanced.shape, const Border());
    expect(advanced.collapsedShape, const Border());

    final headerLeft = tester.getTopLeft(find.text('Advanced encryption')).dx;
    expect(tester.getTopLeft(find.text('Algorithm')).dx, headerLeft);
    expect(tester.getTopLeft(find.text('KDF iterations')).dx, headerLeft);
    expect(tester.getTopLeft(chipFor('AES-256-GCM')).dx, headerLeft);
    expect(tester.getTopLeft(chipFor('100K')).dx, headerLeft);
  });

  testWidgets('existing note shows its saved format and encryption read-only',
      (tester) async {
    final service = _TestNotes();
    final note = _note('locked', 'Existing', encrypted: true)
        .copyWith(fileFormat: NoteFileFormat.html, kdfIterations: 200000);
    await _open(tester, service, NoteEditorScreen(note: note));
    await tester.tap(find.text('Save options'));
    await tester.pumpAndSettle();
    expect(find.text('HTML (.html)'), findsOneWidget);
    expect(find.text('AES-256-GCM · 200000 KDF iterations'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Edit note'), findsOneWidget);
    expect(service.saves, 0);
  });

  testWidgets('empty draft leaves without saving', (tester) async {
    final service = _TestNotes();
    await _open(tester, service, const NoteEditorScreen());
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(service.saves, 0);
  });

  testWidgets(
      'opening a decoy note uses decoy mode; unchanged note is not saved',
      (tester) async {
    final service = _TestNotes()..bodies['decoy'] = 'Decoy draft';
    await _open(
      tester,
      service,
      NoteEditorScreen(note: _note('decoy', 'Decoy', encrypted: true)),
      decoy: true,
    );
    expect(service.lastDecoyRead, isTrue);
    expect(tester.widget<TextField>(_body).controller!.text, 'Decoy draft');
    await tester.tap(find.byTooltip('Save and close'));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(service.saves, 0);
  });

  testWidgets('changing vaults clears search and replaces the note list',
      (tester) async {
    final service = _TestNotes()
      ..notes.add(_note('real', 'Real note'))
      ..decoyNotes.add(_note('decoy', 'Decoy note'));
    await _open(tester, service, const NoteListScreen());
    await tester.enterText(find.byType(TextField), 'Real');
    await tester.pumpAndSettle();
    expect(find.text('Real note'), findsOneWidget);

    final container =
        ProviderScope.containerOf(tester.element(find.byType(NoteListScreen)));
    container.read(isDecoyModeProvider.notifier).state = true;
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(find.text('Real note'), findsNothing);
    expect(find.text('Decoy note'), findsOneWidget);
  });

  testWidgets('editor stays usable with large text and an open keyboard',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 660);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    final service = _TestNotes();
    await _open(
        tester, service, const NoteEditorScreen(initialFolderId: 'work'),
        textScale: 2);
    await tester.enterText(_body, 'Draft');
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Done').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Change folder').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Save options'));
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Apply options'));
    expect(find.text('Apply options').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('list searches body text without exposing encrypted notes',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 760);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _TestNotes()
      ..notes.addAll([
        _note('visible', 'Packing', pin: true),
        _note('hidden', 'Encrypted', encrypted: true),
      ])
      ..bodies
          .addAll({'visible': 'camera and boots', 'hidden': 'camera secret'});
    await _open(tester, service, const NoteListScreen(), textScale: 2);
    expect(find.text('Pinned'), findsOneWidget);
    expect(find.text('Other notes'), findsOneWidget);
    expect(find.text('camera secret'), findsNothing);
    expect(
        tester.widgetList<NoteCard>(find.byType(NoteCard)),
        everyElement(
            isA<NoteCard>().having((card) => card.isGrid, 'grid', true)));

    await tester.tap(find.byTooltip('List view'));
    await tester.pumpAndSettle();
    expect(
        tester.widgetList<NoteCard>(find.byType(NoteCard)),
        everyElement(
            isA<NoteCard>().having((card) => card.isGrid, 'grid', false)));
    await tester.enterText(find.byType(TextField), 'camera');
    await tester.pumpAndSettle();
    expect(find.text('Packing'), findsOneWidget);
    expect(find.text('Encrypted'), findsNothing);
    expect(tester.takeException(), isNull);
    expect((await SharedPreferences.getInstance()).getString('notes_layout'),
        'list');
  });
}
