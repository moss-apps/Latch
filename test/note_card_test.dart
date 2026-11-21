import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/note.dart';
import 'package:locker/themes/app_theme.dart';
import 'package:locker/utils/note_text.dart';
import 'package:locker/widgets/note_card.dart';

Note _note({
  String title = 'Trip checklist',
  bool isPinned = true,
  bool isEncrypted = false,
  bool isMarkdown = true,
}) {
  final now = DateTime(2026, 11, 22, 12);
  return Note(
    id: 'note-1',
    title: title,
    encryptedContentPath: '/tmp/note.txt',
    iv: '',
    keyDerivationSalt: '',
    isPinned: isPinned,
    isMarkdown: isMarkdown,
    isEncrypted: isEncrypted,
    createdAt: now,
    updatedAt: now,
  );
}

Widget _wrap({
  required Widget child,
  required double textScale,
}) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(400, 800),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        body: Center(child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('grid card shows title, preview, and pin', (tester) async {
    await tester.pumpWidget(
      _wrap(
        textScale: 1,
        child: SizedBox(
          width: 160,
          height: 196,
          child: NoteCard(
            note: _note(),
            preview: 'Pack bags, charge camera, and print the tickets.',
            isGrid: true,
            onTap: () {},
            onTogglePin: () {},
            onDelete: () {},
          ),
        ),
      ),
    );

    expect(find.text('Trip checklist'), findsOneWidget);
    expect(find.textContaining('Pack bags'), findsOneWidget);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('grid card survives large text without overflow', (tester) async {
    await tester.pumpWidget(
      _wrap(
        textScale: 2,
        child: SizedBox(
          width: 260,
          height: 280,
          child: NoteCard(
            note: _note(
              title:
                  'A very long note title that needs to wrap across lines without breaking the card',
            ),
            preview:
                'A long preview body that keeps going so the card has to clip it cleanly instead of overflowing. '
                'It should stay inside the rounded surface at large text sizes.',
            isGrid: true,
            onTap: () {},
            onTogglePin: () {},
            onDelete: () {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('selection mode keeps grid card details in place',
      (tester) async {
    final note = _note();
    final dateLabel = formatNoteDate(note.updatedAt);

    Widget build({required bool selectionMode}) => _wrap(
          textScale: 1,
          child: SizedBox(
            width: 160,
            height: 196,
            child: NoteCard(
              note: note,
              preview: 'Pack bags',
              isGrid: true,
              isSelected: selectionMode,
              isSelectionMode: selectionMode,
              onTap: () {},
              onLongPress: () {},
              onTogglePin: () {},
              onDelete: () {},
            ),
          ),
        );

    await tester.pumpWidget(build(selectionMode: false));
    final datePosition = tester.getTopLeft(find.text(dateLabel));
    final previewPosition = tester.getTopLeft(find.text('Pack bags'));
    final cardSize = tester.getSize(find.byType(NoteCard));

    await tester.pumpWidget(build(selectionMode: true));
    expect(tester.getTopLeft(find.text(dateLabel)), datePosition);
    expect(tester.getTopLeft(find.text('Pack bags')), previewPosition);
    expect(tester.getSize(find.byType(NoteCard)), cardSize);
  });

  testWidgets('selection mode keeps a list card from changing height',
      (tester) async {
    final note = _note(isPinned: false);

    Widget build({required bool selectionMode}) => _wrap(
          textScale: 1,
          child: SizedBox(
            width: 340,
            child: NoteCard(
              note: note,
              preview: 'Pack bags',
              isGrid: false,
              isSelected: selectionMode,
              isSelectionMode: selectionMode,
              onTap: () {},
              onLongPress: () {},
              onTogglePin: () {},
              onDelete: () {},
            ),
          ),
        );

    await tester.pumpWidget(build(selectionMode: false));
    final normalSize = tester.getSize(find.byType(NoteCard));

    await tester.pumpWidget(build(selectionMode: true));
    expect(tester.getSize(find.byType(NoteCard)), normalSize);
  });

  testWidgets('list card renders compactly', (tester) async {
    await tester.pumpWidget(
      _wrap(
        textScale: 1,
        child: SizedBox(
          width: 340,
          child: NoteCard(
            note: _note(isPinned: false),
            preview: 'Pack bags, charge camera.',
            isGrid: false,
            isSelected: true,
            isSelectionMode: true,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection mode replaces the menu and shows a check',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        textScale: 1,
        child: SizedBox(
          width: 160,
          height: 196,
          child: NoteCard(
            note: _note(isEncrypted: true),
            isGrid: true,
            isSelectionMode: true,
            onTogglePin: () {},
            onDelete: () {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.circle_outlined), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
