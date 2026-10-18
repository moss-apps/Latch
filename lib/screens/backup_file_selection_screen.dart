import 'package:flutter/material.dart';
import '../models/vaulted_file.dart';
import '../services/vault_service.dart';
import '../themes/app_colors.dart';

class BackupFileSelectionScreen extends StatefulWidget {
  final List<VaultedFile> initialSelection;

  const BackupFileSelectionScreen({
    super.key,
    this.initialSelection = const [],
  });

  @override
  State<BackupFileSelectionScreen> createState() =>
      _BackupFileSelectionScreenState();
}

class _BackupFileSelectionScreenState extends State<BackupFileSelectionScreen> {
  final VaultService _vaultService = VaultService.instance;
  final TextEditingController _searchController = TextEditingController();
  final Map<String, GlobalKey> _tileKeys = {};

  late final Future<List<VaultedFile>> _filesFuture;
  late final Set<String> _selectedIds;
  String _searchQuery = '';
  bool _isSlidingSelection = false;
  bool? _slidingSelectionValue;
  final Set<String> _slidingTouchedIds = {};

  @override
  void initState() {
    super.initState();
    _filesFuture = _vaultService.getAllFiles(isDecoy: false);
    _selectedIds = widget.initialSelection.map((file) => file.id).toSet();
    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    final nextQuery = _searchController.text.trim().toLowerCase();
    if (nextQuery == _searchQuery) return;
    setState(() => _searchQuery = nextQuery);
  }

  void _toggleSelection(String fileId) {
    setState(() {
      _setSelected(fileId, !_selectedIds.contains(fileId));
    });
  }

  void _setSelected(String fileId, bool isSelected) {
    if (isSelected) {
      _selectedIds.add(fileId);
    } else {
      _selectedIds.remove(fileId);
    }
  }

  GlobalKey _tileKeyFor(String fileId) {
    return _tileKeys.putIfAbsent(fileId, GlobalKey.new);
  }

  void _startSlidingSelection(VaultedFile file) {
    final shouldSelect = !_selectedIds.contains(file.id);

    setState(() {
      _isSlidingSelection = true;
      _slidingSelectionValue = shouldSelect;
      _slidingTouchedIds
        ..clear()
        ..add(file.id);
      _setSelected(file.id, shouldSelect);
    });
  }

  void _updateSlidingSelection(Offset globalPosition) {
    if (!_isSlidingSelection || _slidingSelectionValue == null) return;

    final fileId = _fileIdAt(globalPosition);
    if (fileId == null || _slidingTouchedIds.contains(fileId)) return;

    setState(() {
      _slidingTouchedIds.add(fileId);
      _setSelected(fileId, _slidingSelectionValue!);
    });
  }

  void _stopSlidingSelection() {
    if (!_isSlidingSelection) return;

    setState(() {
      _isSlidingSelection = false;
      _slidingSelectionValue = null;
      _slidingTouchedIds.clear();
    });
  }

  String? _fileIdAt(Offset globalPosition) {
    for (final entry in _tileKeys.entries) {
      final context = entry.value.currentContext;
      if (context == null) continue;

      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) continue;

      final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
      if (rect.contains(globalPosition)) {
        return entry.key;
      }
    }

    return null;
  }

  void _toggleVisibleSelections(List<VaultedFile> visibleFiles) {
    if (visibleFiles.isEmpty) return;

    final visibleIds = visibleFiles.map((file) => file.id).toSet();
    final allVisibleSelected = visibleIds.every(_selectedIds.contains);

    setState(() {
      if (allVisibleSelected) {
        _selectedIds.removeAll(visibleIds);
      } else {
        _selectedIds.addAll(visibleIds);
      }
    });
  }

  void _applySelection(List<VaultedFile> files) {
    final selectedFiles =
        files.where((file) => _selectedIds.contains(file.id)).toList();
    Navigator.of(context).pop(selectedFiles);
  }

  List<VaultedFile> _visibleFiles(List<VaultedFile> files) {
    final filtered = _searchQuery.isEmpty
        ? List<VaultedFile>.from(files)
        : files
            .where((file) =>
                file.originalName.toLowerCase().contains(_searchQuery) ||
                file.type.displayName.toLowerCase().contains(_searchQuery) ||
                file.extension.toLowerCase().contains(_searchQuery))
            .toList();

    filtered.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
    return filtered;
  }

  int _selectedCount(List<VaultedFile> files) {
    return files.where((file) => _selectedIds.contains(file.id)).length;
  }

  IconData _iconForFile(VaultedFile file) {
    switch (file.type) {
      case VaultedFileType.image:
        return Icons.image_outlined;
      case VaultedFileType.video:
        return Icons.videocam_outlined;
      case VaultedFileType.song:
        return Icons.music_note_outlined;
      case VaultedFileType.document:
        return Icons.description_outlined;
      case VaultedFileType.other:
        return Icons.insert_drive_file_outlined;
    }
  }

  Color _colorForFile(VaultedFile file) {
    switch (file.type) {
      case VaultedFileType.image:
        return context.accentColor;
      case VaultedFileType.video:
        return Colors.red;
      case VaultedFileType.song:
        return Colors.purple;
      case VaultedFileType.document:
        return Colors.orange;
      case VaultedFileType.other:
        return Colors.grey;
    }
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        style: TextStyle(
          fontFamily: 'GoogleSansFlex',
          color: context.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: 'Search files',
          hintStyle: TextStyle(
            fontFamily: 'GoogleSansFlex',
            color: context.textTertiary,
          ),
          prefixIcon: Icon(Icons.search, color: context.textTertiary),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  onPressed: _searchController.clear,
                  icon: Icon(Icons.close, color: context.textTertiary),
                ),
          filled: true,
          fillColor: context.backgroundSecondary,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildFileTile(VaultedFile file) {
    final isSelected = _selectedIds.contains(file.id);
    final color = _colorForFile(file);

    return Padding(
      key: _tileKeyFor(file.id),
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (_) => _startSlidingSelection(file),
        onLongPressMoveUpdate: (details) =>
            _updateSlidingSelection(details.globalPosition),
        onLongPressEnd: (_) => _stopSlidingSelection(),
        onLongPressCancel: _stopSlidingSelection,
        child: Material(
          color: isSelected
              ? context.accentColor.withValues(alpha: 0.1)
              : context.backgroundSecondary,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => _toggleSelection(file.id),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_iconForFile(file), color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.originalName,
                          style: TextStyle(
                            fontFamily: 'GoogleSansFlex',
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: context.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${file.type.displayName} · ${file.formattedSize} · ${file.formattedDateAdded}',
                          style: TextStyle(
                            fontFamily: 'GoogleSansFlex',
                            fontSize: 12,
                            color: context.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          isSelected ? context.accentColor : Colors.transparent,
                      border: Border.all(
                        color: isSelected
                            ? context.accentColor
                            : context.textTertiary,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionHint() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        'Tip: long-press and slide across files to select or clear several at once.',
        style: TextStyle(
          fontFamily: 'GoogleSansFlex',
          fontSize: 12,
          color: context.textTertiary,
        ),
      ),
    );
  }

  void _syncTileKeys(List<VaultedFile> visibleFiles) {
    final visibleIds = visibleFiles.map((file) => file.id).toSet();
    _tileKeys.removeWhere((fileId, _) => !visibleIds.contains(fileId));
  }

  Widget _buildVisibleFilesList(List<VaultedFile> visibleFiles) {
    _syncTileKeys(visibleFiles);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      itemCount: visibleFiles.length,
      itemBuilder: (context, index) => _buildFileTile(visibleFiles[index]),
    );
  }

  Widget _buildEmptyState({required String title, required String subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.backup_outlined, size: 56, color: context.textTertiary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'GoogleSansFlex',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'GoogleSansFlex',
                fontSize: 14,
                color: context.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadedState(List<VaultedFile> files) {
    final visibleFiles = _visibleFiles(files);
    final selectedCount = _selectedCount(files);
    final allVisibleSelected = visibleFiles.isNotEmpty &&
        visibleFiles.every((file) => _selectedIds.contains(file.id));

    if (files.isEmpty) {
      return _buildEmptyState(
        title: 'No files in vault',
        subtitle: 'Hide files first, then come back to create a backup.',
      );
    }

    return Column(
      children: [
        _buildSearchField(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Text(
                '${visibleFiles.length} file${visibleFiles.length == 1 ? '' : 's'}',
                style: TextStyle(
                  fontFamily: 'GoogleSansFlex',
                  fontSize: 13,
                  color: context.textTertiary,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: visibleFiles.isEmpty
                    ? null
                    : () => _toggleVisibleSelections(visibleFiles),
                child: Text(
                    allVisibleSelected ? 'Clear visible' : 'Select visible'),
              ),
            ],
          ),
        ),
        _buildSelectionHint(),
        Expanded(
          child: visibleFiles.isEmpty
              ? _buildEmptyState(
                  title: 'No matching files',
                  subtitle: 'Try another name, type, or file extension.',
                )
              : _buildVisibleFilesList(visibleFiles),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              border: Border(
                top: BorderSide(
                    color: context.borderColor.withValues(alpha: 0.5)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selectedCount == 1
                        ? '1 file selected'
                        : '$selectedCount files selected',
                    style: TextStyle(
                      fontFamily: 'GoogleSansFlex',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed:
                      selectedCount == 0 ? null : () => _applySelection(files),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Use selected'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Select backup files',
          style: TextStyle(
            fontFamily: 'GoogleSansFlex',
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: context.textPrimary),
      ),
      body: FutureBuilder<List<VaultedFile>>(
        future: _filesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            );
          }

          if (snapshot.hasError) {
            return _buildEmptyState(
              title: 'Failed to load vault files',
              subtitle: 'Try reopening this screen and run the backup again.',
            );
          }

          return _buildLoadedState(snapshot.data ?? const []);
        },
      ),
    );
  }
}
