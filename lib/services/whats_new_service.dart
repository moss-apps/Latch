import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A single highlight item shown in the "What's New" bottom sheet.
class WhatsNewItem {
  final IconData icon;
  final String title;
  final String description;

  const WhatsNewItem({
    required this.icon,
    required this.title,
    required this.description,
  });
}

/// Highlights grouped under a single section header (e.g. "Encryption").
class WhatsNewSection {
  final String title;
  final List<WhatsNewItem> items;

  const WhatsNewSection({
    required this.title,
    required this.items,
  });
}

/// Tracks app version transitions and serves the highlights shown to the
/// user the first time they open a freshly-updated build.
///
/// Highlights are sourced from the bundled `whats_new.json` (mirrored from
/// GitHub) and refreshed from the remote copy on launch. When the network is
/// unavailable the bundled file is used. Version lookups ignore pre-release
/// suffixes, so `0.16.0-beta.1` matches a `0.16.0` entry; when several
/// pre-releases share a core version, the latest wins.
class WhatsNewService {
  WhatsNewService._();
  static final WhatsNewService instance = WhatsNewService._();

  static const String _lastSeenVersionKey = 'whats_new_last_seen_version';
  static const String _cachedHighlightsKey = 'whats_new_cached_highlights';
  static const String _cachedEtagKey = 'whats_new_cached_etag';

  static const String _remoteUrl =
      'https://raw.githubusercontent.com/moss-apps/Latch/main/whats_new.json';

  static const _fetchTimeout = Duration(seconds: 8);

  String? _currentVersion;
  Map<String, List<WhatsNewSection>>? _fetchedHighlights;
  Map<String, List<WhatsNewSection>>? _assetHighlights;
  bool _fetchInitiated = false;

  /// Maps icon names used in the remote JSON to Flutter [IconData].
  static IconData _iconFor(String name) {
    switch (name) {
      case 'shield_outlined':
        return Icons.shield_outlined;
      case 'key_outlined':
        return Icons.key_outlined;
      case 'warning_amber_outlined':
        return Icons.warning_amber_outlined;
      case 'touch_app_outlined':
        return Icons.touch_app_outlined;
      case 'checklist_outlined':
        return Icons.checklist_outlined;
      case 'system_update_outlined':
        return Icons.system_update_outlined;
      case 'bug_report_outlined':
        return Icons.bug_report_outlined;
      case 'auto_awesome_outlined':
        return Icons.auto_awesome_outlined;
      case 'lock_outlined':
        return Icons.lock_outlined;
      case 'folder_outlined':
        return Icons.folder_outlined;
      case 'palette_outlined':
        return Icons.palette_outlined;
      case 'speed':
        return Icons.speed;
      case 'photo_library_outlined':
        return Icons.photo_library_outlined;
      case 'new_releases_outlined':
        return Icons.new_releases_outlined;
      case 'build_outlined':
        return Icons.build_outlined;
      case 'note_outlined':
        return Icons.note_outlined;
      case 'mic_outlined':
        return Icons.mic_outlined;
      case 'filter_list':
        return Icons.filter_list;
      case 'info_outlined':
        return Icons.info_outlined;
      default:
        return Icons.info_outlined;
    }
  }

  /// Resolves and caches the running app's version string.
  Future<String> currentVersion() async {
    if (_currentVersion != null) return _currentVersion!;
    final info = await PackageInfo.fromPlatform();
    _currentVersion = info.version;
    return _currentVersion!;
  }

  /// Returns the highlight sections for [version], preferring the
  /// remotely-fetched set, then the bundled `whats_new.json` asset.
  ///
  /// Pre-release suffixes are ignored, so `0.16.0-beta.1` resolves to a
  /// `0.16.0` entry. When several pre-releases share a core version the
  /// latest one is returned.
  Future<List<WhatsNewSection>> highlightsFor(String version) async {
    final map = _fetchedHighlights ?? await _assetMap();
    return _lookup(map, version);
  }

  Future<Map<String, List<WhatsNewSection>>> _assetMap() async {
    if (_assetHighlights != null) return _assetHighlights!;
    try {
      _assetHighlights =
          _parseJson(await rootBundle.loadString('whats_new.json'));
    } catch (_) {
      _assetHighlights = {};
    }
    return _assetHighlights!;
  }

  List<WhatsNewSection> _lookup(
    Map<String, List<WhatsNewSection>> map,
    String version,
  ) {
    final exact = map[version];
    if (exact != null) return exact;

    final core = _coreVersion(version);
    String? bestKey;
    Version? bestVer;
    for (final key in map.keys) {
      if (_coreVersion(key) != core) continue;
      final parsed = _tryParse(key);
      if (parsed == null) {
        bestKey ??= key;
        continue;
      }
      if (bestVer == null || parsed > bestVer) {
        bestVer = parsed;
        bestKey = key;
      }
    }
    return bestKey == null ? const [] : map[bestKey]!;
  }

  /// Strips build and pre-release suffixes, leaving `major.minor.patch`.
  static String _coreVersion(String v) =>
      v.split('+').first.split('-').first;

  static Version? _tryParse(String v) {
    try {
      return Version.parse(v);
    } catch (_) {
      return null;
    }
  }

  /// Kicks off a non-blocking fetch of the remote highlights JSON.
  ///
  /// Call once early in the app lifecycle. The result is ingested on a
  /// best-effort basis — if the network call fails the service silently
  /// keeps using the bundled asset.
  void startRemoteRefresh() {
    if (_fetchInitiated) return;
    _fetchInitiated = true;
    _loadFromCache();
    unawaited(_fetchAndCache());
  }

  Future<void> _fetchAndCache() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = _fetchTimeout;
      final prefs = await SharedPreferences.getInstance();
      final cachedEtag = prefs.getString(_cachedEtagKey);

      final request = await client.getUrl(Uri.parse(_remoteUrl));
      if (cachedEtag != null) {
        request.headers.set(HttpHeaders.ifNoneMatchHeader, cachedEtag);
      }

      final response = await request.close().timeout(_fetchTimeout);
      client.close();

      if (response.statusCode == 304) return; // not modified
      if (response.statusCode != 200) return;

      final body = await response.transform(utf8.decoder).join();

      final parsed = _parseJson(body);
      if (parsed.isEmpty) return;

      _fetchedHighlights = parsed;
      await prefs.setString(_cachedHighlightsKey, body);

      final etag = response.headers.value(HttpHeaders.etagHeader);
      if (etag != null) {
        await prefs.setString(_cachedEtagKey, etag);
      }
    } catch (_) {
      _loadFromCache();
    }
  }

  void _loadFromCache() {
    SharedPreferences.getInstance().then((prefs) {
      final raw = prefs.getString(_cachedHighlightsKey);
      if (raw != null) {
        final parsed = _parseJson(raw);
        if (parsed.isNotEmpty) _fetchedHighlights = parsed;
      }
    });
  }

  Map<String, List<WhatsNewSection>> _parseJson(String raw) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final result = <String, List<WhatsNewSection>>{};
      for (final entry in decoded.entries) {
        final sections = (entry.value as List<dynamic>).map((s) {
          final map = s as Map<String, dynamic>;
          return WhatsNewSection(
            title: map['title'] as String,
            items: (map['items'] as List<dynamic>).map((i) {
              final item = i as Map<String, dynamic>;
              return WhatsNewItem(
                icon: _iconFor(item['icon'] as String? ?? 'info_outlined'),
                title: item['title'] as String,
                description: item['description'] as String,
              );
            }).toList(),
          );
        }).toList();
        result[entry.key] = sections;
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  /// Whether the "What's New" sheet should be shown on this launch.
  ///
  /// Returns `false` on a fresh install (no prior version recorded) so a
  /// first-time user is not greeted with update notes for a release they
  /// have never used.
  Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSeen = prefs.getString(_lastSeenVersionKey);
    final current = await currentVersion();

    if (lastSeen == null) {
      await prefs.setString(_lastSeenVersionKey, current);
      return false;
    }

    if (lastSeen == current) return false;
    return (await highlightsFor(current)).isNotEmpty;
  }

  /// Persist the current version as "seen" so the sheet does not reappear
  /// until the next update.
  Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final current = await currentVersion();
    await prefs.setString(_lastSeenVersionKey, current);
  }

  /// Force the sheet to reappear on the next launch (used by tests and
  /// debug tooling).
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastSeenVersionKey);
  }
}
