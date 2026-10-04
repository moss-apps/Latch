import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/sync_profile.dart';
import 'package:locker/services/remote/remote_store.dart';
import 'package:locker/services/remote/webdav_store.dart';
import 'package:locker/services/sync_service.dart';

DioException _httpError(int statusCode) {
  final options = RequestOptions(path: '/locker/manifest.enc');
  return DioException(
    requestOptions: options,
    response: Response(requestOptions: options, statusCode: statusCode),
    type: DioExceptionType.badResponse,
  );
}

void main() {
  group('joinPath', () {
    test('joins base and name with a single slash', () {
      expect(WebDAVStore.joinPath('/locker', 'manifest.enc'),
          '/locker/manifest.enc');
      expect(WebDAVStore.joinPath('/locker/', 'ab/cd/hash.enc'),
          '/locker/ab/cd/hash.enc');
      expect(WebDAVStore.joinPath('', 'manifest.enc'), '/manifest.enc');
      expect(WebDAVStore.joinPath('/', '/manifest.enc'), '/manifest.enc');
    });
  });

  group('transport paths', () {
    test('manifest blob path resolves under the profile base path', () {
      final store =
          WebDAVStore(baseUrl: 'https://nas.local/dav', basePath: '/locker');
      // joinPath is public; _path is private, so assert the same contract the
      // WebDAV client will receive: absolute server path for the manifest.
      expect(WebDAVStore.joinPath(store.basePath, RemoteStore.manifestName),
          '/locker/${SyncService.manifestName}');
    });

    test('blob names shard under the base path', () {
      const hash =
          'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';
      expect(
        WebDAVStore.joinPath('/locker', SyncService.blobNameFor(hash)),
        '/locker/ab/cd/$hash.enc',
      );
    });
  });

  group('SyncProfile password keys', () {
    test('password key is derived from profile id', () {
      final p = SyncProfile(id: 'p1', serverUrl: 'https://nas.local/dav');
      expect(p.passwordStorageKey, 'sync_profile_pw_p1');
      expect(SyncProfile.passwordStorageKeyFor('p1'), 'sync_profile_pw_p1');
    });
  });

  group('readOrNull error classification', () {
    test('returns bytes when the read succeeds', () async {
      final bytes = await WebDAVStore.readOrNull(() async => [1, 2, 3]);
      expect(bytes, Uint8List.fromList([1, 2, 3]));
    });

    test('only a confirmed 404 is treated as absent', () async {
      final bytes =
          await WebDAVStore.readOrNull(() async => throw _httpError(404));
      expect(bytes, isNull);
    });

    test('authentication and server errors propagate', () async {
      for (final status in [401, 403, 500]) {
        await expectLater(
          WebDAVStore.readOrNull(() async => throw _httpError(status)),
          throwsA(isA<DioException>()
              .having((e) => e.response?.statusCode, 'statusCode', status)),
        );
      }
    });

    test('transport errors propagate', () async {
      final error = DioException(
        requestOptions: RequestOptions(path: '/locker/manifest.enc'),
        type: DioExceptionType.connectionError,
      );
      await expectLater(
        WebDAVStore.readOrNull(() async => throw error),
        throwsA(same(error)),
      );
    });

    test('isNotFound matches only HTTP 404', () {
      expect(WebDAVStore.isNotFound(_httpError(404)), isTrue);
      expect(WebDAVStore.isNotFound(_httpError(500)), isFalse);
      expect(WebDAVStore.isNotFound(Exception('nope')), isFalse);
    });
  });
}
