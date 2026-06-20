import 'dart:convert';

import 'encryption_algorithm.dart';

class PasswordContent {
  final String username;
  final String password;
  final String url;
  final String notes;

  const PasswordContent({
    this.username = '',
    this.password = '',
    this.url = '',
    this.notes = '',
  });

  PasswordContent copyWith({
    String? username,
    String? password,
    String? url,
    String? notes,
  }) {
    return PasswordContent(
      username: username ?? this.username,
      password: password ?? this.password,
      url: url ?? this.url,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'password': password,
      'url': url,
      'notes': notes,
    };
  }

  factory PasswordContent.fromJson(Map<String, dynamic> json) {
    return PasswordContent(
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      url: json['url'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory PasswordContent.fromJsonString(String jsonString) {
    return PasswordContent.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }
}

class PasswordEntry {
  final String id;
  final String title;
  final String encryptedContentPath;
  final String iv;
  final String keyDerivationSalt;
  final int kdfIterations;
  final List<String> tags;
  final bool isFavorite;
  final bool isEncrypted;
  final EncryptionAlgorithm encryptionAlgorithm;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PasswordEntry({
    required this.id,
    required this.title,
    required this.encryptedContentPath,
    required this.iv,
    required this.keyDerivationSalt,
    this.kdfIterations = 100000,
    this.tags = const [],
    this.isFavorite = false,
    this.isEncrypted = false,
    this.encryptionAlgorithm = EncryptionAlgorithm.aes256Gcm,
    required this.createdAt,
    required this.updatedAt,
  });

  PasswordEntry copyWith({
    String? id,
    String? title,
    String? encryptedContentPath,
    String? iv,
    String? keyDerivationSalt,
    int? kdfIterations,
    List<String>? tags,
    bool? isFavorite,
    bool? isEncrypted,
    EncryptionAlgorithm? encryptionAlgorithm,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PasswordEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      encryptedContentPath: encryptedContentPath ?? this.encryptedContentPath,
      iv: iv ?? this.iv,
      keyDerivationSalt: keyDerivationSalt ?? this.keyDerivationSalt,
      kdfIterations: kdfIterations ?? this.kdfIterations,
      tags: tags ?? this.tags,
      isFavorite: isFavorite ?? this.isFavorite,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      encryptionAlgorithm: encryptionAlgorithm ?? this.encryptionAlgorithm,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  PasswordEntry toggleFavorite() =>
      copyWith(isFavorite: !isFavorite, updatedAt: DateTime.now());

  PasswordEntry addTag(String tag) {
    final normalized = tag.toLowerCase().trim();
    if (normalized.isEmpty || tags.contains(normalized)) return this;
    return copyWith(tags: [...tags, normalized]);
  }

  PasswordEntry removeTag(String tag) {
    final normalized = tag.toLowerCase().trim();
    if (!tags.contains(normalized)) return this;
    return copyWith(tags: tags.where((t) => t != normalized).toList());
  }

  bool hasTag(String tag) => tags.contains(tag.toLowerCase().trim());

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'encryptedContentPath': encryptedContentPath,
      'iv': iv,
      'keyDerivationSalt': keyDerivationSalt,
      'kdfIterations': kdfIterations,
      'tags': tags,
      'isFavorite': isFavorite,
      'isEncrypted': isEncrypted,
      'encryptionAlgorithm': encryptionAlgorithm.name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory PasswordEntry.fromJson(Map<String, dynamic> json) {
    return PasswordEntry(
      id: json['id'] as String,
      title: json['title'] as String,
      encryptedContentPath: json['encryptedContentPath'] as String,
      iv: json['iv'] as String,
      keyDerivationSalt: json['keyDerivationSalt'] as String,
      kdfIterations: json['kdfIterations'] as int? ?? 100000,
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      isFavorite: json['isFavorite'] as bool? ?? false,
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

  factory PasswordEntry.fromJsonString(String jsonString) {
    return PasswordEntry.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PasswordEntry &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'PasswordEntry(id: $id, title: $title, favorite: $isFavorite)';
}
