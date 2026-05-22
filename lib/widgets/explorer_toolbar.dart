import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/album.dart';
import '../providers/vault_providers.dart';
import '../providers/explorer_providers.dart';
import '../themes/app_colors.dart';

class ExplorerToolbar extends ConsumerWidget {
  const ExplorerToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewMode = ref.watch(explorerViewModeProvider);
    final currentFolderId = ref.watch(explorerCurrentFolderIdProvider);
    final currentFolderAsync = ref.watch(explorerCurrentFolderProvider);
    final sortOption = ref.watch(sortOptionProvider);

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: context.borderColor.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left portion: Up Directory Button (only if inside subfolder in Grid mode)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (currentFolderId != null && viewMode == ExplorerViewMode.navigation)
                currentFolderAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (folder) {
                    if (folder == null) return const SizedBox.shrink();
                    return TextButton.icon(
                      onPressed: () {
                        ref.read(explorerCurrentFolderIdProvider.notifier).state = folder.parentId;
                      },
                      icon: Icon(Icons.arrow_upward, size: 16, color: context.accentColor),
                      label: Text(
                        'Up',
                        style: TextStyle(
                          fontFamily: 'ProductSans',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.accentColor,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    );
                  },
                ),
            ],
          ),

          // Right portion: View mode and Sorting options
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // View Mode Toggle
              IconButton(
                icon: Icon(
                  viewMode == ExplorerViewMode.navigation
                      ? Icons.account_tree_outlined
                      : Icons.grid_view_outlined,
                  size: 20,
                  color: context.textSecondary,
                ),
                tooltip: viewMode == ExplorerViewMode.navigation
                    ? 'Switch to Sidebar Tree'
                    : 'Switch to Grid Navigation',
                onPressed: () {
                  final newMode = viewMode == ExplorerViewMode.navigation
                      ? ExplorerViewMode.sidebar
                      : ExplorerViewMode.navigation;
                  ref.read(explorerViewModeProvider.notifier).state = newMode;
                },
              ),

              const SizedBox(width: 8),

              // Sorting Button (Popup Menu)
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
                          color: isSelected ? context.accentColor : context.textSecondary,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          option.displayName,
                          style: TextStyle(
                            fontFamily: 'ProductSans',
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? context.accentColor : context.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ],
      ),
    );
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
