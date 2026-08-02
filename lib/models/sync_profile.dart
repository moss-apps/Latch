import 'dart:convert';

/// Sync direction for a profile.
enum SyncDirection {
  pushOnly,
  twoWay;

  static SyncDirection fromName(String? name) =>
      SyncDirection.values.firstWhere(
        (d) => d.name == name,
        orElse: () => SyncDirection.pushOnly,
      );
}

/// Connection profile for a remote sync target. The server password is NOT
/// stored here — it lives in flutter_secure_storage under [passwordStorageKey],
/// keyed by profile id, so this model stays safe to persist alongside settings.
class SyncProfile {
  final String id;
  final String serverUrl;
  final String? username;
  final String basePath;
  final SyncDirection direction;
  final bool wifiOnly;
  final bool enabled;
  final DateTime? lastSyncedAt;

  /// Secure-storage key for this profile's password.
  String get passwordStorageKey => passwordStorageKeyFor(id);

  /// Secure-storage key for a profile's password by profile id.
  static String passwordStorageKeyFor(String id) => 'sync_profile_pw_$id';

  const SyncProfile({
    required this.id,
    required this.serverUrl,
    this.username,
    this.basePath = '/locker',
    this.direction = SyncDirection.pushOnly,
    this.wifiOnly = true,
    this.enabled = true,
    this.lastSyncedAt,
  });

  SyncProfile copyWith({
    String? id,
    String? serverUrl,
    String? username,
    String? basePath,
    SyncDirection? direction,
    bool? wifiOnly,
    bool? enabled,
    DateTime? lastSyncedAt,
  }) {
    return SyncProfile(
      id: id ?? this.id,
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      basePath: basePath ?? this.basePath,
      direction: direction ?? this.direction,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      enabled: enabled ?? this.enabled,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'serverUrl': serverUrl,
        'username': username,
        'basePath': basePath,
        'direction': direction.name,
        'wifiOnly': wifiOnly,
        'enabled': enabled,
        'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      };

  factory SyncProfile.fromJson(Map<String, dynamic> json) {
    return SyncProfile(
      id: json['id'] as String,
      serverUrl: json['serverUrl'] as String,
      username: json['username'] as String?,
      basePath: json['basePath'] as String? ?? '/locker',
      direction: SyncDirection.fromName(json['direction'] as String?),
      wifiOnly: json['wifiOnly'] as bool? ?? true,
      enabled: json['enabled'] as bool? ?? true,
      lastSyncedAt: json['lastSyncedAt'] != null
          ? DateTime.parse(json['lastSyncedAt'] as String)
          : null,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory SyncProfile.fromJsonString(String jsonString) =>
      SyncProfile.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
}
