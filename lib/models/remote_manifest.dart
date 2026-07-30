import 'dart:convert';

/// One entry in the remote manifest. Describes the synced state of a single
/// vault file. [contentHash] is the sha256-hex of the ciphertext blob (used to
/// derive its content-addressed name); null for tombstones that never uploaded.
class ManifestEntry {
  final String id;
  final String? contentHash;
  final DateTime modifiedAt;
  final bool deleted;

  const ManifestEntry({
    required this.id,
    this.contentHash,
    required this.modifiedAt,
    this.deleted = false,
  });

  ManifestEntry copyWith({
    String? id,
    String? contentHash,
    DateTime? modifiedAt,
    bool? deleted,
  }) {
    return ManifestEntry(
      id: id ?? this.id,
      contentHash: contentHash ?? this.contentHash,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      deleted: deleted ?? this.deleted,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'contentHash': contentHash,
        'modifiedAt': modifiedAt.toIso8601String(),
        'deleted': deleted,
      };

  factory ManifestEntry.fromJson(Map<String, dynamic> json) {
    return ManifestEntry(
      id: json['id'] as String,
      contentHash: json['contentHash'] as String?,
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      deleted: json['deleted'] as bool? ?? false,
    );
  }
}

/// The encrypted-at-rest manifest. Serialized to JSON, then GCM-encrypted with
/// the vault master key before it ever touches the server. The server only ever
/// sees opaque bytes (see SyncService.encryptManifest).
class RemoteManifest {
  final int version;
  final String deviceId;
  final DateTime generatedAt;
  final List<ManifestEntry> entries;

  const RemoteManifest({
    this.version = 1,
    required this.deviceId,
    required this.generatedAt,
    this.entries = const [],
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'deviceId': deviceId,
        'generatedAt': generatedAt.toIso8601String(),
        'entries': entries.map((e) => e.toJson()).toList(),
      };

  factory RemoteManifest.fromJson(Map<String, dynamic> json) {
    return RemoteManifest(
      version: json['version'] as int? ?? 1,
      deviceId: json['deviceId'] as String,
      generatedAt: DateTime.parse(json['generatedAt'] as String),
      entries: (json['entries'] as List<dynamic>?)
              ?.map((e) => ManifestEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory RemoteManifest.fromJsonString(String jsonString) =>
      RemoteManifest.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
}
