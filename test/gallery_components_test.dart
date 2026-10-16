import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/vault_category.dart';
import 'package:locker/models/vault_file_filter.dart';
import 'package:locker/models/vaulted_file.dart';
import 'package:locker/services/gallery_file_query.dart';
import 'package:locker/widgets/gallery/gallery_import_sheet.dart';

VaultedFile _file(String name, VaultedFileType type, {bool favorite = false}) =>
    VaultedFile(
        id: name,
        originalName: name,
        vaultPath: '/vault/$name',
        type: type,
        mimeType: 'application/octet-stream',
        fileSize: 10,
        dateAdded: DateTime.utc(2024),
        isFavorite: favorite);

void main() {
  test(
      'gallery display and selection share category, search and structured filters',
      () {
    final files = [
      _file('Report.pdf', VaultedFileType.document, favorite: true),
      _file('Report.bin', VaultedFileType.other, favorite: true),
      _file('Report.jpg', VaultedFileType.image, favorite: true),
      _file('Private.pdf', VaultedFileType.document),
    ];
    final result = queryGalleryFiles(files,
        category: VaultCategory.docs,
        search: 'REPORT',
        filter: const VaultFileFilter(isFavorite: true));
    expect(result.map((f) => f.id), ['Report.pdf', 'Report.bin']);
    result.clear();
    expect(files, hasLength(4));
    expect(queryGalleryFiles(files, category: VaultCategory.images).single.id,
        'Report.jpg');
    expect(
        queryGalleryFiles(files,
                category: VaultCategory.all,
                filter: const VaultFileFilter(isFavorite: false))
            .single
            .id,
        'Private.pdf');
  });

  testWidgets('extracted import sheet preserves all ten actions at large fonts',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final tapped = <GalleryImportAction>[];
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2.5)),
            child: child!),
        home: Scaffold(
            body: Align(
                alignment: Alignment.bottomCenter,
                child: GalleryImportSheet(actions: {
                  for (final action in GalleryImportAction.values)
                    action: () => tapped.add(action)
                })))));
    for (final action in GalleryImportAction.values) {
      final label = find.text(action.presentation.$1);
      await tester.ensureVisible(label);
      await tester.pumpAndSettle();
      await tester.tap(label);
      expect(tapped.last, action);
      expect(tester.takeException(), isNull);
    }
    expect(tapped, GalleryImportAction.values);
  });

  testWidgets('import sheet cancellation pops only the sheet route',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) =>
                              const GalleryImportSheet(actions: {})),
                      child: const Text('Open import')),
                ))));
    await tester.tap(find.text('Open import'));
    await tester.pumpAndSettle();
    expect(find.byType(GalleryImportSheet), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(GalleryImportSheet), findsNothing);
    expect(find.text('Open import'), findsOneWidget);
  });
}
