import 'vaulted_file.dart';

/// A durable local recovery receipt. Payload bytes are moved, never decrypted.
enum DeletionStage { deleting, trashed, restoring, purging }

class DeletedVaultItem {
  const DeletedVaultItem({
    required this.file,
    required this.deletedAt,
    required this.expiresAt,
    required this.payloadPath,
    this.thumbnailPath,
    this.stage = DeletionStage.deleting,
    this.auxiliaryKey,
    this.auxiliaryRecord,
    this.restoredFile,
  });

  final VaultedFile file;
  final DateTime deletedAt;
  final DateTime expiresAt;
  final String payloadPath;
  final String? thumbnailPath;
  final DeletionStage stage;
  // Notes/passwords have a separate editor index containing their IV and salt.
  final String? auxiliaryKey;
  final Map<String, dynamic>? auxiliaryRecord;
  final VaultedFile? restoredFile;

  bool canRestore(DateTime now) =>
      stage == DeletionStage.trashed && now.isBefore(expiresAt);

  DeletedVaultItem copyWith({
    DeletionStage? stage,
    VaultedFile? restoredFile,
  }) =>
      DeletedVaultItem(
        file: file,
        deletedAt: deletedAt,
        expiresAt: expiresAt,
        payloadPath: payloadPath,
        thumbnailPath: thumbnailPath,
        stage: stage ?? this.stage,
        auxiliaryKey: auxiliaryKey,
        auxiliaryRecord: auxiliaryRecord,
        restoredFile: restoredFile ?? this.restoredFile,
      );

  Map<String, dynamic> toJson() => {
        'file': file.toJson(),
        'deletedAt': deletedAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'payloadPath': payloadPath,
        'thumbnailPath': thumbnailPath,
        'stage': stage.name,
        'auxiliaryKey': auxiliaryKey,
        'auxiliaryRecord': auxiliaryRecord,
        'restoredFile': restoredFile?.toJson(),
      };

  factory DeletedVaultItem.fromJson(Map<String, dynamic> json) =>
      DeletedVaultItem(
        file: VaultedFile.fromJson(json['file'] as Map<String, dynamic>),
        deletedAt: DateTime.parse(json['deletedAt'] as String),
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        payloadPath: json['payloadPath'] as String,
        thumbnailPath: json['thumbnailPath'] as String?,
        stage: DeletionStage.values.byName(json['stage'] as String),
        auxiliaryKey: json['auxiliaryKey'] as String?,
        auxiliaryRecord: json['auxiliaryRecord'] as Map<String, dynamic>?,
        restoredFile: json['restoredFile'] == null
            ? null
            : VaultedFile.fromJson(
                json['restoredFile'] as Map<String, dynamic>),
      );
}
