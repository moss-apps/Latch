import 'dart:convert';

import '../../../models/vaulted_file.dart';
import '../cipher_codec.dart';
import 'pb_dao.dart';

/// `tags`: TagInfo JSON encrypted into the `cipher_name` text column; the
/// tag name is the app-side id.
class TagDao extends PbDao<TagInfo> {
  TagDao(super.client, super.masterKey);

  @override
  String get collection => 'tags';

  @override
  Map<String, dynamic> toRow(TagInfo t) => {
        'id': pbRecordId(t.name),
        'cipher_name': codec.seal(jsonEncode(t.toJson())),
        'modified_at': DateTime.now().millisecondsSinceEpoch,
        'deleted': false,
      };

  @override
  TagInfo fromRow(Map<String, dynamic> row) =>
      TagInfo.fromJson(jsonDecode(codec.open(row['cipher_name'] as String))
          as Map<String, dynamic>);

  @override
  String appIdOf(TagInfo model) => model.name;
}
