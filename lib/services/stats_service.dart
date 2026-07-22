import '../models/vaulted_file.dart';
import 'vault_store.dart';

/// Read-only stats over the file index. Splits out of `VaultService`.
class StatsService {
  final VaultStore _store;
  StatsService(this._store);

  Future<Map<VaultedFileType, int>> getFileCounts() async {
    final files = await _store.loadFileIndex();
    final counts = <VaultedFileType, int>{};

    for (final type in VaultedFileType.values) {
      counts[type] = files.where((f) => f.type == type).length;
    }

    return counts;
  }

  Future<int> getTotalStorageUsed() async {
    final files = await _store.loadFileIndex();
    return files.fold<int>(0, (sum, file) => sum + file.fileSize);
  }
}