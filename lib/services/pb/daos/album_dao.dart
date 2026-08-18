import '../../../models/album.dart';
import '../cipher_codec.dart';
import 'pb_dao.dart';

/// `albums`: whole album JSON encrypted in `cipher_meta`; `modified_at`
/// mirrors `updatedAt` for PB-side sorting.
class AlbumDao extends PbDao<Album> {
  AlbumDao(super.client, super.masterKey);

  @override
  String get collection => 'albums';

  @override
  Map<String, dynamic> toRow(Album a) => {
        'id': pbRecordId(a.id),
        'cipher_meta': codec.sealJson(a.toJson()),
        'modified_at': a.updatedAt.millisecondsSinceEpoch,
        'deleted': false,
      };

  @override
  Album fromRow(Map<String, dynamic> row) => Album.fromJson(
        codec.openJson(row['cipher_meta'] as Map<String, dynamic>)
            as Map<String, dynamic>,
      );

  @override
  String appIdOf(Album model) => model.id;
}
