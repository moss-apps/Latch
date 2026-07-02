import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
/// Highlights are fetched from the GitHub repo on launch and cached
/// locally. If the network is unavailable the cached copy is used; if no
/// cache exists the built-in fallback is served instead.
class WhatsNewService {
  WhatsNewService._();
  static final WhatsNewService instance = WhatsNewService._();

  static const String _lastSeenVersionKey = 'whats_new_last_seen_version';
  static const String _cachedHighlightsKey = 'whats_new_cached_highlights';
  static const String _cachedEtagKey = 'whats_new_cached_etag';

  static const String _remoteUrl =
      'https://raw.githubusercontent.com/moss-apps/Latch/main/whats_new.json';

  static const _fetchTimeout = Duration(seconds: 8);

  /// Built-in highlights shipped with the app. Used as the ultimate
  /// fallback when there is no cached data and the network is unavailable.
  ///
  /// The key MUST match `PackageInfo.version` exactly (the `+buildNumber`
  /// suffix is ignored).
  static const Map<String, List<WhatsNewSection>> _builtIn = {
    '0.16.0-beta.1': [
      WhatsNewSection(
        title: 'Encryption Management',
        items: [
          WhatsNewItem(
            icon: Icons.shield_outlined,
            title: 'Batch encrypt/decrypt',
            description:
                'New encryption management screen lets you encrypt or remove encryption from multiple files at once with progress tracking.',
          ),
          WhatsNewItem(
            icon: Icons.lock_outlined,
            title: 'Per-file encryption control',
            description:
                'Add or strip encryption from individual files in-place with full progress feedback.',
          ),
        ],
      ),
      WhatsNewSection(
        title: 'Explorer & Navigation',
        items: [
          WhatsNewItem(
            icon: Icons.build_outlined,
            title: 'List & grid views',
            description:
                'Toggle between list and grid layouts in the vault explorer — cleaner and simpler than the old sidebar.',
          ),
          WhatsNewItem(
            icon: Icons.filter_list,
            title: 'Category filter bar',
            description:
                'Quickly filter your gallery by file type with the new bottom filter bar.',
          ),
        ],
      ),
      WhatsNewSection(
        title: 'Performance',
        items: [
          WhatsNewItem(
            icon: Icons.speed,
            title: 'Cancelable operations',
            description:
                'File opening and decryption can now be cancelled mid-operation — no more waiting for slow files.',
          ),
          WhatsNewItem(
            icon: Icons.bug_report_outlined,
            title: 'Large PDF fix',
            description:
                'PDF viewer now streams from disk instead of loading into memory, fixing ANR crashes on large documents.',
          ),
          WhatsNewItem(
            icon: Icons.auto_awesome_outlined,
            title: 'Animated logo',
            description:
                'A new animated Latch logo greets you on the auth screen with a staggered entrance animation.',
          ),
        ],
      ),
    ],
    '0.15.0-beta.1': [
      WhatsNewSection(
        title: 'Password Vault & Autofill',
        items: [
          WhatsNewItem(
            icon: Icons.lock_outlined,
            title: 'Password vault',
            description:
                'Store, edit, and organise credentials inside the encrypted vault with a built-in strong password generator.',
          ),
          WhatsNewItem(
            icon: Icons.auto_awesome_outlined,
            title: 'Android Autofill',
            description:
                'Seamlessly fill credentials in other apps and browsers — Latch now integrates with the Android Autofill framework.',
          ),
          WhatsNewItem(
            icon: Icons.info_outlined,
            title: 'Clipboard auto-clear',
            description:
                'Copied passwords are automatically cleared from the clipboard after use.',
          ),
        ],
      ),
      WhatsNewSection(
        title: 'Crypto Overhaul',
        items: [
          WhatsNewItem(
            icon: Icons.shield_outlined,
            title: 'Argon2id + key wrapping',
            description:
                'AEAD key-wrapping protects the vault master key. Argon2id joins PBKDF2 for memory-hard key derivation.',
          ),
          WhatsNewItem(
            icon: Icons.key_outlined,
            title: '600,000 PBKDF2 iterations',
            description:
                'Default iterations raised 6× — from 100k to 600k — for stronger resistance against brute-force attacks.',
          ),
          WhatsNewItem(
            icon: Icons.new_releases_outlined,
            title: 'Auto re-wrap on PIN change',
            description:
                'The encryption key is automatically re-wrapped when you change your password or PIN.',
          ),
        ],
      ),
      WhatsNewSection(
        title: 'Updates & Stability',
        items: [
          WhatsNewItem(
            icon: Icons.system_update_outlined,
            title: 'GitHub update support',
            description:
                'Update checks now detect your install source — Play Store, sideload, or GitHub — and route you accordingly.',
          ),
          WhatsNewItem(
            icon: Icons.bug_report_outlined,
            title: 'Comprehensive test suite',
            description:
                'New unit tests cover every crypto path: AES-256-GCM, CTR, PBKDF2, Argon2id, and key wrapping.',
          ),
          WhatsNewItem(
            icon: Icons.build_outlined,
            title: 'CI workflow active',
            description:
                'Automated builds and tests now run on every push to the versionF branch.',
          ),
        ],
      ),
    ],
    '0.14.4-beta.4': [
      WhatsNewSection(
        title: 'Notes',
        items: [
          WhatsNewItem(
            icon: Icons.note_outlined,
            title: 'Encrypted notes',
            description:
                'Create, edit, and organise secure notes inside the vault with folders, search, and multi-select.',
          ),
          WhatsNewItem(
            icon: Icons.folder_outlined,
            title: 'Note folders',
            description:
                'Hierarchical folder organisation with full CRUD operations for your notes.',
          ),
        ],
      ),
      WhatsNewSection(
        title: 'Audio Recording',
        items: [
          WhatsNewItem(
            icon: Icons.mic_outlined,
            title: 'Voice recording',
            description:
                'Record audio directly into the vault with real-time amplitude visualisation and preview.',
          ),
        ],
      ),
      WhatsNewSection(
        title: 'UI & Design',
        items: [
          WhatsNewItem(
            icon: Icons.palette_outlined,
            title: 'Adaptive logo',
            description:
                'Logo automatically switches between light and dark variants to match your theme.',
          ),
          WhatsNewItem(
            icon: Icons.build_outlined,
            title: 'Resizable sidebar',
            description:
                'Drag to resize the vault explorer sidebar to your preferred width.',
          ),
        ],
      ),
      WhatsNewSection(
        title: 'Under the Hood',
        items: [
          WhatsNewItem(
            icon: Icons.new_releases_outlined,
            title: 'Centralised file service',
            description:
                'All vault file opening now routed through a single service for better reliability.',
          ),
          WhatsNewItem(
            icon: Icons.auto_awesome_outlined,
            title: 'Always up-to-date',
            description:
                'What\'s New and Changelog now fetch live from GitHub — no APK update needed for release notes.',
          ),
        ],
      ),
    ],
    '0.14.2-beta.3': [
      WhatsNewSection(
        title: 'Encryption & Crypto',
        items: [
          WhatsNewItem(
            icon: Icons.shield_outlined,
            title: 'AES-256-GCM v2',
            description:
                'Authenticated encryption with an isolate-based crypto worker pool — heavy work runs off the UI thread.',
          ),
          WhatsNewItem(
            icon: Icons.key_outlined,
            title: 'Dynamic KDF iterations',
            description:
                'Password and PIN hashing now uses per-credential PBKDF2 iteration counts that rotate automatically when vault settings change.',
          ),
          WhatsNewItem(
            icon: Icons.warning_amber_outlined,
            title: 'Re-encryption safeguards',
            description:
                'Detailed risk explanations are surfaced before any re-encryption begins.',
          ),
        ],
      ),
      WhatsNewSection(
        title: 'Selection & Gestures',
        items: [
          WhatsNewItem(
            icon: Icons.touch_app_outlined,
            title: 'Hold-to-action',
            description:
                'Long-press a file to open an action sheet instead of immediately entering selection mode.',
          ),
          WhatsNewItem(
            icon: Icons.checklist_outlined,
            title: 'Multi-select action sheet',
            description:
                'Batch operations are now organised into a clean quick-action grid.',
          ),
        ],
      ),
      WhatsNewSection(
        title: 'Updates & Reliability',
        items: [
          WhatsNewItem(
            icon: Icons.system_update_outlined,
            title: 'In-app updates',
            description:
                'Latch now checks the Play Store on launch and offers to update without leaving the app.',
          ),
          WhatsNewItem(
            icon: Icons.bug_report_outlined,
            title: 'Sturdier exports',
            description:
                'Parallel file export with improved progress tracking, plus fixes for vault entry parsing and empty index saves.',
          ),
        ],
      ),
    ],
  };

  String? _currentVersion;
  Map<String, List<WhatsNewSection>>? _fetchedHighlights;
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
  /// remotely-fetched set when available, then checking the built-in
  /// fallback.
  List<WhatsNewSection> highlightsFor(String version) {
    if (_fetchedHighlights != null) {
      return _fetchedHighlights![version] ?? const [];
    }
    return _builtIn[version] ?? const [];
  }

  /// Kicks off a non-blocking fetch of the remote highlights JSON.
  ///
  /// Call once early in the app lifecycle. The result is ingested on a
  /// best-effort basis — if the network call fails the service silently
  /// keeps using the built-in fallback.
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
    return highlightsFor(current).isNotEmpty;
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
