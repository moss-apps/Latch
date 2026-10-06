import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'remote_manifest.dart';

enum ConflictChoice { local, remote, both }

String syncFingerprint(ManifestEntry entry) {
  if (entry.deleted) return 'deleted';
  final json = entry.toJson()
    ..remove('id')
    ..remove('modifiedAt')
    ..remove('dateModified');
  json['tags'] = [...entry.tags]..sort();
  json['albumIds'] = [...entry.albumIds]..sort();
  return sha256.convert(utf8.encode(jsonEncode(json))).toString();
}

class SyncConflict {
  const SyncConflict({required this.local, required this.remote, this.choice});

  final ManifestEntry local;
  final ManifestEntry remote;
  final ConflictChoice? choice;
  String get id => local.id;

  bool matches(ManifestEntry a, ManifestEntry b) =>
      syncFingerprint(local) == syncFingerprint(a) &&
      syncFingerprint(remote) == syncFingerprint(b);

  Map<String, dynamic> toJson() => {
        'local': local.toJson(),
        'remote': remote.toJson(),
        'choice': choice?.name,
      };

  factory SyncConflict.fromJson(Map<String, dynamic> json) => SyncConflict(
        local: ManifestEntry.fromJson(json['local'] as Map<String, dynamic>),
        remote: ManifestEntry.fromJson(json['remote'] as Map<String, dynamic>),
        choice: json['choice'] == null
            ? null
            : ConflictChoice.values.byName(json['choice'] as String),
      );
}
