import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/album.dart';
import '../models/vaulted_file.dart';
import '../providers/vault_providers.dart';
import '../providers/explorer_providers.dart';
import '../themes/app_colors.dart';

const Map<String, VaultedFileType?> _fileTypeFilters = {
  'All': null,
  'Images': VaultedFileType.image,
  'Videos': VaultedFileType.video,
  'Songs': VaultedFileType.song,
  'Documents': VaultedFileType.document,
};

class ExplorerToolbar extends ConsumerWidget {
  const ExplorerToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewMode = ref.watch(explorerViewModeProvider);
    final currentFolderId = ref.watch(explorerCurrentFolderIdProvider);
    final sortOption = ref.watch(sortOptionProvider);
    final activeFilter = ref.watch(explorerFileTypeFilterProvider);

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: context.borderColor.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showChips = constraints.maxWidth >= 600;

          return Row(
            children: [
              if (showChips)
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final entry in _fileTypeFilters.entries)
                        _buildFilterChip(
                          ref,
                          label: entry.key,
                          value: entry.value,
                          isActive: activeFilter == entry.value,
                        ),
                    ],
                  ),
                )
              else
                _buildFilterDropdown(ref, activeFilter),
              if (!showChips) const Spacer(),
              PopupMenuButton<SortOption>(
                icon: Icon(Icons.sort, size: 20, color: context.textSecondary),
                tooltip: 'Sort Files',
                onSelected: (option) {
                  ref.read(sortOptionProvider.notifier).state = option;
                  // Invalidate current folder views to force a resort
                  if (currentFolderId != null) {
                    ref.invalidate(filesInFolderProvider(currentFolderId));
                  } else {
                    ref.invalidate(unfiledFilesProvider);
                  }
                  ref.invalidate(explorerFilesProvider);
                },
                itemBuilder: (context) => SortOption.values.map((option) {
                  final isSelected = sortOption == option;
                  return PopupMenuItem<SortOption>(
                    value: option,
                    child: Row(
                      children: [
                        Icon(
                          _getSortIcon(option),
                          size: 16,
                          color: isSelected
                              ? context.accentColor
                              : context.textSecondary,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          option.displayName,
                          style: TextStyle(
                            fontFamily: 'GoogleSansFlex',
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? context.accentColor
                                : context.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(
                  viewMode == ExplorerViewMode.list
                      ? Icons.grid_view_outlined
                      : Icons.view_list_outlined,
                  size: 20,
                  color: context.textSecondary,
                ),
                tooltip: viewMode == ExplorerViewMode.list
                    ? 'Switch to Grid View'
                    : 'Switch to List View',
                onPressed: () {
                  final newMode = viewMode == ExplorerViewMode.list
                      ? ExplorerViewMode.grid
                      : ExplorerViewMode.list;
                  ref.read(explorerViewModeProvider.notifier).state = newMode;
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterDropdown(WidgetRef ref, VaultedFileType? activeFilter) {
    final context = ref.context;

    return PopupMenuButton<VaultedFileType?>(
      onSelected: (value) {
        ref.read(explorerFileTypeFilterProvider.notifier).state = value;
      },
      offset: const Offset(0, 40),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 180),
      itemBuilder: (context) => [
        for (final entry in _fileTypeFilters.entries)
          PopupMenuItem<VaultedFileType?>(
            value: entry.value,
            child: Row(
              children: [
                Icon(
                  entry.value == activeFilter
                      ? Icons.check
                      : Icons.circle_outlined,
                  size: 16,
                  color: entry.value == activeFilter
                      ? context.accentColor
                      : context.textSecondary,
                ),
                const SizedBox(width: 12),
                Text(
                  entry.key,
                  style: TextStyle(
                    fontFamily: 'GoogleSansFlex',
                    fontSize: 13,
                    fontWeight: entry.value == activeFilter
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: entry.value == activeFilter
                        ? context.accentColor
                        : context.textPrimary,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: context.backgroundSecondary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: context.borderColor.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _labelForFilter(activeFilter),
              style: TextStyle(
                fontFamily: 'GoogleSansFlex',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more, size: 16, color: context.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(
    WidgetRef ref, {
    required String label,
    required VaultedFileType? value,
    required bool isActive,
  }) {
    final context = ref.context;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontFamily: 'GoogleSansFlex',
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            color: isActive ? Colors.white : context.textPrimary,
            fontSize: 12,
          ),
        ),
        selected: isActive,
        onSelected: (_) {
          ref.read(explorerFileTypeFilterProvider.notifier).state = value;
        },
        selectedColor: context.accentColor,
        backgroundColor: context.backgroundSecondary,
        checkmarkColor: Colors.white,
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isActive
                ? context.accentColor
                : context.borderColor.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
    );
  }

  String _labelForFilter(VaultedFileType? filter) {
    for (final entry in _fileTypeFilters.entries) {
      if (entry.value == filter) return entry.key;
    }
    return 'All';
  }

  IconData _getSortIcon(SortOption option) {
    switch (option) {
      case SortOption.nameAsc:
        return Icons.sort_by_alpha;
      case SortOption.nameDesc:
        return Icons.sort_by_alpha;
      case SortOption.dateAddedNewest:
      case SortOption.dateAddedOldest:
      case SortOption.dateModifiedNewest:
      case SortOption.dateModifiedOldest:
        return Icons.calendar_today;
      case SortOption.sizeSmallest:
      case SortOption.sizeLargest:
        return Icons.scale;
      case SortOption.typeAsc:
      case SortOption.typeDesc:
        return Icons.category;
    }
  }
}
