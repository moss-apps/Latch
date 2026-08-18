import '../../../models/vault_folder.dart';
import '../cipher_codec.dart';
import 'pb_dao.dart';

/// `folders`: whole folder JSON encrypted in `cipher_meta`.
class FolderDao extends PbDao<VaultFolder> {
  FolderDao(super.client, super.masterKey);

  @override
  String get collection => 'folders';

  @override
  Map<String, dynamic> toRow(VaultFolder f) => {
        'id': pbRecordId(f.id),
        'cipher_meta': codec.sealJson(f.toJson()),
        'modified_at': f.updatedAt.millisecondsSinceEpoch,
        'deleted': false,
      };

  @override
  VaultFolder fromRow(Map<String, dynamic> row) => VaultFolder.fromJson(
        codec.openJson(row['cipher_meta'] as Map<String, dynamic>)
            as Map<String, dynamic>,
      );

  @override
  String appIdOf(VaultFolder model) => model.id;
}
