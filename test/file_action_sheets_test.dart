import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/vaulted_file.dart';
import 'package:locker/widgets/media_hold_action_sheet.dart';
import 'package:locker/widgets/media_multi_select_action_sheet.dart';
import 'package:locker/widgets/sheet_action_row.dart';

VaultedFile _file() => VaultedFile(
      id: 'f1',
      originalName: 'notes.pdf',
      vaultPath: '/vault/notes.pdf.enc',
      type: VaultedFileType.document,
      mimeType: 'application/pdf',
      fileSize: 2048,
      dateAdded: DateTime.now(),
    );

Future<void> _pumpSheet(WidgetTester tester, VoidCallback onOpenSheet) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: onOpenSheet,
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('trigger'));
  await tester.pumpAndSettle();
}

List<String> _rowLabels(WidgetTester tester) => tester
    .widgetList<SheetActionRow>(find.byType(SheetActionRow))
    .map((r) => r.label)
    .toList();

void main() {
  testWidgets('hold sheet shows header, ordered rows, isolated delete',
      (tester) async {
    await _pumpSheet(tester, () {
      unawaited(MediaHoldActionSheet.show(
        tester.state(find.byType(Scaffold)).context,
        file: _file(),
        onFavorite: () {},
        onDelete: () {},
        onInfo: () {},
        onSelect: () {},
        onOpen: () {},
        onTags: () {},
        onExport: () {},
        onAddToAlbum: () {},
      ));
    });

    expect(find.text('notes.pdf'), findsOneWidget);
    expect(find.textContaining('Document'), findsOneWidget);

    final rows =
        tester.widgetList<SheetActionRow>(find.byType(SheetActionRow)).toList();
    expect(_rowLabels(tester),
        ['Open', 'Export', 'Tags', 'Add to album', 'Select', 'Delete']);
    expect(rows.last.isDestructive, isTrue);
    expect(rows.where((r) => r.isDestructive).length, 1);

    expect(find.byTooltip('File info'), findsOneWidget);
    expect(find.byTooltip('Favorite'), findsOneWidget);
  });

  testWidgets('hold sheet only lists wired actions', (tester) async {
    await _pumpSheet(tester, () {
      unawaited(MediaHoldActionSheet.show(
        tester.state(find.byType(Scaffold)).context,
        file: _file(),
        onOpen: () {},
        onDelete: () {},
      ));
    });

    expect(_rowLabels(tester), ['Open', 'Delete']);
    expect(find.byTooltip('File info'), findsNothing);
    expect(find.byTooltip('Favorite'), findsNothing);
  });

  testWidgets('tapping a row fires its callback and closes the sheet',
      (tester) async {
    var exported = false;
    await _pumpSheet(tester, () {
      unawaited(MediaHoldActionSheet.show(
        tester.state(find.byType(Scaffold)).context,
        file: _file(),
        onExport: () => exported = true,
      ));
    });

    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();

    expect(exported, isTrue);
    expect(find.byType(MediaHoldActionSheet), findsNothing);
  });

  testWidgets('header favorite toggle fires callback and closes',
      (tester) async {
    var favorited = false;
    await _pumpSheet(tester, () {
      unawaited(MediaHoldActionSheet.show(
        tester.state(find.byType(Scaffold)).context,
        file: _file(),
        onFavorite: () => favorited = true,
      ));
    });

    await tester.tap(find.byTooltip('Favorite'));
    await tester.pumpAndSettle();

    expect(favorited, isTrue);
    expect(find.byType(MediaHoldActionSheet), findsNothing);
  });

  testWidgets('multi-select sheet lists actions and cancels quietly',
      (tester) async {
    var cancelled = false;
    await _pumpSheet(tester, () {
      unawaited(MediaMultiSelectActionSheet.show(
        tester.state(find.byType(Scaffold)).context,
        fileCount: 3,
        onShare: () {},
        onDelete: () {},
        onFavorite: () {},
        onTags: () {},
        onAddToAlbum: () {},
        onUnhide: () {},
        onCancelSelection: () => cancelled = true,
      ));
    });

    expect(find.text('3 files selected'), findsOneWidget);
    expect(_rowLabels(tester),
        ['Favorite', 'Export', 'Unhide', 'Tags', 'Add to album', 'Delete']);
    final rows =
        tester.widgetList<SheetActionRow>(find.byType(SheetActionRow)).toList();
    expect(rows.last.isDestructive, isTrue);

    await tester.tap(find.text('Cancel selection'));
    await tester.pumpAndSettle();

    expect(cancelled, isTrue);
    expect(find.byType(MediaMultiSelectActionSheet), findsNothing);
  });

  testWidgets('multi-select sheet singularizes one file', (tester) async {
    await _pumpSheet(tester, () {
      unawaited(MediaMultiSelectActionSheet.show(
        tester.state(find.byType(Scaffold)).context,
        fileCount: 1,
        onDelete: () {},
      ));
    });

    expect(find.text('1 file selected'), findsOneWidget);
    expect(_rowLabels(tester), ['Delete']);
  });
}
