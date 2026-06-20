import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';
import '../utils/pbkdf2_isolate.dart';
import '../utils/secure_compare.dart';
import 'auto_kill_service.dart';
import 'decoy_service.dart';
import 'encryption_service.dart';
import 'vault_service.dart';

/// Authentication service that handles password and biometric authentication
class AuthService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device),
  );

  static const String _passwordHashKey = 'user_password_hash';
  static const String _pinHashKey = 'user_pin_hash';
  static const String _backupPasswordHashKey = 'backup_password_hash';
  static const String _backupPinHashKey = 'backup_pin_hash';
  static const String _passwordSaltKey = 'user_password_salt';
  static const String _pinSaltKey = 'user_pin_salt';
  static const String _backupPasswordSaltKey = 'backup_password_salt';
  static const String _backupPinSaltKey = 'backup_pin_salt';
  static const String _passwordIterationsKey = 'user_password_iterations';
  static const String _pinIterationsKey = 'user_pin_iterations';
  static const String _backupPasswordIterationsKey = 'backup_password_iterations';
  static const String _backupPinIterationsKey = 'backup_pin_iterations';
  static const String _hashVersionKey = 'hash_version';
  static const String _firstTimeKey = 'is_first_time';
  static const String _biometricsEnabledKey = 'biometrics_enabled';
  static const String _authMethodKey =
      'auth_method'; // 'pin', 'password', 'biometric'
  static const String _failedUnlockAttemptsKey = 'failed_unlock_attempts';
  static const String _totalFailedUnlockAttemptsKey =
      'total_failed_unlock_attempts';
  static const String _unlockLockoutUntilKey = 'unlock_lockout_until';

  final LocalAuthentication _localAuth = LocalAuthentication();
  final VaultService _vaultService = VaultService.instance;
  final DecoyService _decoyService = DecoyService.instance;

  /// Check if this is the first time launching the app (no password set)
  Future<bool> isFirstTime() async {
    try {
      final isFirstTime = await _storage.read(key: _firstTimeKey);
      return isFirstTime == null || isFirstTime == 'true';
    } catch (e) {
      return true; // Default to first time if there's an error
    }
  }

  /// Create and store the user's password
  Future<bool> createPassword(String password) async {
    try {
      if (password.length < minPasswordLength) return false;

      await _createHashedCredential(password, _passwordSaltKey, _passwordHashKey, _passwordIterationsKey);
      await _storage.write(key: _firstTimeKey, value: 'false');
      await _storage.write(key: _authMethodKey, value: 'password');
      EncryptionService.instance.setPendingCredential(password);

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Create and store the user's PIN (6 digits)
  Future<bool> createPIN(String pin) async {
    try {
      if (pin.isEmpty || pin.length != 6) return false;

      if (!RegExp(r'^[0-9]{6}$').hasMatch(pin)) return false;

      await _createHashedCredential(pin, _pinSaltKey, _pinHashKey, _pinIterationsKey);
      await _storage.write(key: _firstTimeKey, value: 'false');
      await _storage.write(key: _authMethodKey, value: 'pin');
      EncryptionService.instance.setPendingCredential(pin);

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Verify the provided PIN against stored hash
  Future<bool> verifyPIN(String pin) async {
    if (await _verifyCredential(pin, _pinHashKey, _pinSaltKey, _pinIterationsKey)) {
      EncryptionService.instance.setPendingCredential(pin);
      return true;
    }
    return _verifyCredential(pin, _backupPinHashKey, _backupPinSaltKey, _backupPinIterationsKey);
  }

  Future<bool> verifyPassword(String password) async {
    if (await _verifyCredential(password, _passwordHashKey, _passwordSaltKey, _passwordIterationsKey)) {
      EncryptionService.instance.setPendingCredential(password);
      return true;
    }
    return _verifyCredential(password, _backupPasswordHashKey, _backupPasswordSaltKey, _backupPasswordIterationsKey);
  }

  /// Verify backup password (used when current auth is biometric)
  Future<bool> verifyBackupPassword(String password) async {
    return _verifyCredential(password, _backupPasswordHashKey, _backupPasswordSaltKey, _backupPasswordIterationsKey);
  }

  /// Verify backup PIN (used when current auth is biometric)
  Future<bool> verifyBackupPin(String pin) async {
    return _verifyCredential(pin, _backupPinHashKey, _backupPinSaltKey, _backupPinIterationsKey);
  }

  /// Check if biometric authentication is available on the device
  Future<String?> getBackupAuthMethod() async {
    try {
      final backupPinHash = await _storage.read(key: _backupPinHashKey);
      if (backupPinHash != null) return 'pin';
      final backupPasswordHash = await _storage.read(key: _backupPasswordHashKey);
      if (backupPasswordHash != null) return 'password';
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<bool> isBiometricAvailable() async {
    try {
      final isAvailable = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      return isAvailable && isDeviceSupported;
    } catch (e) {
      return false;
    }
  }

  /// Get available biometric types
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }

  /// Check if biometric authentication is enabled by the user
  Future<bool> isBiometricEnabled() async {
    try {
      final enabled = await _storage.read(key: _biometricsEnabledKey);
      return enabled == 'true';
    } catch (e) {
      return false;
    }
  }

  /// Enable or disable biometric authentication
  Future<bool> setBiometricEnabled(bool enabled) async {
    try {
      await _storage.write(
          key: _biometricsEnabledKey, value: enabled.toString());
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Authenticate using biometrics
  Future<bool> authenticateWithBiometrics({
    String reason = 'Please authenticate to access your locker',
  }) async {
    final result = await performBiometricAuthentication(reason: reason);
    return result.isSuccess;
  }

  /// Authenticate using biometrics and return a detailed result.
  Future<BiometricAuthenticationResult> performBiometricAuthentication({
    String reason = 'Please authenticate to access your locker',
  }) async {
    try {
      final isAvailable = await isBiometricAvailable();
      if (!isAvailable) {
        return const BiometricAuthenticationResult(
          status: BiometricAuthenticationStatus.unavailable,
        );
      }

      final isEnabled = await isBiometricEnabled();
      if (!isEnabled) {
        return const BiometricAuthenticationResult(
          status: BiometricAuthenticationStatus.unavailable,
        );
      }

      final isAuthenticated =
          await AutoKillService.runSafe(() => _localAuth.authenticate(
                localizedReason: reason,
                biometricOnly: true,
                authMessages: [
                  const AndroidAuthMessages(
                    signInTitle: 'Biometric authentication required',
                    cancelButton: 'No thanks',
                  ),
                  const IOSAuthMessages(
                    cancelButton: 'No thanks',
                  ),
                ],
              ));

      return BiometricAuthenticationResult(
        status: isAuthenticated
            ? BiometricAuthenticationStatus.success
            : BiometricAuthenticationStatus.failed,
      );
    } on PlatformException catch (e) {
      if (e.code == 'UserCanceled' ||
          e.code == 'Canceled' ||
          e.code == 'SystemCanceled') {
        return const BiometricAuthenticationResult(
          status: BiometricAuthenticationStatus.canceled,
        );
      }

      if (e.code == 'LockedOut' || e.code == 'PermanentlyLockedOut') {
        return const BiometricAuthenticationResult(
          status: BiometricAuthenticationStatus.lockedOut,
        );
      }

      return const BiometricAuthenticationResult(
        status: BiometricAuthenticationStatus.unavailable,
      );
    } catch (e) {
      return const BiometricAuthenticationResult(
        status: BiometricAuthenticationStatus.unavailable,
      );
    }
  }

  /// Setup biometric authentication (should be called after password is set)
  Future<bool> setupBiometricAuthentication() async {
    try {
      debugPrint('[AuthService] Checking biometric availability...');
      final isAvailable = await isBiometricAvailable();
      debugPrint('[AuthService] Biometric available: $isAvailable');

      if (!isAvailable) {
        debugPrint('[AuthService] Biometric not available');
        return false;
      }

      debugPrint('[AuthService] Getting available biometrics...');
      final biometrics = await getAvailableBiometrics();
      debugPrint('[AuthService] Available biometrics: $biometrics');

      if (biometrics.isEmpty) {
        debugPrint('[AuthService] No biometrics enrolled');
        return false;
      }

      debugPrint('[AuthService] Requesting biometric authentication...');
      final isAuthenticated =
          await AutoKillService.runSafe(() => _localAuth.authenticate(
                localizedReason: 'Set up biometric authentication',
                biometricOnly: true,
                authMessages: [
                  const AndroidAuthMessages(
                    signInTitle: 'Set up biometric authentication',
                    cancelButton: 'Cancel setup',
                  ),
                  const IOSAuthMessages(
                    cancelButton: 'Cancel setup',
                  ),
                ],
              ));

      debugPrint('[AuthService] Authentication result: $isAuthenticated');

      if (isAuthenticated) {
        debugPrint('[AuthService] Saving biometric settings...');
        await setBiometricEnabled(true);

        // Store current credentials as backup before switching to biometric
        final currentMethod = await getAuthMethod();
        if (currentMethod == 'password') {
          final currentPassword = await _storage.read(key: _passwordHashKey);
          final currentPasswordSalt = await _storage.read(key: _passwordSaltKey);
          final currentPasswordIterations = await _storage.read(key: _passwordIterationsKey);
          if (currentPassword != null) {
            await _storage.write(
                key: _backupPasswordHashKey, value: currentPassword);
          }
          if (currentPasswordSalt != null) {
            await _storage.write(
                key: _backupPasswordSaltKey, value: currentPasswordSalt);
          }
          if (currentPasswordIterations != null) {
            await _storage.write(
                key: _backupPasswordIterationsKey, value: currentPasswordIterations);
          }
        } else if (currentMethod == 'pin') {
          final currentPin = await _storage.read(key: _pinHashKey);
          final currentPinSalt = await _storage.read(key: _pinSaltKey);
          final currentPinIterations = await _storage.read(key: _pinIterationsKey);
          if (currentPin != null) {
            await _storage.write(key: _backupPinHashKey, value: currentPin);
          }
          if (currentPinSalt != null) {
            await _storage.write(key: _backupPinSaltKey, value: currentPinSalt);
          }
          if (currentPinIterations != null) {
            await _storage.write(key: _backupPinIterationsKey, value: currentPinIterations);
          }
        }

        await _storage.write(key: _firstTimeKey, value: 'false');
        await _storage.write(key: _authMethodKey, value: 'biometric');
        await EncryptionService.instance.setupBiometricKwk();
        debugPrint('[AuthService] Biometric setup complete');
        return true;
      }

      debugPrint('[AuthService] Authentication failed or cancelled');
      return false;
    } on PlatformException catch (e) {
      debugPrint('[AuthService] PlatformException: ${e.code} - ${e.message}');
      // Handle specific biometric errors
      if (e.code == 'NotAvailable') {
        debugPrint('[AuthService] Biometric not available on device');
        return false;
      } else if (e.code == 'NotEnrolled') {
        debugPrint('[AuthService] No biometric enrolled');
        return false;
      } else if (e.code == 'LockedOut' || e.code == 'PermanentlyLockedOut') {
        debugPrint('[AuthService] Biometric locked out');
        return false;
      } else if (e.code == 'UserCanceled' || e.code == 'Canceled') {
        debugPrint('[AuthService] User cancelled authentication');
        return false;
      }
      debugPrint('[AuthService] Unknown platform exception: ${e.code}');
      return false;
    } catch (e) {
      debugPrint('[AuthService] Unknown error: $e');
      return false;
    }
  }

  /// Get the authentication method type
  Future<String?> getAuthMethod() async {
    try {
      return await _storage.read(key: _authMethodKey);
    } catch (e) {
      return null;
    }
  }

  /// Set the authentication method type
  Future<bool> setAuthMethod(String method) async {
    try {
      await _storage.write(key: _authMethodKey, value: method);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Check if authentication method is set up
  Future<bool> isAuthMethodSetup() async {
    final method = await getAuthMethod();
    return method != null;
  }

  /// Change the user's password (requires current password verification)
  Future<bool> changePassword(
      String currentPassword, String newPassword) async {
    try {
      if (currentPassword.isEmpty || newPassword.length < minPasswordLength) return false;

      final isVerified = await verifyPassword(currentPassword);
      if (!isVerified) return false;

      await _createHashedCredential(newPassword, _passwordSaltKey, _passwordHashKey, _passwordIterationsKey);
      await _storage.write(key: _authMethodKey, value: 'password');
      await _storage.write(key: _biometricsEnabledKey, value: 'false');
      await _clearBackupCredentials();
      await EncryptionService.instance.reWrapKey(newPassword);
      await EncryptionService.instance.removeBiometricKwk();

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Change the user's PIN (requires current PIN verification)
  Future<bool> changePIN(String currentPIN, String newPIN) async {
    try {
      if (currentPIN.isEmpty || newPIN.isEmpty) return false;
      if (newPIN.length != 6) return false;
      if (!RegExp(r'^[0-9]{6}$').hasMatch(newPIN)) return false;

      final isVerified = await verifyPIN(currentPIN);
      if (!isVerified) return false;

      await _createHashedCredential(newPIN, _pinSaltKey, _pinHashKey, _pinIterationsKey);
      await _storage.write(key: _authMethodKey, value: 'pin');
      await _storage.write(key: _biometricsEnabledKey, value: 'false');
      await _clearBackupCredentials();
      await EncryptionService.instance.reWrapKey(newPIN);
      await EncryptionService.instance.removeBiometricKwk();

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Switch from PIN to password (requires current PIN verification)
  Future<bool> switchFromPINToPassword(
      String currentPIN, String newPassword) async {
    try {
      if (currentPIN.isEmpty || newPassword.length < minPasswordLength) return false;

      final isVerified = await verifyPIN(currentPIN);
      if (!isVerified) return false;

      await _createHashedCredential(newPassword, _passwordSaltKey, _passwordHashKey, _passwordIterationsKey);
      await _storage.write(key: _authMethodKey, value: 'password');
      await _storage.write(key: _biometricsEnabledKey, value: 'false');
      await _clearBackupCredentials();
      await EncryptionService.instance.reWrapKey(newPassword);
      await EncryptionService.instance.removeBiometricKwk();

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Switch from password to PIN (requires current password verification)
  Future<bool> switchFromPasswordToPIN(
      String currentPassword, String newPIN) async {
    try {
      if (currentPassword.isEmpty || newPIN.isEmpty) return false;
      if (newPIN.length != 6) return false;
      if (!RegExp(r'^[0-9]{6}$').hasMatch(newPIN)) return false;

      final isVerified = await verifyPassword(currentPassword);
      if (!isVerified) return false;

      await _createHashedCredential(newPIN, _pinSaltKey, _pinHashKey, _pinIterationsKey);
      await _storage.write(key: _authMethodKey, value: 'pin');
      await _storage.write(key: _biometricsEnabledKey, value: 'false');
      await _clearBackupCredentials();
      await EncryptionService.instance.reWrapKey(newPIN);
      await EncryptionService.instance.removeBiometricKwk();

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Reset all Authentication data (for testing or reset functionality)
  Future<bool> resetAuth() async {
    try {
      await _storage.delete(key: _passwordHashKey);
      await _storage.delete(key: _pinHashKey);
      await _storage.delete(key: _passwordSaltKey);
      await _storage.delete(key: _pinSaltKey);
      await _clearBackupCredentials();
      await _storage.delete(key: _hashVersionKey);
      await _storage.delete(key: _firstTimeKey);
      await _storage.delete(key: _biometricsEnabledKey);
      await _storage.delete(key: _authMethodKey);
      await resetUnlockAttempts();
      await EncryptionService.instance.removeBiometricKwk();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _clearBackupCredentials() async {
    await _storage.delete(key: _backupPasswordHashKey);
    await _storage.delete(key: _backupPinHashKey);
    await _storage.delete(key: _backupPasswordSaltKey);
    await _storage.delete(key: _backupPinSaltKey);
    await _storage.delete(key: _backupPasswordIterationsKey);
    await _storage.delete(key: _backupPinIterationsKey);
  }

  /// Get the current unlock protection state.
  Future<UnlockSecurityState> getUnlockSecurityState() async {
    final settings = await _vaultService.getSettings();
    return _loadUnlockSecurityState(settings);
  }

  /// Clear any failed unlock counters and cooldown state.
  Future<void> resetUnlockAttempts() async {
    await _storage.delete(key: _failedUnlockAttemptsKey);
    await _storage.delete(key: _totalFailedUnlockAttemptsKey);
    await _storage.delete(key: _unlockLockoutUntilKey);
  }

  /// Register a failed unlock attempt and return the updated state.
  Future<UnlockFailureResult> registerFailedUnlockAttempt() async {
    final settings = await _vaultService.getSettings();
    var state = await _loadUnlockSecurityState(settings);

    if (!settings.failedUnlockProtectionEnabled) {
      return UnlockFailureResult(state: state);
    }

    var failedAttempts = state.failedAttempts + 1;
    var totalFailedAttempts = settings.wipeVaultOnMaxFailedAttempts
        ? state.totalFailedAttempts + 1
        : 0;
    DateTime? lockoutUntil;
    var enteredLockout = false;
    var vaultWiped = false;

    if (settings.wipeVaultOnMaxFailedAttempts &&
        totalFailedAttempts >= settings.maxFailedAttemptsBeforeWipe) {
      await _vaultService.clearVault();
      await _decoyService.clearDecoyVault();
      failedAttempts = 0;
      totalFailedAttempts = 0;
      vaultWiped = true;
    }

    if (settings.maxFailedAttemptsBeforeLockout > 0 &&
        failedAttempts >= settings.maxFailedAttemptsBeforeLockout) {
      lockoutUntil = DateTime.now().add(
        Duration(seconds: settings.lockoutDurationSeconds),
      );
      failedAttempts = 0;
      enteredLockout = true;
    }

    await _persistUnlockSecurityState(
      failedAttempts: failedAttempts,
      totalFailedAttempts: totalFailedAttempts,
      lockoutUntil: lockoutUntil,
    );

    state = UnlockSecurityState(
      protectionEnabled: settings.failedUnlockProtectionEnabled,
      failedAttempts: failedAttempts,
      totalFailedAttempts: totalFailedAttempts,
      maxFailedAttemptsBeforeLockout: settings.maxFailedAttemptsBeforeLockout,
      lockoutDurationSeconds: settings.lockoutDurationSeconds,
      wipeVaultOnMaxFailedAttempts: settings.wipeVaultOnMaxFailedAttempts,
      maxFailedAttemptsBeforeWipe: settings.maxFailedAttemptsBeforeWipe,
      lockoutUntil: lockoutUntil,
    );

    return UnlockFailureResult(
      state: state,
      enteredLockout: enteredLockout,
      vaultWiped: vaultWiped,
    );
  }

  static const int _defaultKdfIterations = 600000;
  static const int _saltSize = 32;

  /// Minimum password length enforced at every entry point (setup, change).
  static const int minPasswordLength = 8;

  /// Classify a password's strength. Length is a hard floor; composition only
  /// informs the warning level (NIST 800-63B: length over forced composition).
  static PasswordStrength validatePasswordStrength(String password) {
    if (password.length < minPasswordLength) return PasswordStrength.tooShort;
    var classes = 0;
    if (RegExp(r'[a-z]').hasMatch(password)) classes++;
    if (RegExp(r'[A-Z]').hasMatch(password)) classes++;
    if (RegExp(r'[0-9]').hasMatch(password)) classes++;
    if (RegExp(r'[^a-zA-Z0-9]').hasMatch(password)) classes++;
    // A long passphrase is fine even with one class; only flag short+mono.
    if (password.length < 12 && classes < 2) return PasswordStrength.weak;
    return PasswordStrength.acceptable;
  }

  Future<int> _getCurrentKdfIterations() async {
    final settings = await _vaultService.getSettings();
    return settings.kdfIterations;
  }

  Uint8List _generateSalt() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(_saltSize, (_) => random.nextInt(256)),
    );
  }

  String _hashCredentialLegacy(String credential) {
    final bytes = utf8.encode(credential);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<String> _createHashedCredential(String credential, String saltKey, String hashKey, String iterationsKey) async {
    final salt = _generateSalt();
    final iterations = await _getCurrentKdfIterations();
    final hash = await computePbkdf2Hash(credential, salt, iterations: iterations);
    await _storage.write(key: saltKey, value: base64Encode(salt));
    await _storage.write(key: hashKey, value: hash);
    await _storage.write(key: iterationsKey, value: iterations.toString());
    return hash;
  }

  Future<bool> _verifyCredential(String credential, String hashKey, String saltKey, String iterationsKey) async {
    try {
      final state = await getUnlockSecurityState();
      if (state.isLockedOut) return false;

      final storedHash = await _storage.read(key: hashKey);
      final storedSalt = await _storage.read(key: saltKey);

      if (storedHash == null) return false;

      if (storedSalt == null) {
        final legacyHash = _hashCredentialLegacy(credential);
        // Pad the legacy path with dummy KDF work so verify time does not
        // reveal that this is a legacy (plain SHA-256) account.
        await computePbkdf2Hash(
            credential, _generateSalt(), iterations: _defaultKdfIterations);
        if (constantTimeEquals(legacyHash, storedHash)) {
          final salt = _generateSalt();
          final iterations = await _getCurrentKdfIterations();
          final newHash = await computePbkdf2Hash(credential, salt, iterations: iterations);
          await _storage.write(key: saltKey, value: base64Encode(salt));
          await _storage.write(key: hashKey, value: newHash);
          await _storage.write(key: iterationsKey, value: iterations.toString());
          return true;
        }
        return false;
      }

      final storedIterationsStr = await _storage.read(key: iterationsKey);
      final storedIterations = storedIterationsStr != null
          ? int.tryParse(storedIterationsStr) ?? _defaultKdfIterations
          : _defaultKdfIterations;

      final salt = base64Decode(storedSalt);
      final computedHash = await computePbkdf2Hash(credential, salt, iterations: storedIterations);
      if (!constantTimeEquals(computedHash, storedHash)) return false;

      final currentIterations = await _getCurrentKdfIterations();
      if (currentIterations != storedIterations) {
        final newHash = await computePbkdf2Hash(credential, salt, iterations: currentIterations);
        await _storage.write(key: hashKey, value: newHash);
        await _storage.write(key: iterationsKey, value: currentIterations.toString());
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<UnlockSecurityState> _loadUnlockSecurityState(
    VaultSettings settings,
  ) async {
    var failedAttempts = int.tryParse(
            await _storage.read(key: _failedUnlockAttemptsKey) ?? '') ??
        0;
    var totalFailedAttempts = int.tryParse(
          await _storage.read(key: _totalFailedUnlockAttemptsKey) ?? '',
        ) ??
        0;
    final lockoutMillis =
        int.tryParse(await _storage.read(key: _unlockLockoutUntilKey) ?? '');
    DateTime? lockoutUntil = lockoutMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(lockoutMillis);

    if (lockoutUntil != null && !lockoutUntil.isAfter(DateTime.now())) {
      lockoutUntil = null;
      failedAttempts = 0;
      await _persistUnlockSecurityState(
        failedAttempts: failedAttempts,
        totalFailedAttempts: totalFailedAttempts,
        lockoutUntil: null,
      );
    }

    if (!settings.failedUnlockProtectionEnabled &&
        (failedAttempts != 0 ||
            totalFailedAttempts != 0 ||
            lockoutUntil != null)) {
      failedAttempts = 0;
      totalFailedAttempts = 0;
      lockoutUntil = null;
      await resetUnlockAttempts();
    }

    if (!settings.wipeVaultOnMaxFailedAttempts && totalFailedAttempts != 0) {
      totalFailedAttempts = 0;
      await _persistUnlockSecurityState(
        failedAttempts: failedAttempts,
        totalFailedAttempts: 0,
        lockoutUntil: lockoutUntil,
      );
    }

    return UnlockSecurityState(
      protectionEnabled: settings.failedUnlockProtectionEnabled,
      failedAttempts: failedAttempts,
      totalFailedAttempts: totalFailedAttempts,
      maxFailedAttemptsBeforeLockout: settings.maxFailedAttemptsBeforeLockout,
      lockoutDurationSeconds: settings.lockoutDurationSeconds,
      wipeVaultOnMaxFailedAttempts: settings.wipeVaultOnMaxFailedAttempts,
      maxFailedAttemptsBeforeWipe: settings.maxFailedAttemptsBeforeWipe,
      lockoutUntil: lockoutUntil,
    );
  }

  Future<void> _persistUnlockSecurityState({
    required int failedAttempts,
    required int totalFailedAttempts,
    required DateTime? lockoutUntil,
  }) async {
    await _storage.write(
      key: _failedUnlockAttemptsKey,
      value: failedAttempts.toString(),
    );
    await _storage.write(
      key: _totalFailedUnlockAttemptsKey,
      value: totalFailedAttempts.toString(),
    );

    if (lockoutUntil == null) {
      await _storage.delete(key: _unlockLockoutUntilKey);
      return;
    }

    await _storage.write(
      key: _unlockLockoutUntilKey,
      value: lockoutUntil.millisecondsSinceEpoch.toString(),
    );
  }

  /// Get biometric type display name
  String getBiometricDisplayName(List<BiometricType> biometrics) {
    if (biometrics.contains(BiometricType.fingerprint)) {
      return 'Fingerprint';
    } else if (biometrics.contains(BiometricType.face)) {
      return 'Face ID';
    } else if (biometrics.contains(BiometricType.iris)) {
      return 'Iris';
    } else if (biometrics.contains(BiometricType.strong) ||
        biometrics.contains(BiometricType.weak)) {
      return 'Biometric';
    }
    return 'Biometric';
  }
}

enum BiometricAuthenticationStatus {
  success,
  failed,
  canceled,
  lockedOut,
  unavailable,
}

/// Strength classification for a candidate password.
enum PasswordStrength {
  tooShort,
  weak,
  acceptable;

  bool get isBlocking => this == tooShort;

  String get label {
    switch (this) {
      case PasswordStrength.tooShort:
        return 'Use at least $AuthService.minPasswordLength characters';
      case PasswordStrength.weak:
        return 'Weak — add length or a mix of letters, numbers, symbols';
      case PasswordStrength.acceptable:
        return 'Acceptable';
    }
  }
}

class BiometricAuthenticationResult {
  final BiometricAuthenticationStatus status;

  const BiometricAuthenticationResult({required this.status});

  bool get isSuccess => status == BiometricAuthenticationStatus.success;

  bool get shouldCountAsFailedUnlock =>
      status == BiometricAuthenticationStatus.failed ||
      status == BiometricAuthenticationStatus.lockedOut;
}

class UnlockSecurityState {
  final bool protectionEnabled;
  final int failedAttempts;
  final int totalFailedAttempts;
  final int maxFailedAttemptsBeforeLockout;
  final int lockoutDurationSeconds;
  final bool wipeVaultOnMaxFailedAttempts;
  final int maxFailedAttemptsBeforeWipe;
  final DateTime? lockoutUntil;

  const UnlockSecurityState({
    this.protectionEnabled = false,
    this.failedAttempts = 0,
    this.totalFailedAttempts = 0,
    this.maxFailedAttemptsBeforeLockout = 5,
    this.lockoutDurationSeconds = 30,
    this.wipeVaultOnMaxFailedAttempts = false,
    this.maxFailedAttemptsBeforeWipe = 12,
    this.lockoutUntil,
  });

  bool get isLockedOut => lockoutUntil?.isAfter(DateTime.now()) ?? false;

  Duration get remainingLockout {
    if (!isLockedOut || lockoutUntil == null) return Duration.zero;
    return lockoutUntil!.difference(DateTime.now());
  }

  int get attemptsRemainingBeforeLockout {
    if (!protectionEnabled || maxFailedAttemptsBeforeLockout <= 0) {
      return 0;
    }

    final remaining = maxFailedAttemptsBeforeLockout - failedAttempts;
    return remaining < 0 ? 0 : remaining;
  }

  int? get attemptsRemainingBeforeWipe {
    if (!protectionEnabled || !wipeVaultOnMaxFailedAttempts) {
      return null;
    }

    final remaining = maxFailedAttemptsBeforeWipe - totalFailedAttempts;
    return remaining < 0 ? 0 : remaining;
  }
}

class UnlockFailureResult {
  final UnlockSecurityState state;
  final bool enteredLockout;
  final bool vaultWiped;

  const UnlockFailureResult({
    required this.state,
    this.enteredLockout = false,
    this.vaultWiped = false,
  });
}
