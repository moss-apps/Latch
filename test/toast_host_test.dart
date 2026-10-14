import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/themes/app_colors.dart';
import 'package:locker/utils/toast_utils.dart';
import 'package:locker/widgets/toast_host.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
        darkTheme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        themeMode: ThemeMode.dark,
        builder: (context, child) =>
            ToastHost(child: child ?? const SizedBox.shrink()),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
  }

  double toastOpacity(WidgetTester tester, String text) => tester
      .widget<Opacity>(find
          .ancestor(of: find.text(text), matching: find.byType(Opacity))
          .first)
      .opacity;

  testWidgets('animates in, holds, then animates out on its own',
      (tester) async {
    await pumpApp(tester);

    ToastUtils.showSuccess('Saved');
    await tester.pump();
    expect(find.text('Saved'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 120));
    final midEntrance = toastOpacity(tester, 'Saved');
    expect(midEntrance, greaterThan(0));
    expect(midEntrance, lessThan(1));

    await tester.pumpAndSettle();
    expect(toastOpacity(tester, 'Saved'), 1.0);

    // The card uses the success color with readable content.
    final card = tester.widget<Material>(find.descendant(
      of: find.byType(ToastHost),
      matching: find.byWidgetPredicate(
        (widget) => widget is Material && widget.color == AppColors.success,
      ),
    ));
    expect(card.elevation, 4);
    expect(tester.widget<Text>(find.text('Saved')).style?.color, Colors.white);

    // After its duration it animates away and leaves the tree.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsNothing);
  });

  testWidgets('a new toast smoothly replaces the visible one', (tester) async {
    await pumpApp(tester);

    ToastUtils.showSuccess('First');
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);

    ToastUtils.showError('Second');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // The first toast is still animating out; the new one waits its turn.
    expect(find.text('First'), findsOneWidget);
    expect(toastOpacity(tester, 'First'), lessThan(1));
    expect(find.text('Second'), findsNothing);

    await tester.pumpAndSettle();
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);

    // Let the error toast dismiss so no timers are left behind.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsNothing);
  });

  testWidgets('untyped toasts follow the theme surface colors', (tester) async {
    await pumpApp(tester);

    ToastUtils.showToast('Hi');
    await tester.pumpAndSettle();

    final scheme =
        ThemeData(brightness: Brightness.dark, useMaterial3: true).colorScheme;
    final card = tester.widget<Material>(find.descendant(
      of: find.byType(ToastHost),
      matching: find.byWidgetPredicate(
        (widget) => widget is Material && widget.color == scheme.inverseSurface,
      ),
    ));
    expect(card.color, scheme.inverseSurface);
    expect(
      tester.widget<Text>(find.text('Hi')).style?.color,
      scheme.onInverseSurface,
    );

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Hi'), findsNothing);
  });
}
