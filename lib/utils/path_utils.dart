import 'dart:io';
import 'package:path_provider/path_provider.dart' as pp;

/// Centralized Android/public-storage path resolution.
///
/// Absolute Android paths don't exist on all OEM ROMs and bypass scoped
/// storage on Android 11+. Everything routes through here so the fallback
/// logic lives in one place.
class PathUtils {
  PathUtils._();

  /// Public primary external storage root on Android (may not exist on all
  /// ROMs / scoped-storage builds).
  static const String androidStorageRoot = '/storage/emulated/0';

  /// Resolve a writable Downloads directory.
  /// On Android tries the canonical public Downloads path first, falling back
  /// to the scoped external-storage dir if absent.
  static Future<Directory?> getDownloadsDirectory() async {
    if (Platform.isAndroid) {
      final primary = Directory('$androidStorageRoot/Download');
      if (await primary.exists()) return primary;
      return pp.getExternalStorageDirectory();
    }
    return pp.getDownloadsDirectory();
  }

  /// Common Android document/media source roots to seed a picker.
  static const List<String> androidSourceRoots = [
    '$androidStorageRoot/Download',
    '$androidStorageRoot/Documents',
    '$androidStorageRoot/DCIM',
    '/sdcard/Download',
    '/sdcard/Documents',
  ];
}
