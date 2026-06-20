import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/pbkdf2_isolate.dart';
import '../utils/secure_compare.dart';
import '../models/vaulted_file.dart';
import 'encryption_service.dart';
import 'vault_service.dart';

/// Service for managing decoy mode functionality
/// Decoy mode shows a fake set of files if someone forces access
class DecoyService {
  DecoyService._();
  static final DecoyService instance = DecoyService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device),
  );

  static const String _decoyEnabledKey = 'decoy_mode_enabled';
  static const String _decoyPinKey = 'decoy_pin_hash';
  static const String _decoyPasswordKey = 'decoy_password_hash';
  static const String _decoyPinSaltKey = 'decoy_pin_salt';
  static const String _decoyPasswordSaltKey = 'decoy_password_salt';
  static const String _decoyPinIterationsKey = 'decoy_pin_iterations';
  static const String _decoyPasswordIterationsKey = 'decoy_password_iterations';
  static const String _lastAccessModeKey = 'last_access_mode';
  static const String _decoySettingsKey = 'decoy_settings';

  final VaultService _vaultService = VaultService.instance;

  bool _isDecoyModeActive = false;
  DecoySettings? _cachedSettings;

  /// Check if decoy mode is currently active
  bool get isDecoyModeActive => _isDecoyModeActive;

  /// Initialize decoy service
  Future<void> initialize() async {
    await _loadSettings();
  }

  /// Load decoy settings
  Future<DecoySettings> _loadSettings() async {
    if (_cachedSettings != null) return _cachedSettings!;

    try {
      final settingsJson = await _storage.read(key: _decoySettingsKey);
      if (settingsJson == null || settingsJson.isEmpty) {
        _cachedSettings = const DecoySettings();
        return _cachedSettings!;
      }

      _cachedSettings = DecoySettings.fromJson(
        jsonDecode(settingsJson) as Map<String, dynamic>,
      );
      return _cachedSettings!;
    } catch (e) {
      debugPrint('Error loading decoy settings: $e');
      _cachedSettings = const DecoySettings();
      return _cachedSettings!;
    }
  }

  /// Save decoy settings
  Future<void> _saveSettings() async {
    try {
      await _storage.write(
        key: _decoySettingsKey,
        value: jsonEncode(_cachedSettings?.toJson() ?? {}),
      );
    } catch (e) {
      debugPrint('Error saving decoy settings: $e');
    }
  }

  /// Check if decoy mode is enabled
  Future<bool> isDecoyModeEnabled() async {
    try {
      final enabled = await _storage.read(key: _decoyEnabledKey);
      return enabled == 'true';
    } catch (e) {
      return false;
    }
  }

  /// Enable decoy mode
  Future<bool> enableDecoyMode() async {
    try {
      await _storage.write(key: _decoyEnabledKey, value: 'true');
      _cachedSettings = (_cachedSettings ?? const DecoySettings()).copyWith(
        isEnabled: true,
      );
      await _saveSettings();
      return true;
    } catch (e) {
      debugPrint('Error enabling decoy mode: $e');
      return false;
    }
  }

  /// Disable decoy mode
  Future<bool> disableDecoyMode() async {
    try {
      await _storage.write(key: _decoyEnabledKey, value: 'false');
      _cachedSettings = (_cachedSettings ?? const DecoySettings()).copyWith(
        isEnabled: false,
      );
      await _saveSettings();
      return true;
    } catch (e) {
      debugPrint('Error disabling decoy mode: $e');
      return false;
    }
  }

  /// Set decoy PIN (6 digits, matching main PIN requirement)
  Future<bool> setDecoyPin(String pin) async {
    try {
      if (pin.isEmpty || pin.length != 6) return false;
      if (!RegExp(r'^[0-9]{6}$').hasMatch(pin)) return false;

      await _createHashedCredential(pin, _decoyPinSaltKey, _decoyPinKey, _decoyPinIterationsKey);
      EncryptionService.instance.setPendingCredential(pin, isDecoy: true);

      _cachedSettings = (_cachedSettings ?? const DecoySettings()).copyWith(
        hasPinSet: true,
      );
      await _saveSettings();

      return true;
    } catch (e) {
      debugPrint('Error setting decoy PIN: $e');
      return false;
    }
  }

  /// Set decoy password
  Future<bool> setDecoyPassword(String password) async {
    try {
      if (password.isEmpty) return false;

      await _createHashedCredential(password, _decoyPasswordSaltKey, _decoyPasswordKey, _decoyPasswordIterationsKey);
      EncryptionService.instance.setPendingCredential(password, isDecoy: true);

      _cachedSettings = (_cachedSettings ?? const DecoySettings()).copyWith(
        hasPasswordSet: true,
      );
      await _saveSettings();

      return true;
    } catch (e) {
      debugPrint('Error setting decoy password: $e');
      return false;
    }
  }

  /// Verify decoy PIN
  Future<bool> verifyDecoyPin(String pin) async {
    final result = await _verifyCredential(pin, _decoyPinKey, _decoyPinSaltKey, _decoyPinIterationsKey);
    if (result) EncryptionService.instance.setPendingCredential(pin, isDecoy: true);
    return result;
  }

  /// Verify decoy password
  Future<bool> verifyDecoyPassword(String password) async {
    final result = await _verifyCredential(password, _decoyPasswordKey, _decoyPasswordSaltKey, _decoyPasswordIterationsKey);
    if (result) EncryptionService.instance.setPendingCredential(password, isDecoy: true);
    return result;
  }

  /// Check if input is decoy credential
  Future<DecoyCheckResult> checkIfDecoyCredential(String credential) async {
    final isEnabled = await isDecoyModeEnabled();
    if (!isEnabled) {
      return DecoyCheckResult(isDecoy: false);
    }

    // Check if it matches decoy PIN
    if (await verifyDecoyPin(credential)) {
      return DecoyCheckResult(
          isDecoy: true, credentialType: CredentialType.pin);
    }

    // Check if it matches decoy password
    if (await verifyDecoyPassword(credential)) {
      return DecoyCheckResult(
        isDecoy: true,
        credentialType: CredentialType.password,
      );
    }

    return DecoyCheckResult(isDecoy: false);
  }

  /// Activate decoy mode (show fake files)
  Future<void> activateDecoyMode() async {
    _isDecoyModeActive = true;
    await _storage.write(key: _lastAccessModeKey, value: 'decoy');
  }

  /// Deactivate decoy mode (show real files)
  Future<void> deactivateDecoyMode() async {
    _isDecoyModeActive = false;
    await _storage.write(key: _lastAccessModeKey, value: 'real');
  }

  /// Get files based on current mode
  Future<List<VaultedFile>> getFilesForCurrentMode() async {
    return await _vaultService.getAllFiles(isDecoy: _isDecoyModeActive);
  }

  /// Add file to current mode's vault
  Future<VaultedFile?> addFileToCurrentMode({
    required String sourcePath,
    required String originalName,
    required VaultedFileType type,
    required String mimeType,
    bool deleteOriginal = false,
    bool encrypt = true,
  }) async {
    return await _vaultService.addFile(
      sourcePath: sourcePath,
      originalName: originalName,
      type: type,
      mimeType: mimeType,
      deleteOriginal: deleteOriginal,
      encrypt: encrypt,
      isDecoy: _isDecoyModeActive,
    );
  }

  /// Get decoy settings
  Future<DecoySettings> getSettings() async {
    return await _loadSettings();
  }

  /// Update decoy settings
  Future<void> updateSettings(DecoySettings settings) async {
    _cachedSettings = settings;
    await _saveSettings();
  }

  static const int _defaultKdfIterations = 600000;

  Future<int> _getCurrentKdfIterations() async {
    final settings = await _vaultService.getSettings();
    return settings.kdfIterations;
  }

  Uint8List _generateSalt() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
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

  /// Check if decoy PIN is set
  Future<bool> hasDecoyPinSet() async {
    try {
      final pin = await _storage.read(key: _decoyPinKey);
      return pin != null && pin.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Check if decoy password is set
  Future<bool> hasDecoyPasswordSet() async {
    try {
      final password = await _storage.read(key: _decoyPasswordKey);
      return password != null && password.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Clear decoy vault
  Future<void> clearDecoyVault() async {
    await _vaultService.clearVault(isDecoy: true);
  }

  /// Remove decoy credentials
  Future<void> removeDecoyCredentials() async {
    try {
      await _storage.delete(key: _decoyPinKey);
      await _storage.delete(key: _decoyPasswordKey);
      await _storage.delete(key: _decoyPinSaltKey);
      await _storage.delete(key: _decoyPasswordSaltKey);
      await _storage.delete(key: _decoyPinIterationsKey);
      await _storage.delete(key: _decoyPasswordIterationsKey);
      await _storage.delete(key: 'vault_decoy_key_version');
      await _storage.delete(key: 'vault_decoy_key_wrapped');
      await _storage.delete(key: 'vault_decoy_kwk_salt');
      await _storage.delete(key: 'vault_decoy_kwk_iv');
      await _storage.delete(key: 'vault_decoy_key');
      _cachedSettings = (_cachedSettings ?? const DecoySettings()).copyWith(
        hasPinSet: false,
        hasPasswordSet: false,
      );
      await _saveSettings();
    } catch (e) {
      debugPrint('Error removing decoy credentials: $e');
    }
  }

  /// Get panic action behavior
  PanicAction get panicAction =>
      _cachedSettings?.panicAction ?? PanicAction.showDecoy;

  /// Set panic action
  Future<void> setPanicAction(PanicAction action) async {
    _cachedSettings = (_cachedSettings ?? const DecoySettings()).copyWith(
      panicAction: action,
    );
    await _saveSettings();
  }
}

/// Result of checking if credential is for decoy mode
class DecoyCheckResult {
  final bool isDecoy;
  final CredentialType? credentialType;

  const DecoyCheckResult({
    required this.isDecoy,
    this.credentialType,
  });
}

/// Type of credential
enum CredentialType {
  pin,
  password,
  biometric,
}

/// Decoy mode settings
class DecoySettings {
  final bool isEnabled;
  final bool hasPinSet;
  final bool hasPasswordSet;
  final PanicAction panicAction;
  final bool showFakeNotification;
  final String? customDecoyName; // Custom app name to show

  const DecoySettings({
    this.isEnabled = false,
    this.hasPinSet = false,
    this.hasPasswordSet = false,
    this.panicAction = PanicAction.showDecoy,
    this.showFakeNotification = false,
    this.customDecoyName,
  });

  DecoySettings copyWith({
    bool? isEnabled,
    bool? hasPinSet,
    bool? hasPasswordSet,
    PanicAction? panicAction,
    bool? showFakeNotification,
    String? customDecoyName,
  }) {
    return DecoySettings(
      isEnabled: isEnabled ?? this.isEnabled,
      hasPinSet: hasPinSet ?? this.hasPinSet,
      hasPasswordSet: hasPasswordSet ?? this.hasPasswordSet,
      panicAction: panicAction ?? this.panicAction,
      showFakeNotification: showFakeNotification ?? this.showFakeNotification,
      customDecoyName: customDecoyName ?? this.customDecoyName,
    );
  }

  Map<String, dynamic> toJson() => {
        'isEnabled': isEnabled,
        'hasPinSet': hasPinSet,
        'hasPasswordSet': hasPasswordSet,
        'panicAction': panicAction.name,
        'showFakeNotification': showFakeNotification,
        'customDecoyName': customDecoyName,
      };

  factory DecoySettings.fromJson(Map<String, dynamic> json) {
    return DecoySettings(
      isEnabled: json['isEnabled'] as bool? ?? false,
      hasPinSet: json['hasPinSet'] as bool? ?? false,
      hasPasswordSet: json['hasPasswordSet'] as bool? ?? false,
      panicAction: PanicAction.values.firstWhere(
        (p) => p.name == (json['panicAction'] as String? ?? 'showDecoy'),
        orElse: () => PanicAction.showDecoy,
      ),
      showFakeNotification: json['showFakeNotification'] as bool? ?? false,
      customDecoyName: json['customDecoyName'] as String?,
    );
  }
}

/// Actions to take when panic/decoy mode is triggered
enum PanicAction {
  showDecoy, // Show decoy files
  showEmpty, // Show empty vault
  showCalculator, // Show calculator disguise
  lockOut, // Lock out completely
  clearRealVault; // Delete real vault (dangerous!)

  String get displayName {
    switch (this) {
      case PanicAction.showDecoy:
        return 'Show Decoy Files';
      case PanicAction.showEmpty:
        return 'Show Empty Vault';
      case PanicAction.showCalculator:
        return 'Show Calculator';
      case PanicAction.lockOut:
        return 'Lock Out';
      case PanicAction.clearRealVault:
        return 'Clear Real Vault (Dangerous!)';
    }
  }

  String get description {
    switch (this) {
      case PanicAction.showDecoy:
        return 'Shows a set of fake files you\'ve prepared';
      case PanicAction.showEmpty:
        return 'Shows an empty vault with no files';
      case PanicAction.showCalculator:
        return 'Disguises the app as a calculator';
      case PanicAction.lockOut:
        return 'Prevents any access for a set period';
      case PanicAction.clearRealVault:
        return 'Permanently deletes all real files (cannot be undone!)';
    }
  }
}
