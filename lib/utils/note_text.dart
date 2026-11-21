/// Text helpers shared by the note list, previews, and search.
///
/// These are deliberately pure so they can be unit-tested without the vault.
library;

final RegExp _headingPattern = RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true);
final RegExp _blockquotePattern = RegExp(r'^\s*>\s?', multiLine: true);
final RegExp _taskPattern = RegExp(
  r'^\s*[-*+]\s+\[[ xX]\]\s+',
  multiLine: true,
);
final RegExp _bulletPattern = RegExp(r'^\s*[-*+]\s+', multiLine: true);
final RegExp _orderedPattern = RegExp(r'^\s*\d+[.)]\s+', multiLine: true);
final RegExp _imagePattern = RegExp(r'!\[([^\]]*)\]\([^)]*\)');
final RegExp _linkPattern = RegExp(r'\[([^\]]+)\]\([^)]*\)');
final RegExp _inlineMarks = RegExp(r'\*\*|__|~~|`|\*|_');
final RegExp _excessNewlines = RegExp(r'\n{3,}');

/// A display title for a note.
///
/// An explicit title always wins. Otherwise the first non-empty line of the
/// body is used, so notes can be written without a separate title step.
String deriveNoteTitle(
  String title,
  String content, {
  int maxLength = 120,
  bool isMarkdown = true,
}) {
  final explicit = title.trim();
  if (explicit.isNotEmpty) return explicit;

  for (final line in content.split('\n')) {
    final cleaned = isMarkdown ? _stripMarkdownLine(line) : line.trim();
    if (cleaned.isNotEmpty) {
      return _truncate(cleaned, maxLength);
    }
  }
  return '';
}

/// A readable body preview without Markdown punctuation.
String notePreviewText(
  String content, {
  int maxLength = 320,
  bool isMarkdown = true,
}) {
  if (content.trim().isEmpty) return '';
  if (!isMarkdown) return _truncate(content.trim(), maxLength);

  var text = content.replaceAll('\r\n', '\n');
  text = text.replaceAllMapped(_imagePattern, (match) => match.group(1) ?? '');
  text = text.replaceAllMapped(_linkPattern, (match) => match.group(1) ?? '');
  text = text.replaceAll(_headingPattern, '');
  text = text.replaceAll(_blockquotePattern, '');
  text = text.replaceAll(_taskPattern, '');
  text = text.replaceAll(_bulletPattern, '• ');
  text = text.replaceAll(_orderedPattern, '• ');
  text = text.replaceAll('```', '');
  text = text.replaceAll(_inlineMarks, '');
  text = text.replaceAll(_excessNewlines, '\n\n').trim();

  return _truncate(text, maxLength);
}

/// True when every word in [query] appears in the note's title or body.
///
/// Encrypted notes are searched by title only because their body is not in
/// the plaintext index.
bool noteMatchesQuery(String query, String title, String? content) {
  final terms = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty);
  if (terms.isEmpty) return true;

  final haystack = '$title\n${content ?? ''}'.toLowerCase();
  return terms.every(haystack.contains);
}

String _stripMarkdownLine(String line) {
  return line
      .replaceAll(_headingPattern, '')
      .replaceAll(_blockquotePattern, '')
      .replaceAll(_taskPattern, '')
      .replaceAll(_bulletPattern, '')
      .replaceAll(_orderedPattern, '')
      .replaceAllMapped(_imagePattern, (match) => match.group(1) ?? '')
      .replaceAllMapped(_linkPattern, (match) => match.group(1) ?? '')
      .replaceAll(_inlineMarks, '')
      .trim();
}

String _truncate(String text, int maxLength) {
  if (text.length <= maxLength) return text;
  if (maxLength <= 0) return '';
  // Don't split a UTF-16 surrogate pair at the preview boundary.
  final boundary = text.codeUnitAt(maxLength - 1);
  final end =
      boundary >= 0xd800 && boundary <= 0xdbff ? maxLength - 1 : maxLength;
  final cut = text.substring(0, end);
  final lastSpace = cut.lastIndexOf(' ');
  final safeCut =
      lastSpace > maxLength * 0.6 ? cut.substring(0, lastSpace) : cut;
  return '${safeCut.trimRight()}…';
}

/// Compact relative date used on note cards.
String formatNoteDate(DateTime date, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final diff = reference.difference(date);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${date.day}/${date.month}/${date.year}';
}
