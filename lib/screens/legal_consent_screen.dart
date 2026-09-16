import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../services/legal_consent_service.dart';
import '../themes/app_colors.dart';

/// First-run gate: the user must read and accept the EULA / Terms / Privacy
/// (versioned in legal/version.txt, mirrored in LegalConsentService) before
/// reaching auth setup or unlock. Shown from AppInitializer when the stored
/// acceptance is stale; [onAccepted] returns to the normal flow.
class LegalConsentScreen extends StatefulWidget {
  final VoidCallback onAccepted;

  const LegalConsentScreen({super.key, required this.onAccepted});

  @override
  State<LegalConsentScreen> createState() => _LegalConsentScreenState();
}

class _LegalConsentScreenState extends State<LegalConsentScreen>
    with SingleTickerProviderStateMixin {
  static const _docs = [
    ('License Agreement', 'legal/eula.md'),
    ('Terms', 'legal/terms.md'),
    ('Privacy Policy', 'legal/privacy.md'),
  ];

  late final TabController _tabs = TabController(length: _docs.length, vsync: this);
  String? _markdown;
  bool _accepting = false;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_loadActive);
    _loadActive();
  }

  @override
  void dispose() {
    _tabs.removeListener(_loadActive);
    _tabs.dispose();
    super.dispose();
  }

  void _loadActive() {
    if (_tabs.indexIsChanging) return;
    _load(_docs[_tabs.index].$2);
  }

  Future<void> _load(String asset) async {
    setState(() => _markdown = null);
    try {
      final content = await rootBundle.loadString(asset);
      if (mounted) setState(() => _markdown = content);
    } catch (_) {
      if (mounted) {
        setState(() => _markdown = 'Failed to load this document.');
      }
    }
  }

  Future<void> _accept() async {
    setState(() => _accepting = true);
    try {
      await LegalConsentService().accept();
      widget.onAccepted();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not record acceptance.')),
        );
      }
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: context.backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Text(
                'Before you use Latch',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                  fontFamily: 'ProductSans',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Latch is local-first encrypted storage. Read the terms, then accept to continue. No accounts, no tracking.',
                style: TextStyle(
                  fontSize: 14,
                  color: context.textSecondary,
                  fontFamily: 'ProductSans',
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelStyle: const TextStyle(
                    fontFamily: 'ProductSans', fontWeight: FontWeight.w600),
                tabs: [for (final d in _docs) Tab(text: d.$1)],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.borderColor),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _markdown == null
                      ? Center(
                          child: CircularProgressIndicator(
                              color: context.accentColor))
                      : Markdown(
                          data: _markdown!,
                          padding: const EdgeInsets.all(16),
                          selectable: true,
                        ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _accepting ? null : _accept,
                  child: Text(_accepting ? 'Accepting…' : 'I accept'),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Version ${LegalConsentService.legalVersion} · re-asked on change',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textTertiary,
                    fontFamily: 'ProductSans',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
