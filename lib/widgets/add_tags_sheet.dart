import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vaulted_file.dart';
import '../providers/vault_providers.dart';
import '../themes/app_colors.dart';
import '../utils/toast_utils.dart';

/// Bottom sheet for adding tags to a set of files.
///
/// Extracted from the duplicated inline sheets in the gallery and vault
/// explorer so the media viewer can tag files too.
class AddTagsSheet extends ConsumerStatefulWidget {
  final Set<String> fileIds;
  final void Function(List<String> appliedTags)? onTagsAdded;

  const AddTagsSheet({
    super.key,
    required this.fileIds,
    this.onTagsAdded,
  });

  static Future<void> show(
    BuildContext context, {
    required Set<String> fileIds,
    void Function(List<String> appliedTags)? onTagsAdded,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => AddTagsSheet(
        fileIds: fileIds,
        onTagsAdded: onTagsAdded,
      ),
    );
  }

  @override
  ConsumerState<AddTagsSheet> createState() => _AddTagsSheetState();
}

class _AddTagsSheetState extends ConsumerState<AddTagsSheet> {
  final _tagController = TextEditingController();

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _applyTags(List<String> tags) async {
    if (tags.isEmpty) return;

    final vaultService = ref.read(vaultServiceProvider);
    for (final tag in tags) {
      await vaultService.createTag(tag);
    }

    for (final fileId in widget.fileIds) {
      for (final tag in tags) {
        await ref.read(vaultNotifierProvider.notifier).addTag(fileId, tag);
      }
    }

    ref.invalidate(tagsProvider);
    ToastUtils.showSuccess('Tag added');
    widget.onTagsAdded?.call(tags);
  }

  @override
  Widget build(BuildContext context) {
    final tagsAsync = ref.watch(tagsProvider);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: BoxDecoration(
          color: context.backgroundColor,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add Tags',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimary,
                      fontFamily: 'ProductSans',
                    ),
                  ),
                  Text(
                    '${widget.fileIds.length} file(s) selected',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.textSecondary,
                      fontFamily: 'ProductSans',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _tagController,
                    decoration: InputDecoration(
                      hintText: 'Create new tag',
                      hintStyle: TextStyle(
                        fontFamily: 'ProductSans',
                        color: context.textTertiary,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: context.accentColor),
                      ),
                      prefixIcon: Icon(Icons.label_outline,
                          color: AppColors.lightTextSecondary),
                      suffixIcon: IconButton(
                        icon: Icon(Icons.add, color: context.accentColor),
                        tooltip: 'Add tag',
                        onPressed: () async {
                          final tag = _tagController.text.trim();
                          if (tag.isEmpty) return;

                          await _applyTags([tag]);
                          if (!context.mounted) return;
                          Navigator.pop(context);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Existing Tags',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.textTertiary,
                      fontFamily: 'ProductSans',
                    ),
                  ),
                  const SizedBox(height: 8),
                  tagsAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    error: (_, __) => Text(
                      'Failed to load tags',
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        color: context.textSecondary,
                      ),
                    ),
                    data: (tags) {
                      if (tags.isEmpty) {
                        return Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text(
                              'No tags yet. Create one above!',
                              style: TextStyle(
                                fontFamily: 'ProductSans',
                                color: context.textTertiary,
                              ),
                            ),
                          ),
                        );
                      }
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: tags
                            .map((tag) => ActionChip(
                                  avatar: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: Color(tag.colorValue),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  label: Text(
                                    tag.name,
                                    style: const TextStyle(
                                      fontFamily: 'ProductSans',
                                      fontSize: 12,
                                    ),
                                  ),
                                  onPressed: () async {
                                    await _applyTags([tag.name]);
                                    if (!context.mounted) return;
                                    Navigator.pop(context);
                                  },
                                ))
                            .toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Quick Tags',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.textTertiary,
                      fontFamily: 'ProductSans',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: predefinedTags
                        .map((tag) => ActionChip(
                              label: Text(
                                tag,
                                style: const TextStyle(
                                  fontFamily: 'ProductSans',
                                  fontSize: 12,
                                ),
                              ),
                              onPressed: () async {
                                await _applyTags([tag]);
                                if (!context.mounted) return;
                                Navigator.pop(context);
                              },
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }
}
