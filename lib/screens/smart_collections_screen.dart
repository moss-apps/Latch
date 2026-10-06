import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/smart_collection.dart';
import '../providers/smart_collection_providers.dart';
import '../themes/app_colors.dart';
import '../utils/toast_utils.dart';
import '../widgets/vault_filter_sheet.dart';
import 'smart_collection_screen.dart';

/// Prompts for a collection name. Returns null when cancelled or blank.
Future<String?> showSmartCollectionNameDialog(
  BuildContext context, {
  String title = 'New Collection',
  String? initialName,
  String actionLabel = 'Save',
}) async {
  final controller = TextEditingController(text: initialName ?? '');
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: Theme.of(dialogContext).scaffoldBackgroundColor,
      title: Text(
        title,
        style: TextStyle(
          fontFamily: 'ProductSans',
          color: dialogContext.textPrimary,
        ),
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        style: TextStyle(
          fontFamily: 'ProductSans',
          color: dialogContext.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: 'Collection name',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onSubmitted: (value) {
          final name = value.trim();
          if (name.isNotEmpty) Navigator.pop(dialogContext, name);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(
            'Cancel',
            style: TextStyle(
              fontFamily: 'ProductSans',
              color: dialogContext.textSecondary,
            ),
          ),
        ),
        TextButton(
          onPressed: () {
            final name = controller.text.trim();
            if (name.isNotEmpty) Navigator.pop(dialogContext, name);
          },
          child: Text(
            actionLabel,
            style: TextStyle(
              fontFamily: 'ProductSans',
              color: dialogContext.accentColor,
            ),
          ),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

/// Lists preset and custom smart collections with live file counts.
class SmartCollectionsScreen extends ConsumerWidget {
  const SmartCollectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collectionsAsync = ref.watch(smartCollectionsProvider);
    final counts =
        ref.watch(smartCollectionCountsProvider).value ?? const <String, int>{};

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: context.textPrimary,
        elevation: 0,
        title: Text(
          'Smart Collections',
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        elevation: 0,
        onPressed: () => _createCollection(context, ref),
        backgroundColor: context.accentColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'New Collection',
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: collectionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _buildError(context, ref),
        data: (collections) =>
            _buildList(context, ref, collections, counts),
      ),
    );
  }

  Widget _buildError(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline,
              size: 64, color: AppColors.lightTextTertiary),
          const SizedBox(height: 16),
          Text(
            'Failed to load collections',
            style: TextStyle(
              fontFamily: 'ProductSans',
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => ref.read(smartCollectionsProvider.notifier).reload(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    List<SmartCollection> collections,
    Map<String, int> counts,
  ) {
    final presets = collections.where((c) => c.isPreset).toList();
    final custom = collections.where((c) => c.isCustom).toList();

    return RefreshIndicator(
      onRefresh: () => ref.read(smartCollectionsProvider.notifier).reload(),
      color: context.accentColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _sectionHeader(context, 'Presets'),
          ...presets.map(
            (collection) => _collectionCard(
              context,
              ref,
              collection,
              counts[collection.id] ?? 0,
            ),
          ),
          const SizedBox(height: 20),
          _sectionHeader(context, 'My Collections'),
          if (custom.isEmpty)
            _emptyHint(context)
          else
            ...custom.map(
              (collection) => _collectionCard(
                context,
                ref,
                collection,
                counts[collection.id] ?? 0,
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: context.textSecondary,
          fontFamily: 'ProductSans',
        ),
      ),
    );
  }

  Widget _emptyHint(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.auto_awesome_outlined,
              size: 48, color: context.textTertiary),
          const SizedBox(height: 12),
          Text(
            'No saved collections yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
              fontFamily: 'ProductSans',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Save a filter from the gallery or create one here.',
            style: TextStyle(
              fontSize: 13,
              color: context.textSecondary,
              fontFamily: 'ProductSans',
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _collectionCard(
    BuildContext context,
    WidgetRef ref,
    SmartCollection collection,
    int count,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: context.backgroundSecondary,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  SmartCollectionScreen(collectionId: collection.id),
            ),
          );
        },
        onLongPress: () => _showOptions(context, ref, collection),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: context.accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _iconFor(collection),
                  color: context.accentColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      collection.name,
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$count ${count == 1 ? 'file' : 'files'} · ${_describeFilter(collection)}',
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        fontSize: 12,
                        color: context.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.more_vert, color: context.textTertiary),
                tooltip: 'Options',
                onPressed: () => _showOptions(context, ref, collection),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(SmartCollection collection) {
    switch (collection.id) {
      case 'preset_untagged':
        return Icons.label_off_outlined;
      case 'preset_unencrypted':
        return Icons.lock_open_outlined;
      case 'preset_large_videos':
        return Icons.video_library_outlined;
      case 'preset_added_this_month':
        return Icons.calendar_month_outlined;
      default:
        return Icons.auto_awesome_outlined;
    }
  }

  String _describeFilter(SmartCollection collection) {
    final parts = <String>[];
    final filter = collection.filter;
    if (collection.window == SmartCollectionWindow.thisMonth) {
      parts.add('Added this month');
    }
    if (filter.onlyUntagged) parts.add('Untagged');
    if (filter.isEncrypted == true) parts.add('Encrypted');
    if (filter.isEncrypted == false) parts.add('Unencrypted');
    if (filter.isFavorite == true) parts.add('Favorites');
    if (filter.type != null) parts.add(filter.type!.displayName);
    if (filter.tags.isNotEmpty) {
      parts.add(filter.tags.map((t) => '#$t').join(' '));
    }
    if (filter.minSizeBytes != null) {
      parts.add('≥ ${_formatBytes(filter.minSizeBytes!)}');
    }
    if (filter.maxSizeBytes != null) {
      parts.add('≤ ${_formatBytes(filter.maxSizeBytes!)}');
    }
    if (filter.dateFrom != null || filter.dateTo != null) {
      final from = filter.dateFrom == null ? 'Any' : _formatDate(filter.dateFrom!);
      final to = filter.dateTo == null ? 'Any' : _formatDate(filter.dateTo!);
      parts.add('$from – $to');
    }
    return parts.isEmpty ? 'All files' : parts.join(' · ');
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).round()} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).round()} KB';
    }
    return '$bytes B';
  }

  Future<void> _createCollection(BuildContext context, WidgetRef ref) async {
    final name = await showSmartCollectionNameDialog(context);
    if (name == null || !context.mounted) return;
    final filter = await VaultFilterSheet.show(
      context,
      title: 'Filters for "$name"',
      applyLabel: 'Create',
    );
    if (filter == null || !context.mounted) return;
    final created = await ref
        .read(smartCollectionsProvider.notifier)
        .create(name: name, filter: filter.filter);
    if (!context.mounted) return;
    if (created != null) {
      ToastUtils.showSuccess('Created "${created.name}"');
    } else {
      ToastUtils.showError('Could not create collection');
    }
  }

  Future<void> _showOptions(
    BuildContext context,
    WidgetRef ref,
    SmartCollection collection,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: context.backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
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
              const SizedBox(height: 8),
              ListTile(
                leading: Icon(Icons.tune, color: context.accentColor),
                title: Text(
                  'Edit Filter',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    color: context.textPrimary,
                  ),
                ),
                onTap: () => Navigator.pop(sheetContext, 'edit'),
              ),
              if (collection.id == 'preset_large_videos')
                ListTile(
                  leading: Icon(Icons.straighten, color: context.accentColor),
                  title: Text(
                    'Adjust Size Threshold',
                    style: TextStyle(
                      fontFamily: 'ProductSans',
                      color: context.textPrimary,
                    ),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'threshold'),
                ),
              if (collection.isCustom)
                ListTile(
                  leading: Icon(Icons.edit_outlined, color: context.accentColor),
                  title: Text(
                    'Rename',
                    style: TextStyle(
                      fontFamily: 'ProductSans',
                      color: context.textPrimary,
                    ),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'rename'),
                ),
              if (collection.isCustom)
                ListTile(
                  leading: const Icon(Icons.delete_outline,
                      color: AppColors.error),
                  title: const Text(
                    'Delete',
                    style: TextStyle(
                      fontFamily: 'ProductSans',
                      color: AppColors.error,
                    ),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'delete'),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (action == null || !context.mounted) return;
    switch (action) {
      case 'edit':
        await _editFilter(context, ref, collection);
      case 'threshold':
        await _editThreshold(context, ref, collection);
      case 'rename':
        await _rename(context, ref, collection);
      case 'delete':
        await _confirmDelete(context, ref, collection);
    }
  }

  Future<void> _editFilter(
    BuildContext context,
    WidgetRef ref,
    SmartCollection collection,
  ) async {
    final result = await VaultFilterSheet.show(
      context,
      initialFilter: collection.filter,
      title: 'Edit "${collection.name}"',
      applyLabel: 'Save Filter',
    );
    if (result == null || !context.mounted) return;
    final updated = collection.copyWith(filter: result.filter);
    final ok = await ref
        .read(smartCollectionsProvider.notifier)
        .updateCollection(updated);
    if (!context.mounted) return;
    if (ok) {
      ToastUtils.showSuccess('Filter updated');
    } else {
      ToastUtils.showError('Could not update filter');
    }
  }

  Future<void> _editThreshold(
    BuildContext context,
    WidgetRef ref,
    SmartCollection collection,
  ) async {
    final currentMb =
        (collection.filter.minSizeBytes ?? 100 * 1024 * 1024) ~/ (1024 * 1024);
    final controller = TextEditingController(text: currentMb.toString());
    final mb = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(dialogContext).scaffoldBackgroundColor,
        title: Text(
          'Large Video Threshold',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: dialogContext.textPrimary,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            suffixText: 'MB',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: dialogContext.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              if (value != null && value > 0) {
                Navigator.pop(dialogContext, value);
              }
            },
            child: Text(
              'Save',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: dialogContext.accentColor,
              ),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    if (mb == null || !context.mounted) return;
    final updated = collection.copyWith(
      filter: collection.filter.copyWith(
        minSizeBytes: mb * 1024 * 1024,
        clearMaxSize: false,
      ),
    );
    final ok = await ref
        .read(smartCollectionsProvider.notifier)
        .updateCollection(updated);
    if (!context.mounted) return;
    if (ok) {
      ToastUtils.showSuccess('Threshold set to $mb MB');
    } else {
      ToastUtils.showError('Could not update threshold');
    }
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    SmartCollection collection,
  ) async {
    final name = await showSmartCollectionNameDialog(
      context,
      title: 'Rename Collection',
      initialName: collection.name,
      actionLabel: 'Rename',
    );
    if (name == null || !context.mounted) return;
    final ok = await ref
        .read(smartCollectionsProvider.notifier)
        .updateCollection(collection.copyWith(name: name));
    if (!context.mounted) return;
    if (ok) {
      ToastUtils.showSuccess('Renamed to "$name"');
    } else {
      ToastUtils.showError('Could not rename collection');
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    SmartCollection collection,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(dialogContext).scaffoldBackgroundColor,
        title: Text(
          'Delete Collection',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: dialogContext.textPrimary,
          ),
        ),
        content: Text(
          'Delete "${collection.name}"? Files stay in the vault.',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: dialogContext.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: dialogContext.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
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
    if (confirmed != true || !context.mounted) return;
    final ok = await ref
        .read(smartCollectionsProvider.notifier)
        .deleteCollection(collection.id);
    if (!context.mounted) return;
    if (ok) {
      ToastUtils.showSuccess('Collection deleted');
    } else {
      ToastUtils.showError('Could not delete collection');
    }
  }
}
