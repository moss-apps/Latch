import 'package:shared_preferences/shared_preferences.dart';

/// Versioned legal acceptance for the mobile app (mirrors legal/version.txt).
///
/// Bumping [legalVersion] forces every install through the consent screen
/// again. Stored in SharedPreferences so it survives app updates but resets
/// on a full uninstall — matching user expectations on mobile.
class LegalConsentService {
  static const int legalVersion = 1;

  static const String _acceptedVersionKey = 'legal_accepted_version';

  /// True when the user accepted the current [legalVersion].
  Future<bool> isAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt(_acceptedVersionKey) ?? 0) >= legalVersion;
  }

  /// Record acceptance of the current version.
  Future<void> accept() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_acceptedVersionKey, legalVersion);
  }

  /// Synchronous test helper — checks a raw stored version value.
  static bool versionAccepted(int? stored) => (stored ?? 0) >= legalVersion;
}
