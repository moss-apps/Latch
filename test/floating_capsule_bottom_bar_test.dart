import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/widgets/floating_capsule_bottom_bar.dart';

const _labels = ['All', 'Images', 'Videos', 'Songs', 'Docs'];

void main() {
  for (final width in [240.0, 320.0, 600.0]) {
    for (final scale in [1.0, 2.0, 3.2]) {
      testWidgets(
          'all destinations and import work at width $width, scale $scale',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final tapped = <String>[];
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: Scaffold(
                bottomNavigationBar: FloatingCapsuleBottomBar(
                    tabs: [
                  for (final label in _labels)
                    NavTab(
                        icon: Icons.folder,
                        label: label,
                        selected: label == 'All',
                        onTap: () => tapped.add(label))
                ],
                    feature: NavTab(
                        icon: Icons.add,
                        label: 'Import',
                        selected: false,
                        onTap: () => tapped.add('Import')))),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final scrolls =
              tester.widgetList(find.byType(SingleChildScrollView)).isNotEmpty;
          expect(
              tester.getSemantics(find.bySemanticsLabel('All')),
              matchesSemantics(
                  label: 'All',
                  isButton: true,
                  hasSelectedState: true,
                  isSelected: true,
                  isFocusable: scrolls,
                  hasFocusAction: scrolls,
                  hasTapAction: true));
          for (final label in _labels) {
            await tester.ensureVisible(find.text(label));
            await tester.pumpAndSettle();
            await tester.tap(find.text(label));
            expect(tapped.last, label);
            final size = tester.getSize(find.bySemanticsLabel(label));
            expect(size.width, greaterThanOrEqualTo(48));
            expect(size.height, greaterThanOrEqualTo(48));
          }
          await tester.tap(find.byTooltip('Import'));
          expect(tapped.last, 'Import');
          expect(tester.getSize(find.bySemanticsLabel('Import')).shortestSide,
              greaterThanOrEqualTo(48));
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
    }
  }

  testWidgets(
      'selection mode does not drop Docs and keyboard can activate tabs',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            bottomNavigationBar: FloatingCapsuleBottomBar(
                showFeature: false,
                tabs: [
                  for (final label in _labels)
                    NavTab(
                        icon: Icons.folder,
                        label: label,
                        selected: label == 'Docs',
                        onTap: () => activated = label)
                ],
                feature: NavTab(
                    icon: Icons.add,
                    label: 'Import',
                    selected: false,
                    onTap: () {})))));
    await tester.pumpAndSettle();
    expect(find.text('Docs'), findsOneWidget);
    expect(find.byTooltip('Import'), findsNothing);
    activated = null;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(activated, isNotNull);
  });
}

String? activated;
