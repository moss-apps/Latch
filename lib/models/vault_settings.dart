import 'encryption_algorithm.dart';
import 'album.dart';

/// Vault settings
class VaultSettings {
  final bool encryptionEnabled;
  final EncryptionAlgorithm encryptionAlgorithm;
  final int kdfIterations;
  final bool secureDelete;
  final bool screenshotProtectionEnabled;
  final int autoKillDelaySeconds;
  final SortOption defaultSort;
  final bool showHiddenFiles;
  final bool autoBackup;
  final int? maxStorageMB;
  final bool decoyModeEnabled;
  final String? decoyPin;
  final bool compressionEnabled;
  final bool failedUnlockProtectionEnabled;
  final int maxFailedAttemptsBeforeLockout;
  final int lockoutDurationSeconds;
  final bool wipeVaultOnMaxFailedAttempts;
  final int maxFailedAttemptsBeforeWipe;
  final bool showPermissionWarning;

  // Encrypted-at-rest sync (see docs/local_server_sync.md)
  final bool syncEnabled;
  final String? syncProfileId;

  /// PocketBase local store preferred over the legacy JSON index when the
  /// sidecar is available (docs/embedded_pocketbase.md P4).
  final bool pbEnabled;

  const VaultSettings({
    this.encryptionEnabled = false,
    this.encryptionAlgorithm = EncryptionAlgorithm.aes256Gcm,
    this.kdfIterations = 600000,
    this.secureDelete = true,
    this.screenshotProtectionEnabled = false,
    this.autoKillDelaySeconds = 0,
    this.defaultSort = SortOption.dateAddedNewest,
    this.showHiddenFiles = false,
    this.autoBackup = false,
    this.maxStorageMB,
    this.decoyModeEnabled = false,
    this.decoyPin,
    this.compressionEnabled = false,
    this.failedUnlockProtectionEnabled = true,
    this.maxFailedAttemptsBeforeLockout = 5,
    this.lockoutDurationSeconds = 30,
    this.wipeVaultOnMaxFailedAttempts = false,
    this.maxFailedAttemptsBeforeWipe = 12,
    this.showPermissionWarning = true,
    this.syncEnabled = false,
    this.syncProfileId,
    this.pbEnabled = true,
  });

  VaultSettings copyWith({
    bool? encryptionEnabled,
    EncryptionAlgorithm? encryptionAlgorithm,
    int? kdfIterations,
    bool? secureDelete,
    bool? screenshotProtectionEnabled,
    int? autoKillDelaySeconds,
    SortOption? defaultSort,
    bool? showHiddenFiles,
    bool? autoBackup,
    int? maxStorageMB,
    bool? decoyModeEnabled,
    String? decoyPin,
    bool? compressionEnabled,
    bool? failedUnlockProtectionEnabled,
    int? maxFailedAttemptsBeforeLockout,
    int? lockoutDurationSeconds,
    bool? wipeVaultOnMaxFailedAttempts,
    int? maxFailedAttemptsBeforeWipe,
    bool? showPermissionWarning,
    bool? syncEnabled,
    String? syncProfileId,
    bool? pbEnabled,
  }) {
    return VaultSettings(
      encryptionEnabled: encryptionEnabled ?? this.encryptionEnabled,
      encryptionAlgorithm: encryptionAlgorithm ?? this.encryptionAlgorithm,
      kdfIterations: kdfIterations ?? this.kdfIterations,
      secureDelete: secureDelete ?? this.secureDelete,
      screenshotProtectionEnabled:
          screenshotProtectionEnabled ?? this.screenshotProtectionEnabled,
      autoKillDelaySeconds: autoKillDelaySeconds ?? this.autoKillDelaySeconds,
      defaultSort: defaultSort ?? this.defaultSort,
      showHiddenFiles: showHiddenFiles ?? this.showHiddenFiles,
      autoBackup: autoBackup ?? this.autoBackup,
      maxStorageMB: maxStorageMB ?? this.maxStorageMB,
      decoyModeEnabled: decoyModeEnabled ?? this.decoyModeEnabled,
      decoyPin: decoyPin ?? this.decoyPin,
      compressionEnabled: compressionEnabled ?? this.compressionEnabled,
      failedUnlockProtectionEnabled:
          failedUnlockProtectionEnabled ?? this.failedUnlockProtectionEnabled,
      maxFailedAttemptsBeforeLockout:
          maxFailedAttemptsBeforeLockout ?? this.maxFailedAttemptsBeforeLockout,
      lockoutDurationSeconds:
          lockoutDurationSeconds ?? this.lockoutDurationSeconds,
      wipeVaultOnMaxFailedAttempts:
          wipeVaultOnMaxFailedAttempts ?? this.wipeVaultOnMaxFailedAttempts,
      maxFailedAttemptsBeforeWipe:
          maxFailedAttemptsBeforeWipe ?? this.maxFailedAttemptsBeforeWipe,
      showPermissionWarning:
          showPermissionWarning ?? this.showPermissionWarning,
      syncEnabled: syncEnabled ?? this.syncEnabled,
      syncProfileId: syncProfileId ?? this.syncProfileId,
      pbEnabled: pbEnabled ?? this.pbEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'encryptionEnabled': encryptionEnabled,
        'encryptionAlgorithm': encryptionAlgorithm.name,
        'kdfIterations': kdfIterations,
        'secureDelete': secureDelete,
        'screenshotProtectionEnabled': screenshotProtectionEnabled,
        'autoKillDelaySeconds': autoKillDelaySeconds,
        'defaultSort': defaultSort.name,
        'showHiddenFiles': showHiddenFiles,
        'autoBackup': autoBackup,
        'maxStorageMB': maxStorageMB,
        'decoyModeEnabled': decoyModeEnabled,
        'decoyPin': decoyPin,
        'compressionEnabled': compressionEnabled,
        'failedUnlockProtectionEnabled': failedUnlockProtectionEnabled,
        'maxFailedAttemptsBeforeLockout': maxFailedAttemptsBeforeLockout,
        'lockoutDurationSeconds': lockoutDurationSeconds,
        'wipeVaultOnMaxFailedAttempts': wipeVaultOnMaxFailedAttempts,
        'maxFailedAttemptsBeforeWipe': maxFailedAttemptsBeforeWipe,
        'showPermissionWarning': showPermissionWarning,
        'syncEnabled': syncEnabled,
        'syncProfileId': syncProfileId,
        'pbEnabled': pbEnabled,
      };

  factory VaultSettings.fromJson(Map<String, dynamic> json) {
    return VaultSettings(
      encryptionEnabled: json['encryptionEnabled'] as bool? ?? false,
      encryptionAlgorithm: EncryptionAlgorithm.values.firstWhere(
        (a) => a.name == (json['encryptionAlgorithm'] as String? ?? 'aes256Gcm'),
        orElse: () => EncryptionAlgorithm.aes256Gcm,
      ),
      kdfIterations: json['kdfIterations'] as int? ?? 600000,
      secureDelete: json['secureDelete'] as bool? ?? true,
      screenshotProtectionEnabled:
          json['screenshotProtectionEnabled'] as bool? ?? false,
      autoKillDelaySeconds: json['autoKillDelaySeconds'] as int? ?? 0,
      defaultSort: SortOption.values.firstWhere(
        (s) => s.name == (json['defaultSort'] as String? ?? 'dateAddedNewest'),
        orElse: () => SortOption.dateAddedNewest,
      ),
      showHiddenFiles: json['showHiddenFiles'] as bool? ?? false,
      autoBackup: json['autoBackup'] as bool? ?? false,
      maxStorageMB: json['maxStorageMB'] as int?,
      decoyModeEnabled: json['decoyModeEnabled'] as bool? ?? false,
      decoyPin: json['decoyPin'] as String?,
      compressionEnabled: json['compressionEnabled'] as bool? ?? false,
      failedUnlockProtectionEnabled:
          json['failedUnlockProtectionEnabled'] as bool? ?? true,
      maxFailedAttemptsBeforeLockout:
          json['maxFailedAttemptsBeforeLockout'] as int? ?? 5,
      lockoutDurationSeconds: json['lockoutDurationSeconds'] as int? ?? 30,
      wipeVaultOnMaxFailedAttempts:
          json['wipeVaultOnMaxFailedAttempts'] as bool? ?? false,
      maxFailedAttemptsBeforeWipe:
          json['maxFailedAttemptsBeforeWipe'] as int? ?? 12,
      showPermissionWarning:
          json['showPermissionWarning'] as bool? ?? true,
      syncEnabled: json['syncEnabled'] as bool? ?? false,
      syncProfileId: json['syncProfileId'] as String?,
      pbEnabled: json['pbEnabled'] as bool? ?? true,
    );
  }
}
