import '../../../models/vaulted_file.dart';
import '../cipher_codec.dart';
import 'pb_dao.dart';

/// `vault_files`: `blob_ref`/`modified_at`/`deleted` stay plaintext and
/// sortable; everything else rides encrypted in `cipher_meta`, which is the
/// authoritative source on read (columns are derived, queryable copies).
class VaultFileDao extends PbDao<VaultedFile> {
  VaultFileDao(super.client, super.masterKey);

  @override
  String get collection => 'vault_files';

  @override
  Map<String, dynamic> toRow(VaultedFile f) => {
        'id': pbRecordId(f.id),
        'blob_ref': f.vaultPath,
        'cipher_meta': codec.sealJson(f.toJson()),
        'modified_at': (f.modifiedAt ?? f.dateModified ?? f.dateAdded)
            .millisecondsSinceEpoch,
        'deleted': f.syncedDeleted,
      };

  @override
  VaultedFile fromRow(Map<String, dynamic> row) => VaultedFile.fromJson(
        codec.openJson(row['cipher_meta'] as Map<String, dynamic>)
            as Map<String, dynamic>,
      );

  @override
  String appIdOf(VaultedFile model) => model.id;
}
