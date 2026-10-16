import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/deleted_vault_item.dart';
import 'vault_providers.dart';

final recentlyDeletedProvider = FutureProvider<List<DeletedVaultItem>>((ref) {
  ref.watch(vaultNotifierProvider);
  return ref
      .watch(vaultServiceProvider)
      .store
      .loadDeletedItems(isDecoy: ref.watch(isDecoyModeProvider));
});

final recentlyDeletedStorageProvider = FutureProvider<int>((ref) {
  ref.watch(recentlyDeletedProvider);
  return ref
      .watch(vaultServiceProvider)
      .recentlyDeleted
      .storageUsed(isDecoy: ref.watch(isDecoyModeProvider));
});
