import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  String? _markdown;

  @override
  void initState() {
    super.initState();
    _loadMarkdown();
  }

  Future<void> _loadMarkdown() async {
    try {
      final content = await rootBundle.loadString('assets/privacy_policy.md');
      if (mounted) {
        setState(() => _markdown = content);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _markdown = 'Failed to load privacy policy.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFFFFFFF),
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: _textPrimary(isDark)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Privacy Policy',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: _textPrimary(isDark),
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _markdown == null
          ? Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
          : Markdown(
              data: _markdown!,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              styleSheet: MarkdownStyleSheet(
                h1: TextStyle(
                  fontFamily: 'ProductSans',
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary(isDark),
                ),
                h2: TextStyle(
                  fontFamily: 'ProductSans',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _textPrimary(isDark),
                ),
                p: TextStyle(
                  fontFamily: 'ProductSans',
                  fontSize: 14,
                  color: _textSecondary(isDark),
                  height: 1.5,
                ),
                strong: TextStyle(
                  fontFamily: 'ProductSans',
                  fontWeight: FontWeight.w600,
                  color: _textPrimary(isDark),
                ),
                listBullet: TextStyle(
                  fontFamily: 'ProductSans',
                  fontSize: 14,
                  color: _textSecondary(isDark),
                ),
                listBulletPadding: const EdgeInsets.symmetric(horizontal: 8),
                blockquote: TextStyle(
                  fontFamily: 'ProductSans',
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: _textSecondary(isDark),
                ),
                blockquoteDecoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                      width: 3,
                    ),
                  ),
                ),
                code: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  backgroundColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F0F0),
                  color: _textPrimary(isDark),
                ),
                horizontalRuleDecoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: isDark ? const Color(0xFF333333) : const Color(0xFFE0E0E0),
                      width: 1,
                    ),
                  ),
                ),
              ),
              selectable: true,
            ),
    );
  }

  Color _textPrimary(bool isDark) => isDark ? const Color(0xFFE5E5E5) : const Color(0xFF1A1A1A);
  Color _textSecondary(bool isDark) => isDark ? const Color(0xFFA0A0A0) : const Color(0xFF555555);
}
