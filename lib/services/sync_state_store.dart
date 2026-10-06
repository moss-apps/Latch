import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../crypto/aes_gcm_cipher.dart';
import '../crypto/key_derivation.dart';
import '../models/remote_manifest.dart';
import '../models/sync_conflict.dart';
import '../models/sync_profile.dart';

class SyncCheckpoint {
  const SyncCheckpoint({this.baseline = const {}, this.conflicts = const []});
  final Map<String, ManifestEntry> baseline;
  final List<SyncConflict> conflicts;

  Map<String, dynamic> toJson() => {
        'baseline': baseline.map((id, entry) => MapEntry(id, entry.toJson())),
        'conflicts': conflicts.map((c) => c.toJson()).toList(),
      };

  factory SyncCheckpoint.fromJson(Map<String, dynamic> json) => SyncCheckpoint(
        baseline: (json['baseline'] as Map<String, dynamic>).map((id, entry) =>
            MapEntry(
                id, ManifestEntry.fromJson(entry as Map<String, dynamic>))),
        conflicts: (json['conflicts'] as List<dynamic>)
            .map((c) => SyncConflict.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

class SyncStateStore {
  SyncStateStore(this.root, this.key);
  final String root;
  final Uint8List key;

  static const _deletionsKey = 'locker_sync_deletions';
  static const _storage = FlutterSecureStorage();
  static Future<void> _deletionWrite = Future.value();

  static Future<Map<String, DateTime>> deletions() async {
    final json = await _storage.read(key: _deletionsKey);
    if (json == null) return {};
    return (jsonDecode(json) as Map<String, dynamic>)
        .map((id, date) => MapEntry(id, DateTime.parse(date as String)));
  }

  static Future<void> recordDeletion(String id) {
    final write = _deletionWrite.then((_) async {
      final saved = await deletions();
      saved[id] = DateTime.now().toUtc();
      await _storage.write(
          key: _deletionsKey,
          value: jsonEncode(
              saved.map((id, date) => MapEntry(id, date.toIso8601String()))));
    });
    _deletionWrite = write.catchError((Object _) {});
    return write;
  }

  static String targetId(SyncProfile profile) => sha256
      .convert(utf8.encode('${profile.serverUrl.replaceAll(RegExp(r'/+$'), '')}'
          '|${profile.basePath.replaceAll(RegExp(r'/+$'), '')}|${profile.username}'))
      .toString();

  File _file(String target, String suffix) =>
      File('$root/.sync-state/$target.$suffix');

  Future<Map<String, dynamic>?> read(String target,
      {bool journal = false}) async {
    final file = _file(target, journal ? 'journal' : 'state');
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (bytes.length < 32) throw const FormatException('Invalid sync state');
    final plain = AesGcmCipher.process(key, Uint8List.sublistView(bytes, 0, 16),
        Uint8List.sublistView(bytes, 16), false);
    return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
  }

  Future<SyncCheckpoint> load(String target) async {
    final json = await read(target);
    return json == null
        ? const SyncCheckpoint()
        : SyncCheckpoint.fromJson(json);
  }

  Future<void> save(String target, Map<String, dynamic> json,
      {bool journal = false}) async {
    final file = _file(target, journal ? 'journal' : 'state');
    await file.parent.create(recursive: true);
    final iv = KeyDerivation.generateIV();
    final encrypted = AesGcmCipher.process(
        key, iv, Uint8List.fromList(utf8.encode(jsonEncode(json))), true);
    final staging = File('${file.path}.tmp');
    await staging.writeAsBytes([...iv, ...encrypted], flush: true);
    await staging.rename(file.path);
  }

  Future<void> clearJournal(String target) async {
    final file = _file(target, 'journal');
    if (await file.exists()) await file.delete();
  }
}
