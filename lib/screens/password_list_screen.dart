import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/password_entry.dart';
import '../providers/password_providers.dart';
import '../themes/app_colors.dart';
import '../utils/toast_utils.dart';
import '../widgets/password_card.dart';
import 'password_editor_screen.dart';

class PasswordListScreen extends ConsumerStatefulWidget {
  const PasswordListScreen({super.key});

  @override
  ConsumerState<PasswordListScreen> createState() =>
      _PasswordListScreenState();
}

class _PasswordListScreenState extends ConsumerState<PasswordListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;
  bool _showAutofillInfo = false;

  @override
  void initState() {
    super.initState();
    _loadAutofillInfoState();
  }

  Future<void> _loadAutofillInfoState() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _showAutofillInfo =
            !(prefs.getBool('autofill_info_dismissed') ?? false);
      });
    }
  }

  Future<void> _dismissAutofillInfo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autofill_info_dismissed', true);
    setState(() => _showAutofillInfo = false);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchQuery = ref.watch(passwordSearchQueryProvider);
    final entriesAsync = ref.watch(passwordsNotifierProvider);

    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: _isSelectionMode
          ? _buildSelectionAppBar()
          : AppBar(
              backgroundColor: context.backgroundColor,
              elevation: 0,
              title: Text(
                'Passwords',
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                ref.read(passwordSearchQueryProvider.notifier).state = value;
              },
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: context.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Search passwords',
                hintStyle: TextStyle(
                  fontFamily: 'ProductSans',
                  color: context.textTertiary,
                ),
                prefixIcon:
                    Icon(Icons.search, size: 20, color: context.textTertiary),
                isDense: true,
                filled: true,
                fillColor: context.surfaceColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.accentColor),
                ),
              ),
            ),
          ),
          if (_showAutofillInfo) _buildAutofillInfoCard(),
          Expanded(
            child: entriesAsync.when(
              data: (entries) {
                final filtered = _filterPasswords(entries, searchQuery);
                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 48,
                          color: context.textTertiary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          searchQuery.isNotEmpty
                              ? 'No passwords found'
                              : 'No passwords yet',
                          style: TextStyle(
                            fontFamily: 'ProductSans',
                            fontSize: 15,
                            color: context.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: context.dividerColor,
                  ),
                  itemBuilder: (context, index) {
                    final entry = filtered[index];
                    return PasswordCard(
                      entry: entry,
                      isSelected: _selectedIds.contains(entry.id),
                      isSelectionMode: _isSelectionMode,
                      onTap: () {
                        if (_isSelectionMode) {
                          setState(() {
                            if (_selectedIds.contains(entry.id)) {
                              _selectedIds.remove(entry.id);
                              if (_selectedIds.isEmpty) {
                                _isSelectionMode = false;
                              }
                            } else {
                              _selectedIds.add(entry.id);
                            }
                          });
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  PasswordEditorScreen(entry: entry),
                            ),
                          );
                        }
                      },
                      onLongPress: () {
                        if (!_isSelectionMode) {
                          setState(() {
                            _isSelectionMode = true;
                            _selectedIds.add(entry.id);
                          });
                        }
                      },
                    );
                  },
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Text(
                  'Error loading passwords',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    color: context.textTertiary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _isSelectionMode
          ? null
          : FloatingActionButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PasswordEditorScreen(),
                ),
              ),
              backgroundColor: context.accentColor,
              elevation: 0,
              child: const Icon(Icons.add, color: Colors.white),
            ),
    );
  }

  Widget _buildAutofillInfoCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: context.accentColor.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome, color: context.accentColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Autofill is available',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.accentColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Enable in Android Settings to fill logins in any app:\n'
                  'Settings → Passwords & accounts → Autofill service → Latch',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 12,
                    color: context.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 16, color: context.textTertiary),
            onPressed: _dismissAutofillInfo,
            tooltip: 'Dismiss',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildSelectionAppBar() {
    return AppBar(
      backgroundColor: context.backgroundColor,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.close, color: context.textPrimary),
        onPressed: () {
          setState(() {
            _isSelectionMode = false;
            _selectedIds.clear();
          });
        },
      ),
      title: Text(
        '${_selectedIds.length} selected',
        style: TextStyle(
          fontFamily: 'ProductSans',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: context.textPrimary,
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.delete_outline, color: AppColors.error),
          onPressed: _showDeleteConfirmation,
        ),
      ],
    );
  }

  List<PasswordEntry> _filterPasswords(
    List<PasswordEntry> entries,
    String searchQuery,
  ) {
    var filtered = entries;
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      filtered = filtered
          .where((e) =>
              e.title.toLowerCase().contains(query) ||
              e.tags.any((t) => t.contains(query)))
          .toList();
    }
    filtered.sort((a, b) {
      if (a.isFavorite && !b.isFavorite) return -1;
      if (!a.isFavorite && b.isFavorite) return 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return filtered;
  }

  Future<void> _showDeleteConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.surfaceColor,
        title: Text(
          'Delete Passwords',
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
        ),
        content: Text(
          'Delete ${_selectedIds.length} entry(s)? This cannot be undone.',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: context.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final entriesAsync = ref.read(passwordsNotifierProvider);
      entriesAsync.whenData((entries) async {
        final toDelete =
            entries.where((e) => _selectedIds.contains(e.id)).toList();
        await ref.read(passwordsNotifierProvider.notifier).deletePasswords(toDelete);
        if (mounted) {
          setState(() {
            _isSelectionMode = false;
            _selectedIds.clear();
          });
          ToastUtils.showSuccess('Passwords deleted');
        }
      });
    }
  }
}
