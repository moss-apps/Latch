import 'dart:convert';

/// Enum representing the type of file stored in the vault
enum VaultedFileType {
  image,
  video,
  song,
  document,
  other;

  String get displayName {
    switch (this) {
      case VaultedFileType.image:
        return 'Image';
      case VaultedFileType.video:
        return 'Video';
      case VaultedFileType.song:
        return 'Song';
      case VaultedFileType.document:
        return 'Document';
      case VaultedFileType.other:
        return 'Other';
    }
  }

  String get icon {
    switch (this) {
      case VaultedFileType.image:
        return 'picture_icon.png';
      case VaultedFileType.video:
        return 'video_icon.png';
      case VaultedFileType.song:
      case VaultedFileType.document:
      case VaultedFileType.other:
        return 'otherfiles_icon.png';
    }
  }

  static VaultedFileType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'image':
        return VaultedFileType.image;
      case 'video':
        return VaultedFileType.video;
      case 'song':
      case 'audio':
        return VaultedFileType.song;
      case 'document':
        return VaultedFileType.document;
      default:
        return VaultedFileType.other;
    }
  }
}

/// Model representing a file stored in the vault
class VaultedFile {
  final String id;
  final String originalName;
  final String vaultPath;
  final String? originalPath;
  final VaultedFileType type;
  final String mimeType;
  final int fileSize;
  final DateTime dateAdded;
  final DateTime? dateModified;
  final String? thumbnailPath;
  final Map<String, dynamic>? metadata;

  // New fields for organization
  final List<String> tags;
  final bool isFavorite;
  final bool isEncrypted;
  final String? encryptionIv; // Initialization vector for AES encryption
  final bool isDecoy; // Flag for decoy mode files
  final DateTime? lastViewed;
  final int viewCount;
  final String? notes;
  final List<String> albumIds; // Albums this file belongs to
  final String? folderId; // Folder this file belongs to

  const VaultedFile({
    required this.id,
    required this.originalName,
    required this.vaultPath,
    this.originalPath,
    required this.type,
    required this.mimeType,
    required this.fileSize,
    required this.dateAdded,
    this.dateModified,
    this.thumbnailPath,
    this.metadata,
    this.tags = const [],
    this.isFavorite = false,
    this.isEncrypted = false,
    this.encryptionIv,
    this.isDecoy = false,
    this.lastViewed,
    this.viewCount = 0,
    this.notes,
    this.albumIds = const [],
    this.folderId,
  });

  /// Create a copy with updated fields
  VaultedFile copyWith({
    String? id,
    String? originalName,
    String? vaultPath,
    String? originalPath,
    VaultedFileType? type,
    String? mimeType,
    int? fileSize,
    DateTime? dateAdded,
    DateTime? dateModified,
    String? thumbnailPath,
    Map<String, dynamic>? metadata,
    List<String>? tags,
    bool? isFavorite,
    bool? isEncrypted,
    String? encryptionIv,
    bool? isDecoy,
    DateTime? lastViewed,
    int? viewCount,
    String? notes,
    List<String>? albumIds,
    String? folderId,
  }) {
    return VaultedFile(
      id: id ?? this.id,
      originalName: originalName ?? this.originalName,
      vaultPath: vaultPath ?? this.vaultPath,
      originalPath: originalPath ?? this.originalPath,
      type: type ?? this.type,
      mimeType: mimeType ?? this.mimeType,
      fileSize: fileSize ?? this.fileSize,
      dateAdded: dateAdded ?? this.dateAdded,
      dateModified: dateModified ?? this.dateModified,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      metadata: metadata ?? this.metadata,
      tags: tags ?? List.from(this.tags),
      isFavorite: isFavorite ?? this.isFavorite,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      encryptionIv: encryptionIv ?? this.encryptionIv,
      isDecoy: isDecoy ?? this.isDecoy,
      lastViewed: lastViewed ?? this.lastViewed,
      viewCount: viewCount ?? this.viewCount,
      notes: notes ?? this.notes,
      albumIds: albumIds ?? List.from(this.albumIds),
      folderId: folderId ?? this.folderId,
    );
  }

  /// Add a tag
  VaultedFile addTag(String tag) {
    if (tags.contains(tag.toLowerCase().trim())) return this;
    return copyWith(
      tags: [...tags, tag.toLowerCase().trim()],
      dateModified: DateTime.now(),
    );
  }

  /// Add multiple tags
  VaultedFile addTags(List<String> newTags) {
    final normalizedTags =
        newTags.map((t) => t.toLowerCase().trim()).toSet().toList();
    final tagsToAdd =
        normalizedTags.where((t) => !tags.contains(t) && t.isNotEmpty).toList();
    if (tagsToAdd.isEmpty) return this;
    return copyWith(
      tags: [...tags, ...tagsToAdd],
      dateModified: DateTime.now(),
    );
  }

  /// Remove a tag
  VaultedFile removeTag(String tag) {
    final normalizedTag = tag.toLowerCase().trim();
    if (!tags.contains(normalizedTag)) return this;
    return copyWith(
      tags: tags.where((t) => t != normalizedTag).toList(),
      dateModified: DateTime.now(),
    );
  }

  /// Toggle favorite status
  VaultedFile toggleFavorite() {
    return copyWith(
      isFavorite: !isFavorite,
      dateModified: DateTime.now(),
    );
  }

  /// Mark as viewed
  VaultedFile markViewed() {
    return copyWith(
      lastViewed: DateTime.now(),
      viewCount: viewCount + 1,
    );
  }

  /// Add to album
  VaultedFile addToAlbum(String albumId) {
    if (albumIds.contains(albumId)) return this;
    return copyWith(
      albumIds: [...albumIds, albumId],
      dateModified: DateTime.now(),
    );
  }

  /// Remove from album
  VaultedFile removeFromAlbum(String albumId) {
    if (!albumIds.contains(albumId)) return this;
    return copyWith(
      albumIds: albumIds.where((id) => id != albumId).toList(),
      dateModified: DateTime.now(),
    );
  }

  /// Add to folder
  VaultedFile addToFolder(String folderId) {
    return copyWith(
      folderId: folderId,
      dateModified: DateTime.now(),
    );
  }

  /// Remove from folder
  VaultedFile removeFromFolder() {
    return copyWith(
      folderId: null,
      dateModified: DateTime.now(),
    );
  }

  /// Check if file has a specific tag
  bool hasTag(String tag) => tags.contains(tag.toLowerCase().trim());

  /// Check if file is in a specific album
  bool isInAlbum(String albumId) => albumIds.contains(albumId);

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'originalName': originalName,
      'vaultPath': vaultPath,
      'originalPath': originalPath,
      'type': type.name,
      'mimeType': mimeType,
      'fileSize': fileSize,
      'dateAdded': dateAdded.toIso8601String(),
      'dateModified': dateModified?.toIso8601String(),
      'thumbnailPath': thumbnailPath,
      'metadata': metadata,
      'tags': tags,
      'isFavorite': isFavorite,
      'isEncrypted': isEncrypted,
      'encryptionIv': encryptionIv,
      'isDecoy': isDecoy,
      'lastViewed': lastViewed?.toIso8601String(),
      'viewCount': viewCount,
      'notes': notes,
      'albumIds': albumIds,
      'folderId': folderId,
    };
  }

  /// Create from JSON map
  factory VaultedFile.fromJson(Map<String, dynamic> json) {
    return VaultedFile(
      id: json['id'] as String,
      originalName: json['originalName'] as String,
      vaultPath: json['vaultPath'] as String,
      originalPath: json['originalPath'] as String?,
      type: VaultedFileType.fromString(json['type'] as String),
      mimeType: json['mimeType'] as String,
      fileSize: json['fileSize'] as int,
      dateAdded: DateTime.parse(json['dateAdded'] as String),
      dateModified: json['dateModified'] != null
          ? DateTime.parse(json['dateModified'] as String)
          : null,
      thumbnailPath: json['thumbnailPath'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              [],
      isFavorite: json['isFavorite'] as bool? ?? false,
      isEncrypted: json['isEncrypted'] as bool? ?? false,
      encryptionIv: json['encryptionIv'] as String?,
      isDecoy: json['isDecoy'] as bool? ?? false,
      lastViewed: json['lastViewed'] != null
          ? DateTime.parse(json['lastViewed'] as String)
          : null,
      viewCount: json['viewCount'] as int? ?? 0,
      notes: json['notes'] as String?,
      albumIds: (json['albumIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      folderId: json['folderId'] as String?,
    );
  }

  /// Convert to JSON string
  String toJsonString() => jsonEncode(toJson());

  /// Create from JSON string
  factory VaultedFile.fromJsonString(String jsonString) {
    return VaultedFile.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }

  /// Get file extension from original name
  String get extension {
    final parts = originalName.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  /// Get formatted file size
  String get formattedSize {
    if (fileSize < 1024) {
      return '$fileSize B';
    } else if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    } else if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  /// Check if file is an image
  bool get isImage => type == VaultedFileType.image;

  /// Check if file is a video
  bool get isVideo => type == VaultedFileType.video;

  /// Check if file is a document
  bool get isDocument => type == VaultedFileType.document;

  /// Check if file is a song
  bool get isSong => type == VaultedFileType.song;

  /// Get tag count
  int get tagCount => tags.length;

  /// Get album count
  int get albumCount => albumIds.length;

  /// Check if file has tags
  bool get hasTags => tags.isNotEmpty;

  /// Get formatted date added
  String get formattedDateAdded {
    final now = DateTime.now();
    final diff = now.difference(dateAdded);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        return '${diff.inMinutes}m ago';
      }
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${dateAdded.day}/${dateAdded.month}/${dateAdded.year}';
    }
  }

  @override
  String toString() {
    return 'VaultedFile(id: $id, name: $originalName, type: $type, size: $formattedSize, tags: $tags, encrypted: $isEncrypted)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VaultedFile && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// Supported image extensions
const List<String> supportedImageExtensions = [
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'bmp',
  'heic',
  'heif',
  'tiff',
  'tif'
];

/// Supported video extensions
const List<String> supportedVideoExtensions = [
  'mp4',
  'mov',
  'avi',
  'mkv',
  'webm',
  'flv',
  'wmv',
  'm4v',
  '3gp'
];

/// Supported document extensions
const List<String> supportedDocumentExtensions = [
  'pdf',
  'doc',
  'docx',
  'txt',
  'rtf',
  'odt',
  'epub',
];

/// Supported audio extensions
const List<String> supportedAudioExtensions = [
  'mp3',
  'wav',
  'flac',
  'aac',
  'ogg',
  'm4a',
];

/// Get file type from extension
VaultedFileType getFileTypeFromExtension(String extension) {
  final ext = extension.toLowerCase().replaceAll('.', '');

  if (supportedImageExtensions.contains(ext)) {
    return VaultedFileType.image;
  } else if (supportedVideoExtensions.contains(ext)) {
    return VaultedFileType.video;
  } else if (supportedAudioExtensions.contains(ext)) {
    return VaultedFileType.song;
  } else if (supportedDocumentExtensions.contains(ext)) {
    return VaultedFileType.document;
  }
  return VaultedFileType.other;
}

/// Get file type from MIME type
VaultedFileType getFileTypeFromMime(String mimeType) {
  final mime = mimeType.toLowerCase();

  if (mime.startsWith('image/')) {
    return VaultedFileType.image;
  } else if (mime.startsWith('video/')) {
    return VaultedFileType.video;
  } else if (mime.startsWith('audio/')) {
    return VaultedFileType.song;
  } else if (mime.startsWith('application/pdf') ||
      mime.startsWith('application/msword') ||
      mime.startsWith('application/vnd.') ||
      mime.startsWith('text/')) {
    return VaultedFileType.document;
  }
  return VaultedFileType.other;
}

/// Predefined tags for quick selection
const List<String> predefinedTags = [
  'work',
  'personal',
  'family',
  'friends',
  'travel',
  'events',
  'receipts',
  'important',
  'private',
  'backup',
  'memories',
  'documents',
  'screenshots',
  'downloads',
];

/// Tag with color for UI display
class TagInfo {
  final String name;
  final int colorValue;
  final int usageCount;

  const TagInfo({
    required this.name,
    this.colorValue = 0xFF1976D2,
    this.usageCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'colorValue': colorValue,
        'usageCount': usageCount,
      };

  factory TagInfo.fromJson(Map<String, dynamic> json) => TagInfo(
        name: json['name'] as String,
        colorValue: json['colorValue'] as int? ?? 0xFF1976D2,
        usageCount: json['usageCount'] as int? ?? 0,
      );
}
