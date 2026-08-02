import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/sync_profile.dart';
import 'package:locker/services/remote/remote_store.dart';
import 'package:locker/services/remote/webdav_store.dart';
import 'package:locker/services/sync_service.dart';

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
      final store = WebDAVStore(baseUrl: 'https://nas.local/dav', basePath: '/locker');
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
}
