import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/vault_folder.dart';
import '../providers/vault_providers.dart';
import '../providers/explorer_providers.dart';
import '../themes/app_colors.dart';

/// Compact app bar title for the file explorer.
///
/// Shows "My Vault" at the root, or the current folder name when inside a
/// folder. Tapping it opens the folder path as a menu so any ancestor (including
/// My Vault) can be opened directly, replacing the full-width breadcrumb strip.
class FolderBreadcrumbWidget extends ConsumerWidget {
  final String title;

  const FolderBreadcrumbWidget({super.key, required this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentId = ref.watch(explorerCurrentFolderIdProvider);
    final allFolders =
        ref.watch(foldersProvider).value ?? const <VaultFolder>[];
    final path = _resolvePath(allFolders, currentId);

    return PopupMenuButton<String?>(
      onSelected: (id) {
        ref.read(explorerCurrentFolderIdProvider.notifier).state = id;
      },
      offset: const Offset(0, 44),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 200),
      itemBuilder: (context) => _buildPathItems(context, path, currentId),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.45,
            ),
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'GoogleSansFlex',
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: context.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.expand_more, size: 18, color: context.textSecondary),
        ],
      ),
    );
  }

  /// Walks parent links to build the folder chain from root to current folder.
  List<VaultFolder> _resolvePath(
    List<VaultFolder> allFolders,
    String? currentId,
  ) {
    final path = <VaultFolder>[];
    String? cursor = currentId;

    while (cursor != null) {
      final index = allFolders.indexWhere((folder) => folder.id == cursor);
      if (index == -1) break;
      final folder = allFolders[index];
      path.insert(0, folder);
      cursor = folder.parentId;
    }

    return path;
  }

  List<PopupMenuEntry<String?>> _buildPathItems(
    BuildContext context,
    List<VaultFolder> path,
    String? currentId,
  ) {
    return [
      _buildPathItem(
        context,
        value: null,
        label: 'My Vault',
        depth: 0,
        isCurrent: currentId == null,
      ),
      ...path.asMap().entries.map((entry) {
        final folder = entry.value;
        return _buildPathItem(
          context,
          value: folder.id,
          label: folder.name,
          depth: entry.key + 1,
          isCurrent: folder.id == currentId,
        );
      }),
    ];
  }

  PopupMenuItem<String?> _buildPathItem(
    BuildContext context, {
    required String? value,
    required String label,
    required int depth,
    required bool isCurrent,
  }) {
    return PopupMenuItem<String?>(
      value: value,
      enabled: !isCurrent,
      child: Padding(
        padding: EdgeInsets.only(left: depth * 12.0),
        child: Row(
          children: [
            Icon(
              depth == 0 ? Icons.home_outlined : Icons.folder_outlined,
              size: 18,
              color: isCurrent ? context.accentColor : context.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'GoogleSansFlex',
                  fontSize: 13,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  color: isCurrent ? context.accentColor : context.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
