import 'package:flutter_test/flutter_test.dart';
import 'package:locker/utils/note_text.dart';

void main() {
  group('deriveNoteTitle', () {
    test('prefers the explicit title', () {
      expect(
        deriveNoteTitle('Groceries', 'milk\neggs'),
        'Groceries',
      );
      expect(
        deriveNoteTitle('  Groceries  ', 'milk'),
        'Groceries',
      );
    });

    test('falls back to the first non-empty body line', () {
      expect(
        deriveNoteTitle('', '\n\n## Trip checklist\npack bags'),
        'Trip checklist',
      );
    });

    test('strips Markdown formatting from the derived title', () {
      expect(
        deriveNoteTitle('', '- [ ] **Call** the [dentist](tel:1)'),
        'Call the dentist',
      );
    });

    test('returns empty for an empty note', () {
      expect(deriveNoteTitle('', ' \n\t'), '');
    });
  });

  group('notePreviewText', () {
    test('removes Markdown punctuation but keeps words', () {
      final preview = notePreviewText(
        '# Title\n\n- first item\n- **second** item\n\n'
        'A [link](https://example.com) and `code`.',
      );
      expect(preview, contains('Title'));
      expect(preview, contains('• first item'));
      expect(preview, contains('second item'));
      expect(preview, contains('link'));
      expect(preview, isNot(contains('#')));
      expect(preview, isNot(contains('**')));
      expect(preview, isNot(contains('https://')));
    });

    test('truncates long previews on a word boundary', () {
      final preview = notePreviewText('word ' * 200, maxLength: 40);
      expect(preview.length, lessThanOrEqualTo(41));
      expect(preview.endsWith('…'), isTrue);
    });

    test('returns empty for blank content', () {
      expect(notePreviewText('   '), '');
    });
  });

  group('noteMatchesQuery', () {
    test('matches title and body case-insensitively', () {
      expect(noteMatchesQuery('trip', 'Trip plan', 'pack bags'), isTrue);
      expect(noteMatchesQuery('PACK', 'Trip plan', 'pack bags'), isTrue);
    });

    test('requires every term', () {
      expect(noteMatchesQuery('trip bags', 'Trip plan', 'pack bags'), isTrue);
      expect(noteMatchesQuery('trip shoes', 'Trip plan', 'pack bags'), isFalse);
    });

    test('searches encrypted notes by title only', () {
      expect(noteMatchesQuery('secret', 'Secret note', null), isTrue);
      expect(noteMatchesQuery('body', 'Secret note', null), isFalse);
    });

    test('an empty query matches everything', () {
      expect(noteMatchesQuery('   ', '', ''), isTrue);
    });
  });

  group('formatNoteDate', () {
    final now = DateTime(2026, 11, 22, 12);

    test('formats recent times compactly', () {
      expect(formatNoteDate(now.subtract(const Duration(seconds: 10)), now: now),
          'Just now');
      expect(formatNoteDate(now.subtract(const Duration(minutes: 5)), now: now),
          '5m ago');
      expect(formatNoteDate(now.subtract(const Duration(hours: 3)), now: now),
          '3h ago');
      expect(formatNoteDate(now.subtract(const Duration(days: 2)), now: now),
          '2d ago');
    });

    test('uses a date after a week', () {
      expect(
        formatNoteDate(DateTime(2026, 10, 1), now: now),
        '1/10/2026',
      );
    });
  });
}
