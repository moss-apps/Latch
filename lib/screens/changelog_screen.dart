import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../themes/app_colors.dart';

/// Full changelog viewer.
///
/// Fetches `CHANGELOG.md` from the GitHub repo on launch so it always
/// reflects the latest published notes. The response is cached locally and
/// the bundled asset is used as a fallback when the network is unavailable.
class ChangelogScreen extends StatefulWidget {
  const ChangelogScreen({super.key});

  @override
  State<ChangelogScreen> createState() => _ChangelogScreenState();
}

class _ChangelogScreenState extends State<ChangelogScreen> {
  static const String _cacheKey = 'changelog_cached_markdown';
  static const String _etagKey = 'changelog_cached_etag';
  static const String _remoteUrl =
      'https://raw.githubusercontent.com/moss-apps/Latch/main/CHANGELOG.md';
  static const _fetchTimeout = Duration(seconds: 8);

  String? _markdown;

  @override
  void initState() {
    super.initState();
    _loadChangelog();
  }

  Future<void> _loadChangelog() async {
    if (!mounted) return;

    // Show bundled version instantly while we fetch the latest.
    _loadBundled();

    final remote = await _fetchRemote();
    if (remote != null && mounted) {
      setState(() => _markdown = remote);
    }
  }

  void _loadBundled() {
    rootBundle.loadString('CHANGELOG.md').then((content) {
      if (mounted && _markdown == null) setState(() => _markdown = content);
    }).catchError((_) {});
  }

  Future<String?> _fetchRemote() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = _fetchTimeout;
      final prefs = await SharedPreferences.getInstance();
      final cachedEtag = prefs.getString(_etagKey);

      // Try cache first for an instant load if there is one.
      final cached = prefs.getString(_cacheKey);
      if (cached != null && _markdown == null && mounted) {
        setState(() => _markdown = cached);
      }

      final request = await client.getUrl(Uri.parse(_remoteUrl));
      if (cachedEtag != null) {
        request.headers.set(HttpHeaders.ifNoneMatchHeader, cachedEtag);
      }

      final response = await request.close().timeout(_fetchTimeout);
      client.close();

      if (response.statusCode == 304 && cached != null) return cached;
      if (response.statusCode != 200) return null;

      final body = await response.transform(utf8.decoder).join();
      if (body.trim().isEmpty) return null;

      await prefs.setString(_cacheKey, body);

      final etag = response.headers.value(HttpHeaders.etagHeader);
      if (etag != null) await prefs.setString(_etagKey, etag);

      return body;
    } catch (_) {
      return null;
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
