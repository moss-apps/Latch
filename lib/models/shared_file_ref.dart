/// A file shared into Latch from another app.
///
/// The bytes stay owned by the source content provider, so this reference is
/// only valid while the granting process keeps the URI permission alive. It is
/// therefore never persisted and does not survive a process restart; once the
/// grant is gone the user has to share the file again.
class SharedFileRef {
  final String id;
  final String uri;
  final String name;
  final String mimeType;
  final int? sizeBytes;

  const SharedFileRef({
    required this.id,
    required this.uri,
    required this.name,
    required this.mimeType,
    this.sizeBytes,
  });

  static SharedFileRef? fromMap(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final uri = value['uri'];
    if (id is! String || id.isEmpty || uri is! String || uri.isEmpty) {
      return null;
    }
    final rawSize = value['size'];
    return SharedFileRef(
      id: id,
      uri: uri,
      name: value['name'] is String && (value['name'] as String).isNotEmpty
          ? value['name'] as String
          : 'Shared file',
      mimeType: value['mimeType'] is String &&
              (value['mimeType'] as String).isNotEmpty
          ? value['mimeType'] as String
          : 'application/octet-stream',
      sizeBytes: rawSize is num ? rawSize.toInt() : null,
    );
  }

  @override
  String toString() => 'SharedFileRef($id, $name, $uri)';
}

/// A copy of a shared file that now lives in app-private staging storage.
class StagedShareFile {
  final SharedFileRef ref;
  final String? path;
  final String name;
  final String mimeType;
  final int sizeBytes;
  final String? error;

  const StagedShareFile({
    required this.ref,
    this.path,
    required this.name,
    required this.mimeType,
    this.sizeBytes = 0,
    this.error,
  });

  bool get ok => error == null && path != null;

  static StagedShareFile failure(SharedFileRef ref, String error) =>
      StagedShareFile(
        ref: ref,
        name: ref.name,
        mimeType: ref.mimeType,
        error: error,
      );

  static StagedShareFile? fromMap(Object? value, SharedFileRef ref) {
    if (value is! Map) return null;
    final error = value['error'];
    if (error is String && error.isNotEmpty) {
      return failure(ref, error);
    }
    final path = value['path'];
    if (path is! String || path.isEmpty) return null;
    final rawSize = value['size'];
    return StagedShareFile(
      ref: ref,
      path: path,
      name: value['name'] is String && (value['name'] as String).isNotEmpty
          ? value['name'] as String
          : ref.name,
      mimeType: value['mimeType'] is String &&
              (value['mimeType'] as String).isNotEmpty
          ? value['mimeType'] as String
          : ref.mimeType,
      sizeBytes: rawSize is num ? rawSize.toInt() : 0,
    );
  }
}
