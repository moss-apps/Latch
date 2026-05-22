import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/vault_folder.dart';
import '../providers/vault_providers.dart';
import '../providers/explorer_providers.dart';
import '../themes/app_colors.dart';

class FolderTreeWidget extends ConsumerStatefulWidget {
  final void Function(VaultFolder folder)? onFolderLongPress;

  const FolderTreeWidget({
    super.key,
    this.onFolderLongPress,
  });

  @override
  ConsumerState<FolderTreeWidget> createState() => _FolderTreeWidgetState();
}

class _FolderTreeWidgetState extends ConsumerState<FolderTreeWidget> {
  // Keeps track of which folders are expanded
  final Set<String> _expandedFolderIds = {};

  void _toggleExpand(String folderId) {
    setState(() {
      if (_expandedFolderIds.contains(folderId)) {
        _expandedFolderIds.remove(folderId);
      } else {
        _expandedFolderIds.add(folderId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentSelectedId = ref.watch(explorerCurrentFolderIdProvider);
    final rootFoldersAsync = ref.watch(rootFoldersProvider);

    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: context.borderColor,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Root of the Vault Tree
          _buildRootTile(currentSelectedId),
          const Divider(height: 1, thickness: 1),
          Expanded(
            child: rootFoldersAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Failed to load folders',
                    style: TextStyle(
                      fontFamily: 'ProductSans',
                      color: context.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              data: (rootFolders) {
                if (rootFolders.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'No folders created yet.',
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        color: context.textTertiary,
                        fontSize: 13,
                      ),
                    ),
                  );
                }

                // Sort root folders alphabetically
                final sortedRoots = List<VaultFolder>.from(rootFolders)
                  ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: sortedRoots.length,
                  itemBuilder: (context, index) {
                    return _buildFolderNode(
                      folder: sortedRoots[index],
                      depth: 0,
                      currentSelectedId: currentSelectedId,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRootTile(String? currentSelectedId) {
    final isSelected = currentSelectedId == null;

    return InkWell(
      onTap: () {
        ref.read(explorerCurrentFolderIdProvider.notifier).state = null;
      },
      child: Container(
        color: isSelected ? context.accentColor.withValues(alpha: 0.1) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.shield_outlined,
              color: isSelected ? context.accentColor : context.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'My Vault',
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? context.accentColor : context.textPrimary,
                  fontSize: 14,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: context.accentColor,
                size: 14,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderNode({
    required VaultFolder folder,
    required int depth,
    required String? currentSelectedId,
  }) {
    final isSelected = currentSelectedId == folder.id;
    final isExpanded = _expandedFolderIds.contains(folder.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Folder item itself
        InkWell(
          onTap: () {
            ref.read(explorerCurrentFolderIdProvider.notifier).state = folder.id;
          },
          onLongPress: widget.onFolderLongPress != null
              ? () => widget.onFolderLongPress!(folder)
              : null,
          child: Container(
            color: isSelected ? context.accentColor.withValues(alpha: 0.1) : Colors.transparent,
            padding: EdgeInsets.only(
              left: 8.0 + (depth * 16.0),
              right: 16.0,
              top: 6.0,
              bottom: 6.0,
            ),
            child: Row(
              children: [
                // Expand / Collapse Chevron
                GestureDetector(
                  onTap: () => _toggleExpand(folder.id),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                    child: Icon(
                      folder.subfolderCount > 0
                          ? (isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right)
                          : Icons.fiber_manual_record,
                      size: folder.subfolderCount > 0 ? 18 : 6,
                      color: folder.subfolderCount > 0
                          ? context.textSecondary
                          : Colors.transparent, // Hide chevron area if empty
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  isExpanded ? Icons.folder_open : Icons.folder,
                  color: isSelected ? context.accentColor : context.accentColor.withValues(alpha: 0.7),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    folder.name,
                    style: TextStyle(
                      fontFamily: 'ProductSans',
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? context.accentColor : context.textPrimary,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (folder.fileCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: context.backgroundSecondary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${folder.fileCount}',
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        fontSize: 10,
                        color: context.textTertiary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Subfolders of this node (rendered recursively if expanded)
        if (isExpanded)
          Consumer(
            builder: (context, ref, child) {
              final subfoldersAsync = ref.watch(subfoldersProvider(folder.id));

              return subfoldersAsync.when(
                loading: () => Padding(
                  padding: EdgeInsets.only(left: 24.0 + (depth * 16.0), top: 4.0, bottom: 4.0),
                  child: const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1),
                  ),
                ),
                error: (error, _) => const SizedBox.shrink(),
                data: (subfolders) {
                  if (subfolders.isEmpty) return const SizedBox.shrink();

                  // Sort subfolders alphabetically
                  final sortedSubfolders = List<VaultFolder>.from(subfolders)
                    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

                  return Column(
                    children: sortedSubfolders.map((subfolder) {
                      return _buildFolderNode(
                        folder: subfolder,
                        depth: depth + 1,
                        currentSelectedId: currentSelectedId,
                      );
                    }).toList(),
                  );
                },
              );
            },
          ),
      ],
    );
  }
}
