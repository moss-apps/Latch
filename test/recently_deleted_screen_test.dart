import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/providers/recently_deleted_provider.dart';
import 'package:locker/providers/vault_providers.dart';
import 'package:locker/screens/recently_deleted_screen.dart';

import 'support/recovery_fixture.dart';

void main() {
  late RecoveryFixture fixture;
  setUp(() async {
    fixture = RecoveryFixture();
    await fixture.initialize();
  });
  tearDown(() => fixture.dispose());

  testWidgets('large-text recovery keeps destructive confirmations cancellable',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final items = await tester.runAsync(() async {
      final file = await fixture.file('recoverable');
      await fixture.seed([file]);
      expect(await fixture.vault.removeFile(file.id), isTrue);
      return fixture.vault.store.loadDeletedItems();
    });
    await tester.pumpWidget(ProviderScope(
        overrides: [
          vaultServiceProvider.overrideWithValue(fixture.vault),
          recentlyDeletedProvider.overrideWith((_) async => items!),
          recentlyDeletedStorageProvider.overrideWith((_) async => 3),
        ],
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(2.5)),
                child: child!),
            home: const RecentlyDeletedScreen())));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final retention = find.text('Retention for future deletions');
    await tester.ensureVisible(retention);
    await tester.pumpAndSettle();
    await tester.tap(retention);
    await tester.pumpAndSettle();
    final immediate = find.text('Delete immediately');
    await tester.ensureVisible(immediate);
    await tester.pumpAndSettle();
    await tester.tap(immediate);
    await tester.pumpAndSettle();
    expect(
        find.text('Turn off recovery for future deletions?'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
        (await fixture.vault.getSettings()).recentlyDeletedRetentionDays, 30);

    await tester.tap(find.byTooltip('Recovery actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Empty Recently Deleted'));
    await tester.pumpAndSettle();
    expect(find.text('Delete permanently?'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      expect(await fixture.vault.store.loadDeletedItems(), hasLength(1));
      expect(await fixture.vault.recentlyDeleted.storageUsed(), 3);
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
