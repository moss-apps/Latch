import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/vault_folder.dart';
import '../providers/vault_providers.dart';
import '../providers/explorer_providers.dart';
import '../themes/app_colors.dart';

class FolderBreadcrumbWidget extends ConsumerWidget {
  const FolderBreadcrumbWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentId = ref.watch(explorerCurrentFolderIdProvider);
    final foldersAsync = ref.watch(foldersProvider);

    return foldersAsync.when(
      loading: () => const SizedBox(height: 48),
      error: (_, __) => const SizedBox(height: 48),
      data: (allFolders) {
        // Resolve path to current folder
        final path = <VaultFolder>[];
        String? tempId = currentId;

        while (tempId != null) {
          final match = allFolders.where((f) => f.id == tempId);
          if (match.isEmpty) break;
          final folder = match.first;
          path.insert(0, folder);
          tempId = folder.parentId;
        }

        return Container(
          height: 48,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: context.backgroundSecondary.withValues(alpha: 0.5),
            border: Border(
              bottom: BorderSide(
                color: context.borderColor,
                width: 1,
              ),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // "My Vault" (Root Segment)
                _buildBreadcrumbSegment(
                  context,
                  ref,
                  title: 'My Vault',
                  id: null,
                  isLast: path.isEmpty,
                ),

                // Folder segments
                ...path.asMap().entries.map((entry) {
                  final index = entry.key;
                  final folder = entry.value;
                  final isLast = index == path.length - 1;

                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: context.textTertiary,
                        ),
                      ),
                      _buildBreadcrumbSegment(
                        context,
                        ref,
                        title: folder.name,
                        id: folder.id,
                        isLast: isLast,
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBreadcrumbSegment(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String? id,
    required bool isLast,
  }) {
    return InkWell(
      onTap: isLast
          ? null
          : () {
              ref.read(explorerCurrentFolderIdProvider.notifier).state = id;
            },
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          title,
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontSize: 13,
            fontWeight: isLast ? FontWeight.bold : FontWeight.w500,
            color: isLast
                ? context.textPrimary
                : context.accentColor,
          ),
        ),
      ),
    );
  }
}

// Custom helper alignment class to bypass standard Alignment center vertical limitations
class CenterPlayAlign {
  static const Alignment center = Alignment(0.0, 0.0);
}
