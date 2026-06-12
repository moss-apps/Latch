import 'dart:convert';

import 'encryption_algorithm.dart';

class NoteFolder {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  const NoteFolder({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  NoteFolder copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NoteFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory NoteFolder.fromJson(Map<String, dynamic> json) {
    return NoteFolder(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory NoteFolder.fromJsonString(String jsonString) {
    return NoteFolder.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteFolder && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'NoteFolder(id: $id, name: $name)';
}

class Note {
  final String id;
  final String title;
  final String encryptedContentPath;
  final String iv;
  final String keyDerivationSalt;
  final int kdfIterations;
  final String? folderId;
  final bool isPinned;
  final bool isMarkdown;
  final bool isEncrypted;
  final EncryptionAlgorithm encryptionAlgorithm;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Note({
    required this.id,
    required this.title,
    required this.encryptedContentPath,
    required this.iv,
    required this.keyDerivationSalt,
    this.kdfIterations = 100000,
    this.folderId,
    this.isPinned = false,
    this.isMarkdown = false,
    this.isEncrypted = false,
    this.encryptionAlgorithm = EncryptionAlgorithm.aes256Gcm,
    required this.createdAt,
    required this.updatedAt,
  });

  Note copyWith({
    String? id,
    String? title,
    String? encryptedContentPath,
    String? iv,
    String? keyDerivationSalt,
    int? kdfIterations,
    String? folderId,
    bool? clearFolder,
    bool? isPinned,
    bool? isMarkdown,
    bool? isEncrypted,
    EncryptionAlgorithm? encryptionAlgorithm,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      encryptedContentPath: encryptedContentPath ?? this.encryptedContentPath,
      iv: iv ?? this.iv,
      keyDerivationSalt: keyDerivationSalt ?? this.keyDerivationSalt,
      kdfIterations: kdfIterations ?? this.kdfIterations,
      folderId: clearFolder == true ? null : (folderId ?? this.folderId),
      isPinned: isPinned ?? this.isPinned,
      isMarkdown: isMarkdown ?? this.isMarkdown,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      encryptionAlgorithm: encryptionAlgorithm ?? this.encryptionAlgorithm,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Note togglePin() => copyWith(isPinned: !isPinned, updatedAt: DateTime.now());

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'encryptedContentPath': encryptedContentPath,
      'iv': iv,
      'keyDerivationSalt': keyDerivationSalt,
      'kdfIterations': kdfIterations,
      'folderId': folderId,
      'isPinned': isPinned,
      'isMarkdown': isMarkdown,
      'isEncrypted': isEncrypted,
      'encryptionAlgorithm': encryptionAlgorithm.name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'] as String,
      title: json['title'] as String,
      encryptedContentPath: json['encryptedContentPath'] as String,
      iv: json['iv'] as String,
      keyDerivationSalt: json['keyDerivationSalt'] as String,
      kdfIterations: json['kdfIterations'] as int? ?? 100000,
      folderId: json['folderId'] as String?,
      isPinned: json['isPinned'] as bool? ?? false,
      isMarkdown: json['isMarkdown'] as bool? ?? false,
      isEncrypted: json['isEncrypted'] as bool? ?? false,
      encryptionAlgorithm: json['encryptionAlgorithm'] != null
          ? EncryptionAlgorithm.values.firstWhere(
              (e) => e.name == json['encryptionAlgorithm'],
              orElse: () => EncryptionAlgorithm.aes256Gcm,
            )
          : EncryptionAlgorithm.aes256Gcm,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory Note.fromJsonString(String jsonString) {
    return Note.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Note && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Note(id: $id, title: $title, pinned: $isPinned)';
}
