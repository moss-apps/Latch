import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../providers/smart_collection_providers.dart';
import '../../providers/vault_providers.dart';
import '../../screens/albums_screen.dart';
import '../../screens/favorites_screen.dart';
import '../../screens/folders_screen.dart';
import '../../screens/recently_deleted_screen.dart';
import '../../screens/smart_collections_screen.dart';
import '../../screens/tags_screen.dart';
import '../../screens/vault_explorer_screen.dart';
import '../../services/session_service.dart';
import '../../themes/app_colors.dart';

/// Library navigation owns its own counts, rather than rebuilding the gallery.
class GalleryVaultDrawer extends ConsumerWidget {
  const GalleryVaultDrawer({
    super.key,
    required this.onSettings,
    required this.onDecoyMode,
  });

  final VoidCallback onSettings;
  final VoidCallback onDecoyMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void open(Widget screen) {
      Navigator.pop(context);
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    }

    return Drawer(
      backgroundColor: context.isDarkMode ? Colors.black : Colors.white,
      child: ListView(padding: EdgeInsets.zero, children: [
        _header(context, ref),
        _section(context, 'Library'),
        _item(context, Icons.folder_outlined, 'Albums',
            badge: ref.watch(albumsProvider).asData?.value.length,
            onTap: () => open(const AlbumsScreen())),
        _item(context, Icons.folder_copy_outlined, 'Folders',
            badge: ref.watch(foldersProvider).asData?.value.length,
            onTap: () => open(const FoldersScreen())),
        _item(context, Icons.explore_outlined, 'File Explorer',
            badge: ref
                .watch(fileCountsProvider)
                .asData
                ?.value
                .values
                .fold<int>(0, (sum, count) => sum + count),
            onTap: () => open(const VaultExplorerScreen())),
        _item(context, Icons.favorite_outline, 'Favorites',
            badge: ref.watch(favoriteFilesProvider).asData?.value.length,
            onTap: () => open(const FavoritesScreen())),
        _item(context, Icons.label_outline, 'Tags',
            badge: ref.watch(tagsProvider).asData?.value.length,
            onTap: () => open(const TagsScreen())),
        _item(context, Icons.auto_awesome_outlined, 'Smart Collections',
            badge: ref.watch(smartCollectionsProvider).asData?.value.length,
            onTap: () => open(const SmartCollectionsScreen())),
        _item(context, Icons.delete_outline, 'Recently Deleted',
            showChevron: true,
            onTap: () => open(const RecentlyDeletedScreen())),
        _section(context, 'Security'),
        _item(context, Icons.lock_outline, 'Lock now',
            onTap: () => SessionService.instance.lock()),
        _item(context, Icons.security, 'Security Settings', showChevron: true,
            onTap: () {
          Navigator.pop(context);
          onSettings();
        }),
        _item(context, Icons.shield_outlined, 'Decoy Mode',
            subtitle: 'Set up fake vault', showChevron: true, onTap: () {
          Navigator.pop(context);
          onDecoyMode();
        }),
        SizedBox(height: MediaQuery.paddingOf(context).bottom + 12),
      ]),
    );
  }

  Widget _header(BuildContext context, WidgetRef ref) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
              context.accentColor,
              context.accentColor.withValues(alpha: 0.8)
            ])),
        child: SafeArea(
          bottom: false,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 72,
              height: 72,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3), width: 1.5)),
              child: SvgPicture.asset('assets/locker_logo_nobg.svg',
                  fit: BoxFit.contain,
                  colorFilter:
                      const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
            ),
            const SizedBox(height: 16),
            const Text('Latch',
                style: TextStyle(
                    fontFamily: 'ProductSans',
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5)),
            const SizedBox(height: 6),
            Text(
                '${ref.watch(fileCountSummaryProvider).value ?? '...'} • '
                '${ref.watch(formattedStorageProvider).value ?? '...'}',
                style: TextStyle(
                    fontFamily: 'ProductSans',
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14)),
          ]),
        ),
      );

  Widget _section(BuildContext context, String title) => Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 16, 8),
      child: Text(title.toUpperCase(),
          style: TextStyle(
              fontFamily: 'ProductSans',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: context.accentColor)));

  Widget _item(BuildContext context, IconData icon, String title,
          {String? subtitle,
          int? badge,
          bool showChevron = false,
          required VoidCallback onTap}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: context.accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10)),
                    child: Icon(icon, color: context.accentColor, size: 22)),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title,
                          style: TextStyle(
                              fontFamily: 'ProductSans',
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: context.textPrimary)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: TextStyle(
                                fontFamily: 'ProductSans',
                                fontSize: 12,
                                color: context.textSecondary)),
                      ],
                    ])),
                if (badge != null)
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: context.accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text('$badge',
                          style: TextStyle(
                              fontFamily: 'ProductSans',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: context.accentColor)))
                else if (showChevron)
                  Icon(Icons.chevron_right,
                      color: context.textTertiary, size: 20),
              ]),
            ),
          ),
        ),
      );
}
