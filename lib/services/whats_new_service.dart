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
class WhatsNewService {
  WhatsNewService._();
  static final WhatsNewService instance = WhatsNewService._();

  static const String _lastSeenVersionKey = 'whats_new_last_seen_version';

  /// Version-keyed highlights. The key MUST match `PackageInfo.version`
  /// exactly (the `+buildNumber` suffix is ignored).
  ///
  /// Add a new entry here whenever the app version in `pubspec.yaml` is
  /// bumped to surface the changes to users on first launch.
  static const Map<String, List<WhatsNewSection>> _highlights = {
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

  /// Resolves and caches the running app's version string.
  Future<String> currentVersion() async {
    if (_currentVersion != null) return _currentVersion!;
    final info = await PackageInfo.fromPlatform();
    _currentVersion = info.version;
    return _currentVersion!;
  }

  /// Returns the highlight sections for [version], or an empty list if no
  /// entry exists for it.
  List<WhatsNewSection> highlightsFor(String version) {
    return _highlights[version] ?? const [];
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
      // Fresh install — record the current version and stay silent.
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
