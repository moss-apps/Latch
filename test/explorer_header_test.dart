import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/vault_folder.dart';
import 'package:locker/providers/explorer_providers.dart';
import 'package:locker/providers/vault_providers.dart';
import 'package:locker/widgets/explorer_toolbar.dart';
import 'package:locker/widgets/folder_breadcrumb_widget.dart';

void main() {
  final now = DateTime(2026);
  final folders = [
    VaultFolder(
        id: 'photos',
        name: 'Photos',
        createdAt: now,
        updatedAt: now),
    VaultFolder(
        id: 'trips',
        name: 'Trips',
        parentId: 'photos',
        createdAt: now,
        updatedAt: now),
  ];

  Widget subject({
    required double width,
    String? folderId,
    double textScale = 1.0,
  }) {
    return ProviderScope(
      overrides: [
        foldersProvider.overrideWith((_) async => folders),
        explorerCurrentFolderIdProvider.overrideWith((_) => folderId),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          appBar: AppBar(
            title: FolderBreadcrumbWidget(
              title: folderId == null ? 'My Vault' : 'Trips',
            ),
          ),
          body: const Column(children: [ExplorerToolbar()]),
        ),
      ),
    );
  }

  Future<void> pumpAt(WidgetTester tester, Widget widget, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
  }

  testWidgets('narrow toolbar uses a filter dropdown that switches types',
      (tester) async {
    await pumpAt(tester, subject(width: 360), const Size(360, 640));

    expect(find.text('All'), findsOneWidget);
    expect(find.byTooltip('Sort Files'), findsOneWidget);
    expect(find.byTooltip('Switch to List View'), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Images').last);
    await tester.pumpAndSettle();

    expect(find.text('Images'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide toolbar keeps all filter chips visible', (tester) async {
    await pumpAt(tester, subject(width: 800), const Size(800, 640));

    for (final label in ['All', 'Images', 'Videos', 'Songs', 'Documents']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('folder title menu lists the path and navigates to a parent',
      (tester) async {
    await pumpAt(
        tester, subject(width: 360, folderId: 'trips'), const Size(360, 640));

    expect(find.text('Trips'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String?>));
    await tester.pumpAndSettle();

    expect(find.text('My Vault'), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);

    await tester.tap(find.text('My Vault').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('header survives large text on a narrow screen', (tester) async {
    await pumpAt(
        tester,
        subject(width: 320, folderId: 'trips', textScale: 2.0),
        const Size(320, 640));

    expect(tester.takeException(), isNull);
  });
}
