import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/screens/legal_consent_screen.dart';
import 'package:locker/services/legal_consent_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('legal consent versioning', () {
    test('current version is accepted, older is not', () {
      expect(
          LegalConsentService.versionAccepted(
              LegalConsentService.legalVersion),
          isTrue);
      expect(
          LegalConsentService.versionAccepted(
              LegalConsentService.legalVersion - 1),
          isFalse);
    });

    test('missing acceptance (null) is not accepted', () {
      expect(LegalConsentService.versionAccepted(null), isFalse);
    });

    test('canonical version.txt matches the service version', () {
      final raw =
          File('legal/version.txt').readAsStringSync().trim();
      expect(int.parse(raw), LegalConsentService.legalVersion);
    });

    test('all canonical legal docs exist', () {
      for (final name in ['eula.md', 'terms.md', 'privacy.md']) {
        expect(File('legal/$name').existsSync(), isTrue,
            reason: 'missing legal/$name');
      }
    });

    testWidgets('consent screen shows tabs and records acceptance',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      var accepted = false;
      await tester.pumpWidget(
        MaterialApp(
          home: LegalConsentScreen(onAccepted: () => accepted = true),
        ),
      );

      expect(find.text('Before you use Latch'), findsOneWidget);
      expect(find.text('License Agreement'), findsOneWidget);
      expect(find.text('Terms'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('I accept'), findsOneWidget);

      await tester.tap(find.text('I accept'));
      await tester.pumpAndSettle();

      expect(accepted, isTrue);
      expect(await LegalConsentService().isAccepted(), isTrue);
    });
  });
}
