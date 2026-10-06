import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vault_file_filter.dart';
import '../models/vaulted_file.dart';
import '../providers/vault_providers.dart';
import '../themes/app_colors.dart';

/// What the user chose in [VaultFilterSheet].
enum VaultFilterAction { apply, saveSearch }

class VaultFilterSheetResult {
  final VaultFilterAction action;
  final VaultFileFilter filter;

  const VaultFilterSheetResult(this.action, this.filter);
}

/// Bottom sheet for editing a [VaultFileFilter].
///
/// Returns the edited filter via `Navigator.pop`, or null when dismissed
/// without applying. Reused by the gallery and smart-collection editing.
class VaultFilterSheet extends ConsumerStatefulWidget {
  final VaultFileFilter initialFilter;
  final String title;
  final String applyLabel;
  final bool allowSaveSearch;

  const VaultFilterSheet({
    super.key,
    this.initialFilter = const VaultFileFilter(),
    this.title = 'Filter Files',
    this.applyLabel = 'Apply Filters',
    this.allowSaveSearch = false,
  });

  static Future<VaultFilterSheetResult?> show(
    BuildContext context, {
    VaultFileFilter initialFilter = const VaultFileFilter(),
    String title = 'Filter Files',
    String applyLabel = 'Apply Filters',
    bool allowSaveSearch = false,
  }) {
    return showModalBottomSheet<VaultFilterSheetResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => VaultFilterSheet(
        initialFilter: initialFilter,
        title: title,
        applyLabel: applyLabel,
        allowSaveSearch: allowSaveSearch,
      ),
    );
  }

  @override
  ConsumerState<VaultFilterSheet> createState() => _VaultFilterSheetState();
}

class _VaultFilterSheetState extends ConsumerState<VaultFilterSheet> {
  late VaultFileFilter _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialFilter;
  }

  void _update(VaultFileFilter Function(VaultFileFilter) change) {
    setState(() => _draft = change(_draft));
  }

  VaultFileFilter _normalizedDraft() {
    var result = _draft;
    final from = result.dateFrom;
    final to = result.dateTo;
    if (from != null && to != null && from.isAfter(to)) {
      result = result.copyWith(dateFrom: to, dateTo: from);
    }
    return result;
  }

  void _apply() {
    Navigator.of(context).pop(
        VaultFilterSheetResult(VaultFilterAction.apply, _normalizedDraft()));
  }

  void _saveSearch() {
    Navigator.of(context).pop(VaultFilterSheetResult(
        VaultFilterAction.saveSearch, _normalizedDraft()));
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final current = isFrom ? _draft.dateFrom : _draft.dateTo;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null) return;
    _update((f) => isFrom
        ? f.copyWith(dateFrom: VaultFileFilter.dayOf(picked))
        : f.copyWith(dateTo: VaultFileFilter.dayOf(picked)));
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  @override
  Widget build(BuildContext context) {
    final tags = ref.watch(tagsProvider).value ?? const [];

    return Container(
      decoration: BoxDecoration(
        color: context.backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimary,
                      fontFamily: 'ProductSans',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader('Type'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: VaultedFileType.values.map((type) {
                      final selected = _draft.type == type;
                      return FilterChip(
                        label: Text(type.displayName),
                        selected: selected,
                        onSelected: (_) => _update((f) => selected
                            ? f.copyWith(clearType: true)
                            : f.copyWith(type: type)),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  _sectionHeader('Quick Filters'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('Favorites'),
                        selected: _draft.isFavorite == true,
                        onSelected: (selected) => _update((f) => f.copyWith(
                            isFavorite: selected ? true : null,
                            clearIsFavorite: !selected)),
                      ),
                      FilterChip(
                        label: const Text('Untagged'),
                        selected: _draft.onlyUntagged,
                        onSelected: (selected) =>
                            _update((f) => f.copyWith(onlyUntagged: selected)),
                      ),
                      ChoiceChip(
                        label: const Text('Encrypted'),
                        selected: _draft.isEncrypted == true,
                        onSelected: (selected) => _update((f) => f.copyWith(
                            isEncrypted: selected ? true : null,
                            clearIsEncrypted: !selected)),
                      ),
                      ChoiceChip(
                        label: const Text('Unencrypted'),
                        selected: _draft.isEncrypted == false,
                        onSelected: (selected) => _update((f) => f.copyWith(
                            isEncrypted: selected ? false : null,
                            clearIsEncrypted: !selected)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _sectionHeader('Added Date'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _dateButton(
                          label: 'From',
                          date: _draft.dateFrom,
                          onPick: () => _pickDate(isFrom: true),
                          onClear: () =>
                              _update((f) => f.copyWith(clearDateFrom: true)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _dateButton(
                          label: 'To',
                          date: _draft.dateTo,
                          onPick: () => _pickDate(isFrom: false),
                          onClear: () =>
                              _update((f) => f.copyWith(clearDateTo: true)),
                        ),
                      ),
                    ],
                  ),
                  if (_draft.dateFrom != null || _draft.dateTo != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Both days are included. Files added on either day match.',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textTertiary,
                        fontFamily: 'ProductSans',
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _sectionHeader('Tags'),
                  const SizedBox(height: 8),
                  if (tags.isEmpty)
                    Text(
                      'No tags yet. Add tags to files to filter by them.',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.textSecondary,
                        fontFamily: 'ProductSans',
                      ),
                    )
                  else ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: tags.map((tag) {
                        final selected = _draft.tags.contains(tag.name);
                        return FilterChip(
                          label: Text(tag.name),
                          selected: selected,
                          onSelected: (isSelected) => _update((f) => f.copyWith(
                                tags: isSelected
                                    ? [...f.tags, tag.name]
                                    : f.tags
                                        .where((t) => t != tag.name)
                                        .toList(),
                              )),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Files must have every selected tag.',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textTertiary,
                        fontFamily: 'ProductSans',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              MediaQuery.of(context).padding.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(
                          () => _draft = VaultFileFilter(
                            nameQuery: _draft.nameQuery,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Reset'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _apply,
                        style: FilledButton.styleFrom(
                          backgroundColor: context.accentColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(widget.applyLabel),
                      ),
                    ),
                  ],
                ),
                if (widget.allowSaveSearch) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _saveSearch,
                    icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                    label: const Text('Save as Collection'),
                    style: TextButton.styleFrom(
                      foregroundColor: context.accentColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: context.textSecondary,
        fontFamily: 'ProductSans',
      ),
    );
  }

  Widget _dateButton({
    required String label,
    required DateTime? date,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: context.backgroundSecondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.borderColor),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 16, color: context.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.textTertiary,
                      fontFamily: 'ProductSans',
                    ),
                  ),
                  Text(
                    date == null ? 'Any' : _formatDate(date),
                    style: TextStyle(
                      fontSize: 14,
                      color: context.textPrimary,
                      fontFamily: 'ProductSans',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (date != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close, size: 16, color: context.textTertiary),
              ),
          ],
        ),
      ),
    );
  }
}
