import 'package:flutter_test/flutter_test.dart';
import 'package:locker/services/auth_service.dart';
import 'package:locker/utils/secure_compare.dart';

void main() {
  group('constantTimeEquals', () {
    test('equal strings match', () {
      expect(constantTimeEquals('abc123', 'abc123'), isTrue);
    });

    test('different strings do not match', () {
      expect(constantTimeEquals('abc123', 'abc124'), isFalse);
    });

    test('different lengths do not match', () {
      expect(constantTimeEquals('abc', 'abcd'), isFalse);
    });

    test('empty strings match', () {
      expect(constantTimeEquals('', ''), isTrue);
    });
  });

  group('AuthService.validatePasswordStrength', () {
    test('rejects below minimum length', () {
      expect(AuthService.validatePasswordStrength('Ab1!'),
          PasswordStrength.tooShort);
    });

    test('flags short single-class as weak', () {
      expect(AuthService.validatePasswordStrength('abcdefgh'),
          PasswordStrength.weak);
    });

    test('accepts short multi-class', () {
      expect(AuthService.validatePasswordStrength('Abcd1234'),
          PasswordStrength.acceptable);
    });

    test('accepts long single-class passphrase', () {
      expect(AuthService.validatePasswordStrength('longpassphraseonly'),
          PasswordStrength.acceptable);
    });
  });
}
