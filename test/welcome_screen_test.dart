import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/screens/auth_method_selection_screen.dart';
import 'package:locker/widgets/animated_latch_logo.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
        darkTheme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        themeMode:
            brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        home: const AuthMethodSelectionScreen(),
      ),
    );
  }

  double titleOpacity(WidgetTester tester) => tester
      .widgetList<Opacity>(find.ancestor(
          of: find.text('Welcome to Latch'), matching: find.byType(Opacity)))
      .first
      .opacity;

  testWidgets('builds in light and dark, shows logo, title and method cards',
      (tester) async {
    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Latch'), findsOneWidget);
    expect(find.text('PIN'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Biometrics'), findsOneWidget);
    expect(find.byType(AnimatedLatchLogo), findsOneWidget);

    await pumpScreen(tester, brightness: Brightness.dark);
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Latch'), findsOneWidget);
    expect(find.byType(AnimatedLatchLogo), findsOneWidget);
  });

  testWidgets('entrance animates the title from invisible to fully visible',
      (tester) async {
    await pumpScreen(tester);
    expect(titleOpacity(tester), lessThan(0.2));

    await tester.pumpAndSettle();
    expect(titleOpacity(tester), equals(1.0));
  });
}
