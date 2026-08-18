import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient, Platform;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where this build was installed from.
enum InstallSource { playStore, github, unknown }

/// A pending update surfaced to the UI. For [InstallSource.playStore] the
/// update is applied via in-app update; for [InstallSource.github] the user
/// is sent to the release page in a browser.
class PendingUpdate {
  final InstallSource source;
  final String? latestVersion;
  final String? releaseUrl;

  const PendingUpdate({
    required this.source,
    this.latestVersion,
    this.releaseUrl,
  });
}

class _RemoteRelease {
  final String tag;
  final String url;
  const _RemoteRelease(this.tag, this.url);
}

/// Checks for app updates, dispatching to the Play Store in-app update flow
/// or the GitHub Releases API depending on the detected install source.
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const _installSourceChannel =
      MethodChannel('com.mossapps.locker/install_source');

  // hardcoded repo slug — single distribution channel, no config needed
  static const _releasesUrl =
      'https://api.github.com/repos/moss-apps/Latch/releases/latest';
  static const _releasePageUrl =
      'https://github.com/moss-apps/Latch/releases/latest';
  static const _fetchTimeout = Duration(seconds: 8);
  static const _skippedVersionKey = 'update_skipped_version';

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isChecking = false;
  String? _lastEmittedKey;

  InstallSource _installSource = InstallSource.unknown;
  InstallSource get installSource => _installSource;

  PendingUpdate? _pendingUpdate;
  PendingUpdate? get pendingUpdate => _pendingUpdate;

  final _updateController = StreamController<PendingUpdate?>.broadcast();
  Stream<PendingUpdate?> get onUpdateCheck => _updateController.stream;

  void start() {
    if (!Platform.isAndroid) return;
    unawaited(_init());
  }

  Future<void> _init() async {
    _installSource = await _detectInstallSource();
    await _checkForUpdate();
    _subscription = Connectivity().onConnectivityChanged.listen((results) {
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      if (hasConnection) _checkForUpdate();
    });
  }

  void dispose() {
    _subscription?.cancel();
    _updateController.close();
  }

  Future<PendingUpdate?> checkForUpdate() async {
    await _checkForUpdate();
    return _pendingUpdate;
  }

  Future<void> _checkForUpdate() async {
    if (_isChecking) return;
    _isChecking = true;
    try {
      if (_installSource == InstallSource.playStore) {
        final info = await InAppUpdate.checkForUpdate();
        _pendingUpdate =
            info.updateAvailability == UpdateAvailability.updateAvailable
                ? const PendingUpdate(source: InstallSource.playStore)
                : null;
      } else {
        _pendingUpdate = await _checkGitHubRelease();
      }
      _emit(_pendingUpdate);
    } catch (_) {
      _pendingUpdate = null;
      _emit(null);
    } finally {
      _isChecking = false;
    }
  }

  void _emit(PendingUpdate? update) {
    final key = update == null
        ? null
        : (update.latestVersion ?? update.source.name);
    if (key == _lastEmittedKey) return;
    _lastEmittedKey = key;
    _updateController.add(update);
  }

  Future<void> skipVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_skippedVersionKey, version);
  }

  Future<bool> isVersionSkipped(String? version) async {
    if (version == null) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_skippedVersionKey) == version;
  }

  Future<InstallSource> _detectInstallSource() async {
    if (!Platform.isAndroid) return InstallSource.unknown;
    try {
      final installer = await _installSourceChannel
          .invokeMethod<String>('getInstallerPackageName');
      if (installer == 'com.android.vending') return InstallSource.playStore;
      return InstallSource.github;
    } catch (_) {
      // Detection failed (e.g. channel missing on a fresh build). Default to
      // the Play Store path so the majority flow stays intact; a sideloaded
      // build with a broken channel simply sees no in-app update.
      return InstallSource.playStore;
    }
  }

  Future<PendingUpdate?> _checkGitHubRelease() async {
    final current = await _currentVersion();
    final remote = await _fetchLatestRelease();
    if (remote == null) return null;
    final latest = _normalizeVersion(remote.tag);
    if (!_isNewer(current, latest)) return null;
    return PendingUpdate(
      source: InstallSource.github,
      latestVersion: latest,
      releaseUrl: remote.url,
    );
  }

  Future<String> _currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  Future<_RemoteRelease?> _fetchLatestRelease() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = _fetchTimeout;
      final request = await client.getUrl(Uri.parse(_releasesUrl));
      request.headers.set('Accept', 'application/vnd.github+json');
      final response = await request.close().timeout(_fetchTimeout);
      client.close();
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tag = json['tag_name'] as String? ?? '';
      final url = (json['html_url'] as String?) ?? _releasePageUrl;
      if (tag.isEmpty) return null;
      return _RemoteRelease(tag, url);
    } catch (_) {
      return null;
    }
  }

  static String _normalizeVersion(String tag) =>
      tag.startsWith('v') ? tag.substring(1) : tag;

  static bool _isNewer(String current, String latest) {
    try {
      return Version.parse(latest) > Version.parse(current);
    } catch (_) {
      return latest != current;
    }
  }
}
