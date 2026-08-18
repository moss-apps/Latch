import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../cipher_codec.dart';
import '../pb_client.dart';

/// Shared CRUD for one PB collection: paginated list, upsert, delete,
/// reconcile (upsert all + remove rows no longer in the expected set).
/// Concrete DAOs map models ↔ rows; secret fields go through [codec].
abstract class PbDao<T> {
  PbDao(this.client, this.masterKey);

  final PbClient client;
  final Uint8List masterKey;

  String get collection;
  String get path => '/api/collections/$collection/records';

  CipherCodec get codec => CipherCodec(masterKey);

  /// Full row for a model, `id` = pbRecordId(...) of the app id.
  Map<String, dynamic> toRow(T model);

  T fromRow(Map<String, dynamic> row);

  /// App id of a model — used by [reconcile] to diff expected rows.
  String appIdOf(T model);

  Future<List<T>> list() async {
    final out = <T>[];
    for (final row in await _rows(null)) {
      try {
        out.add(fromRow(row));
      } catch (e) {
        debugPrint('[PB] skipping undecodable $collection/${row['id']}: $e');
      }
    }
    return out;
  }

  /// Upsert: create, fall back to patch when the id already exists.
  /// 2 calls on the rare update path; batch API if it ever matters.
  Future<void> put(T model) async {
    final row = toRow(model);
    try {
      await client.post(path, body: row);
    } on http.ClientException {
      await client.patch('$path/${row['id']}', body: row..remove('id'));
    }
  }

  Future<void> delete(String appId) => _deleteRecordId(pbRecordId(appId));

  /// Upsert every model, then delete rows absent from [models].
  Future<void> reconcile(Iterable<T> models) async {
    final expected = {for (final m in models) pbRecordId(appIdOf(m))};
    for (final m in models) {
      await put(m);
    }
    for (final id in await _rows('id')
        .then((rows) => rows.map((r) => r['id'] as String))) {
      if (!expected.contains(id)) {
        await _deleteRecordId(id);
      }
    }
  }

  Future<List<Map<String, dynamic>>> _rows(String? fields) async {
    final rows = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final res = await client.get(path, query: {
        'page': '$page',
        'perPage': '200',
        if (fields != null) 'fields': fields,
      });
      final items =
          (res['items'] as List<dynamic>).cast<Map<String, dynamic>>();
      rows.addAll(items);
      if (page >= (res['totalPages'] as num? ?? 1)) break;
      page++;
    }
    return rows;
  }

  Future<void> _deleteRecordId(String recordId) async {
    try {
      await client.delete('$path/$recordId');
    } on http.ClientException {
      // already gone — delete is idempotent
    }
  }
}
