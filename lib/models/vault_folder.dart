import 'dart:convert';

class VaultFolder {
  final String id;
  final String name;
  final String? parentId;
  final String? description;
  final String? coverImageId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> fileIds;
  final List<String> subfolderIds;

  const VaultFolder({
    required this.id,
    required this.name,
    this.parentId,
    this.description,
    this.coverImageId,
    required this.createdAt,
    required this.updatedAt,
    this.fileIds = const [],
    this.subfolderIds = const [],
  });

  int get fileCount => fileIds.length;
  int get subfolderCount => subfolderIds.length;
  bool get isEmpty => fileIds.isEmpty && subfolderIds.isEmpty;
  bool get isRoot => parentId == null;
  bool get hasSubfolders => subfolderIds.isNotEmpty;
  bool get hasFiles => fileIds.isNotEmpty;
  bool containsFile(String fileId) => fileIds.contains(fileId);
  bool containsSubfolder(String folderId) => subfolderIds.contains(folderId);

  VaultFolder copyWith({
    String? id,
    String? name,
    String? parentId,
    String? description,
    String? coverImageId,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? fileIds,
    List<String>? subfolderIds,
  }) {
    return VaultFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      description: description ?? this.description,
      coverImageId: coverImageId ?? this.coverImageId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      fileIds: fileIds ?? List.from(this.fileIds),
      subfolderIds: subfolderIds ?? List.from(this.subfolderIds),
    );
  }

  VaultFolder addFile(String fileId) {
    if (fileIds.contains(fileId)) return this;
    return copyWith(
      fileIds: [...fileIds, fileId],
      updatedAt: DateTime.now(),
    );
  }

  VaultFolder addFiles(List<String> ids) {
    final newIds = ids.where((id) => !fileIds.contains(id)).toList();
    if (newIds.isEmpty) return this;
    return copyWith(
      fileIds: [...fileIds, ...newIds],
      updatedAt: DateTime.now(),
    );
  }

  VaultFolder removeFile(String fileId) {
    if (!fileIds.contains(fileId)) return this;
    return copyWith(
      fileIds: fileIds.where((id) => id != fileId).toList(),
      updatedAt: DateTime.now(),
      coverImageId: coverImageId == fileId ? null : coverImageId,
    );
  }

  VaultFolder removeFiles(List<String> ids) {
    final idsSet = ids.toSet();
    final newFileIds = fileIds.where((id) => !idsSet.contains(id)).toList();
    return copyWith(
      fileIds: newFileIds,
      updatedAt: DateTime.now(),
      coverImageId: idsSet.contains(coverImageId) ? null : coverImageId,
    );
  }

  VaultFolder addSubfolder(String folderId) {
    if (subfolderIds.contains(folderId)) return this;
    return copyWith(
      subfolderIds: [...subfolderIds, folderId],
      updatedAt: DateTime.now(),
    );
  }

  VaultFolder removeSubfolder(String folderId) {
    if (!subfolderIds.contains(folderId)) return this;
    return copyWith(
      subfolderIds: subfolderIds.where((id) => id != folderId).toList(),
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'parentId': parentId,
      'description': description,
      'coverImageId': coverImageId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'fileIds': fileIds,
      'subfolderIds': subfolderIds,
    };
  }

  factory VaultFolder.fromJson(Map<String, dynamic> json) {
    return VaultFolder(
      id: json['id'] as String,
      name: json['name'] as String,
      parentId: json['parentId'] as String?,
      description: json['description'] as String?,
      coverImageId: json['coverImageId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      fileIds: (json['fileIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      subfolderIds: (json['subfolderIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory VaultFolder.fromJsonString(String jsonString) {
    return VaultFolder.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }

  @override
  String toString() {
    return 'VaultFolder(id: $id, name: $name, fileCount: $fileCount, subfolders: $subfolderCount, parentId: $parentId)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VaultFolder && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}