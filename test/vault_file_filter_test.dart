import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/vault_file_filter.dart';
import 'package:locker/models/vaulted_file.dart';

VaultedFile _file({
  String id = 'f1',
  String name = 'beach.jpg',
  VaultedFileType type = VaultedFileType.image,
  DateTime? dateAdded,
  int fileSize = 1024,
  List<String> tags = const [],
  bool isFavorite = false,
  bool isEncrypted = false,
  List<String> albumIds = const [],
  String? folderId,
}) {
  return VaultedFile(
    id: id,
    originalName: name,
    vaultPath: '/tmp/$id.enc',
    type: type,
    mimeType: 'application/octet-stream',
    fileSize: fileSize,
    dateAdded: dateAdded ?? DateTime(2024, 1, 1),
    tags: tags,
    isFavorite: isFavorite,
    isEncrypted: isEncrypted,
    albumIds: albumIds,
    folderId: folderId,
  );
}

void main() {
  group('VaultFileFilter matching', () {
    test('name query is a case-insensitive substring match', () {
      const filter = VaultFileFilter(nameQuery: 'BEACH');
      expect(filter.matches(_file(name: 'Summer_Beach.jpg')), isTrue);
      expect(filter.matches(_file(name: 'mountain.jpg')), isFalse);
    });

    test('tags require all tags to be present', () {
      const filter = VaultFileFilter(tags: ['work', 'important']);
      expect(
        filter.matches(_file(tags: ['important', 'work', 'other'])),
        isTrue,
      );
      expect(filter.matches(_file(tags: ['work'])), isFalse);
    });

    test('onlyUntagged excludes any tagged file', () {
      const filter = VaultFileFilter(onlyUntagged: true);
      expect(filter.matches(_file(tags: [])), isTrue);
      expect(filter.matches(_file(tags: ['x'])), isFalse);
    });

    test('type, favorite, encryption, size, album and folder match', () {
      final file = _file(
        type: VaultedFileType.video,
        fileSize: 500,
        isFavorite: true,
        isEncrypted: true,
        albumIds: ['a1'],
        folderId: 'fld1',
      );
      expect(
        const VaultFileFilter(
          type: VaultedFileType.video,
          isFavorite: true,
          isEncrypted: true,
          minSizeBytes: 100,
          maxSizeBytes: 1000,
          albumId: 'a1',
          folderId: 'fld1',
        ).matches(file),
        isTrue,
      );
      expect(const VaultFileFilter(type: VaultedFileType.image).matches(file),
          isFalse);
      expect(const VaultFileFilter(isFavorite: false).matches(file), isFalse);
      expect(const VaultFileFilter(isEncrypted: false).matches(file), isFalse);
      expect(const VaultFileFilter(minSizeBytes: 501).matches(file), isFalse);
      expect(const VaultFileFilter(maxSizeBytes: 499).matches(file), isFalse);
      expect(const VaultFileFilter(albumId: 'a2').matches(file), isFalse);
      expect(const VaultFileFilter(folderId: 'fld2').matches(file), isFalse);
    });
  });

  group('date range boundaries are inclusive calendar days', () {
    test('file exactly at start-day midnight matches dateFrom', () {
      final filter = VaultFileFilter(dateFrom: DateTime(2024, 5, 10));
      expect(
        filter.matches(_file(dateAdded: DateTime(2024, 5, 10, 0, 0, 0))),
        isTrue,
      );
    });

    test('file late on end day matches dateTo', () {
      final filter = VaultFileFilter(dateTo: DateTime(2024, 5, 10));
      expect(
        filter.matches(_file(dateAdded: DateTime(2024, 5, 10, 23, 59, 59))),
        isTrue,
      );
    });

    test('file at next-day midnight is excluded by dateTo', () {
      final filter = VaultFileFilter(dateTo: DateTime(2024, 5, 10));
      expect(
        filter.matches(_file(dateAdded: DateTime(2024, 5, 11, 0, 0, 0))),
        isFalse,
      );
    });

    test('file just before start day is excluded by dateFrom', () {
      final filter = VaultFileFilter(dateFrom: DateTime(2024, 5, 10));
      expect(
        filter.matches(_file(dateAdded: DateTime(2024, 5, 9, 23, 59, 59))),
        isFalse,
      );
    });

    test('same-day range matches only that day', () {
      final filter = VaultFileFilter(
        dateFrom: DateTime(2024, 5, 10),
        dateTo: DateTime(2024, 5, 10),
      );
      expect(
          filter.matches(_file(dateAdded: DateTime(2024, 5, 10, 8))), isTrue);
      expect(
          filter.matches(_file(dateAdded: DateTime(2024, 5, 9, 23))), isFalse);
      expect(
          filter.matches(_file(dateAdded: DateTime(2024, 5, 11, 1))), isFalse);
    });

    test('open-ended dateFrom matches everything after the day', () {
      final filter = VaultFileFilter(dateFrom: DateTime(2024, 5, 10));
      expect(filter.matches(_file(dateAdded: DateTime(2024, 6, 1))), isTrue);
      expect(filter.matches(_file(dateAdded: DateTime(2024, 5, 1))), isFalse);
    });

    test('open-ended dateTo matches everything before the day', () {
      final filter = VaultFileFilter(dateTo: DateTime(2024, 5, 10));
      expect(filter.matches(_file(dateAdded: DateTime(2024, 4, 1))), isTrue);
      expect(filter.matches(_file(dateAdded: DateTime(2024, 5, 11))), isFalse);
    });

    test('inverted range matches nothing', () {
      final filter = VaultFileFilter(
        dateFrom: DateTime(2024, 5, 20),
        dateTo: DateTime(2024, 5, 10),
      );
      expect(filter.matches(_file(dateAdded: DateTime(2024, 5, 15))), isFalse);
    });

    test('date-only filtering works across month and year boundaries', () {
      final filter = VaultFileFilter(
        dateFrom: DateTime(2023, 12, 30),
        dateTo: DateTime(2024, 1, 2),
      );
      expect(
          filter.matches(_file(dateAdded: DateTime(2024, 1, 1, 12))), isTrue);
      expect(filter.matches(_file(dateAdded: DateTime(2023, 12, 29, 12))),
          isFalse);
      expect(
          filter.matches(_file(dateAdded: DateTime(2024, 1, 3, 0))), isFalse);
    });

    test('UTC timestamps are compared on their local calendar day', () {
      final utcNoon = DateTime.utc(2024, 5, 10, 12);
      final localDay = VaultFileFilter.dayOf(utcNoon.toLocal());

      final sameDay = VaultFileFilter(dateFrom: localDay, dateTo: localDay);
      expect(sameDay.matches(_file(dateAdded: utcNoon)), isTrue);

      final previousDay = VaultFileFilter(
        dateTo: DateTime(localDay.year, localDay.month, localDay.day - 1),
      );
      expect(previousDay.matches(_file(dateAdded: utcNoon)), isFalse);
    });

    test('day boundaries survive DST transitions', () {
      // US spring-forward (2024-03-10) and EU spring-forward (2024-03-31).
      for (final dstDay in [DateTime(2024, 3, 10), DateTime(2024, 3, 31)]) {
        final nextDay = VaultFileFilter.nextDayOf(dstDay);
        expect(nextDay.hour, 0);
        expect(nextDay.isAfter(dstDay), isTrue);
        expect(VaultFileFilter.dayOf(nextDay), nextDay);

        final filter = VaultFileFilter(dateFrom: dstDay, dateTo: dstDay);
        expect(
          filter.matches(_file(
              dateAdded: DateTime(dstDay.year, dstDay.month, dstDay.day, 2))),
          isTrue,
        );
        expect(
          filter.matches(_file(dateAdded: nextDay)),
          isFalse,
        );
      }
    });
  });

  group('VaultFileFilter serialization', () {
    test('round-trips through JSON', () {
      final filter = VaultFileFilter(
        nameQuery: 'trip',
        tags: ['work', 'travel'],
        type: VaultedFileType.video,
        isFavorite: true,
        onlyUntagged: true,
        isEncrypted: false,
        albumId: 'a1',
        folderId: 'fld1',
        minSizeBytes: 100,
        maxSizeBytes: 5000,
        dateFrom: DateTime(2024, 5, 1),
        dateTo: DateTime(2024, 5, 31),
      );

      final restored = VaultFileFilter.fromJson(filter.toJson());
      expect(restored, filter);
    });

    test('tolerates missing and unknown fields', () {
      final restored = VaultFileFilter.fromJson(const {'bogus': 1});
      expect(restored.isEmpty, isTrue);
    });

    test('copyWith can clear individual dimensions', () {
      final filter = VaultFileFilter(
        nameQuery: 'x',
        type: VaultedFileType.image,
        dateFrom: DateTime(2024, 5, 1),
      );
      final cleared = filter.copyWith(
        clearNameQuery: true,
        clearType: true,
        clearDateFrom: true,
      );
      expect(cleared.isEmpty, isTrue);
    });
  });
}
