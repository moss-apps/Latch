import 'dart:convert';

/// One entry in the remote manifest. Describes the synced state of a single
/// vault file. [contentHash] is the sha256-hex of the ciphertext blob (used to
/// derive its content-addressed name); null for tombstones that never uploaded.
///
/// v2 (S3) carries the full per-file metadata needed to *restore* a file on a
/// device that has never seen it — the lean v1 schema (`id`/`contentHash`/
/// `modifiedAt`/`deleted`) could push but not pull. All v2 fields are nullable
/// or defaulted so a v1 manifest (missing the new keys) still deserializes.
class ManifestEntry {
  final String id;
  final String? contentHash;
  final DateTime modifiedAt;
  final bool deleted;

  // Restore metadata (v2). Null/default on tombstones and v1 manifests.
  final String? originalName;
  final String? type; // VaultedFileType.name
  final String? mimeType;
  final int? fileSize;
  final DateTime? dateAdded;
  final DateTime? dateModified;
  final bool isEncrypted;
  final String? encryptionIv;
  final String? encryptionAlgorithm; // EncryptionAlgorithm.name
  final String? keyDerivationSalt;
  final int? kdfIterations;
  final List<String> tags;
  final bool isFavorite;
  final List<String> albumIds;
  final String? folderId;

  const ManifestEntry({
    required this.id,
    this.contentHash,
    required this.modifiedAt,
    this.deleted = false,
    this.originalName,
    this.type,
    this.mimeType,
    this.fileSize,
    this.dateAdded,
    this.dateModified,
    this.isEncrypted = false,
    this.encryptionIv,
    this.encryptionAlgorithm,
    this.keyDerivationSalt,
    this.kdfIterations,
    this.tags = const [],
    this.isFavorite = false,
    this.albumIds = const [],
    this.folderId,
  });

  ManifestEntry copyWith({
    String? id,
    String? contentHash,
    DateTime? modifiedAt,
    bool? deleted,
    String? originalName,
    String? type,
    String? mimeType,
    int? fileSize,
    DateTime? dateAdded,
    DateTime? dateModified,
    bool? isEncrypted,
    String? encryptionIv,
    String? encryptionAlgorithm,
    String? keyDerivationSalt,
    int? kdfIterations,
    List<String>? tags,
    bool? isFavorite,
    List<String>? albumIds,
    String? folderId,
  }) {
    return ManifestEntry(
      id: id ?? this.id,
      contentHash: contentHash ?? this.contentHash,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      deleted: deleted ?? this.deleted,
      originalName: originalName ?? this.originalName,
      type: type ?? this.type,
      mimeType: mimeType ?? this.mimeType,
      fileSize: fileSize ?? this.fileSize,
      dateAdded: dateAdded ?? this.dateAdded,
      dateModified: dateModified ?? this.dateModified,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      encryptionIv: encryptionIv ?? this.encryptionIv,
      encryptionAlgorithm: encryptionAlgorithm ?? this.encryptionAlgorithm,
      keyDerivationSalt: keyDerivationSalt ?? this.keyDerivationSalt,
      kdfIterations: kdfIterations ?? this.kdfIterations,
      tags: tags ?? List.from(this.tags),
      albumIds: albumIds ?? List.from(this.albumIds),
      isFavorite: isFavorite ?? this.isFavorite,
      folderId: folderId ?? this.folderId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'contentHash': contentHash,
        'modifiedAt': modifiedAt.toIso8601String(),
        'deleted': deleted,
        'originalName': originalName,
        'type': type,
        'mimeType': mimeType,
        'fileSize': fileSize,
        'dateAdded': dateAdded?.toIso8601String(),
        'dateModified': dateModified?.toIso8601String(),
        'isEncrypted': isEncrypted,
        'encryptionIv': encryptionIv,
        'encryptionAlgorithm': encryptionAlgorithm,
        'keyDerivationSalt': keyDerivationSalt,
        'kdfIterations': kdfIterations,
        'tags': tags,
        'isFavorite': isFavorite,
        'albumIds': albumIds,
        'folderId': folderId,
      };

  factory ManifestEntry.fromJson(Map<String, dynamic> json) {
    return ManifestEntry(
      id: json['id'] as String,
      contentHash: json['contentHash'] as String?,
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      deleted: json['deleted'] as bool? ?? false,
      originalName: json['originalName'] as String?,
      type: json['type'] as String?,
      mimeType: json['mimeType'] as String?,
      fileSize: (json['fileSize'] as num?)?.toInt(),
      dateAdded: json['dateAdded'] != null
          ? DateTime.parse(json['dateAdded'] as String)
          : null,
      dateModified: json['dateModified'] != null
          ? DateTime.parse(json['dateModified'] as String)
          : null,
      isEncrypted: json['isEncrypted'] as bool? ?? false,
      encryptionIv: json['encryptionIv'] as String?,
      encryptionAlgorithm: json['encryptionAlgorithm'] as String?,
      keyDerivationSalt: json['keyDerivationSalt'] as String?,
      kdfIterations: (json['kdfIterations'] as num?)?.toInt(),
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      isFavorite: json['isFavorite'] as bool? ?? false,
      albumIds: (json['albumIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      folderId: json['folderId'] as String?,
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
    this.version = 2,
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
      version: json['version'] as int? ?? 2,
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
