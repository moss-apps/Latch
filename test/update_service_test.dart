import 'package:flutter_test/flutter_test.dart';
import 'package:pub_semver/pub_semver.dart';

void main() {
  group('update version ordering', () {
    test('newer pre-release tag beats current', () {
      expect(Version.parse('0.15.0-beta.2') > Version.parse('0.15.0-beta.1'),
          isTrue);
    });

    test('older tag does not beat current', () {
      expect(Version.parse('0.14.4-beta.4') > Version.parse('0.15.0-beta.1'),
          isFalse);
    });

    test('release is newer than its own pre-release', () {
      expect(Version.parse('0.15.0') > Version.parse('0.15.0-beta.1'), isTrue);
    });

    test('equal versions are not newer', () {
      expect(Version.parse('0.15.0-beta.1') > Version.parse('0.15.0-beta.1'),
          isFalse);
    });
  });
}
