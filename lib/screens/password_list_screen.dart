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
    final selectedTag = ref.watch(selectedPasswordTagProvider);
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
            padding: const EdgeInsets.all(16),
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
                hintText: 'Search passwords...',
                hintStyle: TextStyle(
                  fontFamily: 'ProductSans',
                  color: context.textTertiary,
                ),
                prefixIcon: Icon(Icons.search, color: context.textTertiary),
                filled: true,
                fillColor: context.surfaceColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.borderColor),
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
                final allTags = _collectTags(entries);
                final filtered =
                    _filterPasswords(entries, searchQuery, selectedTag);
                return Column(
                  children: [
                    if (allTags.isNotEmpty)
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            _buildTagChip(
                              null,
                              selectedTag == null,
                              'All',
                            ),
                            ...allTags.map((tag) =>
                                _buildTagChip(tag, selectedTag == tag, tag)),
                          ],
                        ),
                      ),
                    Expanded(
                      child: filtered.isEmpty
                          ? _buildEmptyState(searchQuery)
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final entry = filtered[index];
                                final isSelected =
                                    _selectedIds.contains(entry.id);
                                return Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 10),
                                  child: PasswordCard(
                                    entry: entry,
                                    isSelected: isSelected,
                                    onTap: () {
                                      if (_isSelectionMode) {
                                        setState(() {
                                          if (isSelected) {
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
                                                PasswordEditorScreen(
                                                    entry: entry),
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
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
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
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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

  Widget _buildTagChip(String? tag, bool isSelected, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontSize: 12,
            color: isSelected
                ? Colors.white
                : context.textSecondary,
          ),
        ),
        selected: isSelected,
        onSelected: (_) {
          ref.read(selectedPasswordTagProvider.notifier).state = tag;
        },
        selectedColor: context.accentColor,
        backgroundColor: context.surfaceColor,
        side: BorderSide(
          color: isSelected ? context.accentColor : context.borderColor,
        ),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildEmptyState(String searchQuery) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lock_outline,
            size: 64,
            color: context.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            searchQuery.isNotEmpty
                ? 'No passwords found'
                : 'No passwords yet',
            style: TextStyle(
              fontFamily: 'ProductSans',
              fontSize: 16,
              color: context.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  List<String> _collectTags(List<PasswordEntry> entries) {
    final tags = <String>{};
    for (final entry in entries) {
      tags.addAll(entry.tags);
    }
    return tags.toList()..sort();
  }

  List<PasswordEntry> _filterPasswords(
    List<PasswordEntry> entries,
    String searchQuery,
    String? selectedTag,
  ) {
    var filtered = entries;
    if (selectedTag != null) {
      filtered = filtered.where((e) => e.hasTag(selectedTag)).toList();
    }
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
