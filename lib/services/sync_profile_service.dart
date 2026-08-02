import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/sync_profile.dart';

/// CRUD for sync profiles. All profiles (no secrets) live under one
/// secure-storage JSON key; each password lives in its own secure-storage
/// entry keyed by profile id ([SyncProfile.passwordStorageKeyFor]).
class SyncProfileService {
  SyncProfileService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static final SyncProfileService instance = SyncProfileService();

  final FlutterSecureStorage _storage;

  static const String profilesKey = 'sync_profiles';

  Future<List<SyncProfile>> listProfiles() async {
    final raw = await _storage.read(key: profilesKey);
    if (raw == null) return const [];
    return (jsonDecode(raw) as List<dynamic>)
        .map((e) => SyncProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<SyncProfile?> getProfile(String id) async {
    for (final p in await listProfiles()) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> saveProfile(SyncProfile profile) async {
    final profiles = await listProfiles();
    final i = profiles.indexWhere((p) => p.id == profile.id);
    if (i >= 0) {
      profiles[i] = profile;
    } else {
      profiles.add(profile);
    }
    await _storage.write(
      key: profilesKey,
      value: jsonEncode([for (final p in profiles) p.toJson()]),
    );
  }

  Future<void> deleteProfile(String id) async {
    final profiles = await listProfiles();
    profiles.removeWhere((p) => p.id == id);
    await _storage.write(
      key: profilesKey,
      value: jsonEncode([for (final p in profiles) p.toJson()]),
    );
    await _storage.delete(key: SyncProfile.passwordStorageKeyFor(id));
  }

  Future<void> savePassword(String id, String password) => _storage.write(
        key: SyncProfile.passwordStorageKeyFor(id),
        value: password,
      );

  Future<String?> getPassword(String id) =>
      _storage.read(key: SyncProfile.passwordStorageKeyFor(id));

  Future<void> deletePassword(String id) =>
      _storage.delete(key: SyncProfile.passwordStorageKeyFor(id));
}
