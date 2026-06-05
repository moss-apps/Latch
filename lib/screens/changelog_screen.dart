import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../themes/app_colors.dart';

/// Full changelog viewer. Renders the bundled `CHANGELOG.md` asset and
/// is reachable from the "What's New" bottom sheet and vault settings.
class ChangelogScreen extends StatefulWidget {
  const ChangelogScreen({super.key});

  @override
  State<ChangelogScreen> createState() => _ChangelogScreenState();
}

class _ChangelogScreenState extends State<ChangelogScreen> {
  String? _markdown;

  @override
  void initState() {
    super.initState();
    _loadMarkdown();
  }

  Future<void> _loadMarkdown() async {
    try {
      final content = await rootBundle.loadString('CHANGELOG.md');
      if (mounted) setState(() => _markdown = content);
    } catch (_) {
      if (mounted) setState(() => _markdown = 'Failed to load changelog.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Changelog',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _markdown == null
          ? Center(
              child: CircularProgressIndicator(color: context.accentColor),
            )
          : Markdown(
              data: _markdown!,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              styleSheet: _styleSheet(context),
              selectable: true,
            ),
    );
  }

  MarkdownStyleSheet _styleSheet(BuildContext context) {
    final isDark = context.isDarkMode;
    return MarkdownStyleSheet(
      h1: TextStyle(
        fontFamily: 'ProductSans',
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: context.textPrimary,
      ),
      h2: TextStyle(
        fontFamily: 'ProductSans',
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: context.textPrimary,
      ),
      h3: TextStyle(
        fontFamily: 'ProductSans',
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: context.accentColor,
      ),
      p: TextStyle(
        fontFamily: 'ProductSans',
        fontSize: 14,
        color: context.textSecondary,
        height: 1.5,
      ),
      strong: TextStyle(
        fontFamily: 'ProductSans',
        fontWeight: FontWeight.w600,
        color: context.textPrimary,
      ),
      listBullet: TextStyle(
        fontFamily: 'ProductSans',
        fontSize: 14,
        color: context.textSecondary,
      ),
      listBulletPadding: const EdgeInsets.symmetric(horizontal: 8),
      blockquote: TextStyle(
        fontFamily: 'ProductSans',
        fontSize: 14,
        fontStyle: FontStyle.italic,
        color: context.textSecondary,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: context.accentColor.withValues(alpha: 0.3),
            width: 3,
          ),
        ),
      ),
      code: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        backgroundColor:
            isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F0F0),
        color: context.textPrimary,
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: context.dividerColor, width: 1),
        ),
      ),
    );
  }
}
