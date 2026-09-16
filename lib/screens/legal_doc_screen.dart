import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// Reader for a bundled legal document (EULA / Terms / Privacy).
class LegalDocScreen extends StatefulWidget {
  final String title;
  final String assetPath;

  const LegalDocScreen({
    super.key,
    required this.title,
    required this.assetPath,
  });

  @override
  State<LegalDocScreen> createState() => _LegalDocScreenState();
}

class _LegalDocScreenState extends State<LegalDocScreen> {
  String? _markdown;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final content = await rootBundle.loadString(widget.assetPath);
      if (mounted) setState(() => _markdown = content);
    } catch (_) {
      if (mounted) {
        setState(() => _markdown = 'Failed to load ${widget.title}.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? const Color(0xFFE5E5E5) : const Color(0xFF1A1A1A);
    final secondary =
        isDark ? const Color(0xFFA0A0A0) : const Color(0xFF555555);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: primary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.title,
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _markdown == null
          ? Center(
              child: CircularProgressIndicator(
                  color: Theme.of(context).colorScheme.primary))
          : Markdown(
              data: _markdown!,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              styleSheet: MarkdownStyleSheet(
                h1: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: primary),
                h2: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: primary),
                p: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 14,
                    color: secondary,
                    height: 1.5),
              ),
              selectable: true,
            ),
    );
  }
}
