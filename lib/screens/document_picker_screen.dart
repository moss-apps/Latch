import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/path_utils.dart';
import 'package:mime/mime.dart';
import '../models/vaulted_file.dart';
import '../themes/app_colors.dart';
import '../services/permission_service.dart';

/// Model representing a document file found on the device
class DocumentFile {
  final String path;
  final String name;
  final int size;
  final DateTime modified;
  final String extension;

  DocumentFile({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
    required this.extension,
  });

  /// Get the MIME type
  String get mimeType => lookupMimeType(path) ?? 'application/octet-stream';

  /// Get formatted file size
  String get formattedSize {
    if (size < 1024) {
      return '$size B';
    } else if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    } else if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  /// Get formatted date
  String get formattedDate {
    final now = DateTime.now();
    final diff = now.difference(modified);

    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${modified.day}/${modified.month}/${modified.year}';
    }
  }

  /// Get icon data based on extension
  IconData get icon {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
      case 'odt':
      case 'rtf':
        return Icons.description;
      case 'xls':
      case 'xlsx':
      case 'ods':
      case 'csv':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
      case 'odp':
        return Icons.slideshow;
      case 'txt':
        return Icons.text_snippet;
      case 'epub':
        return Icons.menu_book;
      default:
        return Icons.insert_drive_file;
    }
  }

  /// Get icon color based on extension
  Color get iconColor {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return Colors.red.shade400;
      case 'doc':
      case 'docx':
      case 'odt':
      case 'rtf':
        return Colors.blue.shade400;
      case 'xls':
      case 'xlsx':
      case 'ods':
      case 'csv':
        return Colors.green.shade400;
      case 'ppt':
      case 'pptx':
      case 'odp':
        return Colors.orange.shade400;
      case 'txt':
        return Colors.grey.shade600;
      case 'epub':
        return Colors.purple.shade400;
      default:
        return Colors.blueGrey.shade400;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentFile &&
          runtimeType == other.runtimeType &&
          path == other.path;

  @override
  int get hashCode => path.hashCode;
}

/// Sort options for documents
enum DocumentSortOption {
  nameAsc('Name (A-Z)'),
  nameDesc('Name (Z-A)'),
  dateAsc('Oldest First'),
  dateDesc('Most Recent'),
  sizeAsc('Smallest First'),
  sizeDesc('Largest First');

  final String label;
  const DocumentSortOption(this.label);
}

/// A custom document picker that scans the device for document files.
/// This provides a gallery-like experience for selecting documents.
class DocumentPickerScreen extends StatefulWidget {
  /// Maximum number of items that can be selected (0 = unlimited)
  final int maxSelection;

  /// Title for the app bar
  final String title;

  /// Extensions allowed in the picker.
  final List<String> allowedExtensions;

  /// Singular label for the selected file type.
  final String itemLabel;

  /// Plural label for the selected file type.
  final String itemLabelPlural;

  /// Icon for the empty/loading state.
  final IconData stateIcon;

  const DocumentPickerScreen({
    super.key,
    this.maxSelection = 0,
    this.title = 'Select Documents',
    this.allowedExtensions = supportedDocumentExtensions,
    this.itemLabel = 'document',
    this.itemLabelPlural = 'documents',
    this.stateIcon = Icons.description_outlined,
  });

  @override
  State<DocumentPickerScreen> createState() => _DocumentPickerScreenState();
}

class _DocumentPickerScreenState extends State<DocumentPickerScreen> {
  final List<DocumentFile> _documents = [];
  final Set<DocumentFile> _selectedDocuments = {};
  final Map<String, GlobalKey> _tileKeys = {};
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  DocumentSortOption _sortOption = DocumentSortOption.dateDesc;
  final _searchController = TextEditingController();
  late String _currentFolder;
  final Map<String, List<DocumentFile>> _folderGroups = {};
  bool _isSlidingSelection = false;
  bool? _slidingSelectionValue;
  final Set<String> _slidingTouchedDocumentPaths = {};

  String get _allItemsLabel => 'All ${widget.itemLabelPlural}';

  String get _itemLabelPluralCapitalized =>
      widget.itemLabelPlural[0].toUpperCase() +
      widget.itemLabelPlural.substring(1);

  @override
  void initState() {
    super.initState();
    _currentFolder = _allItemsLabel;
    _scanForDocuments();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Scan device storage for documents
  Future<void> _scanForDocuments() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Request storage permission
      final permissionService = PermissionService.instance;
      final hasPermission = await permissionService.requestStoragePermission();

      if (!hasPermission) {
        setState(() {
          _isLoading = false;
          _error = 'Storage permission is required to browse documents';
        });
        return;
      }

      final foundDocuments = <DocumentFile>[];
      final directories = <Directory>[];

      // Get common document directories
      if (Platform.isAndroid) {
        // External storage directories where documents are commonly stored
        final externalDirs = await getExternalStorageDirectories();
        if (externalDirs != null) {
          for (final dir in externalDirs) {
            // Navigate up to get the root external storage
            final rootPath = dir.path.split('Android').first;
            directories.add(Directory(rootPath));
          }
        }

        // Also check common locations
        final commonPaths = PathUtils.androidSourceRoots;

        for (final path in commonPaths) {
          final dir = Directory(path);
          if (await dir.exists()) {
            directories.add(dir);
          }
        }
      } else {
        // iOS - use documents directory
        final docDir = await getApplicationDocumentsDirectory();
        directories.add(docDir);

        // Also check downloads
        final downloadDir = await getDownloadsDirectory();
        if (downloadDir != null) {
          directories.add(downloadDir);
        }
      }

      // Scan each directory for documents
      final scannedPaths = <String>{};
      for (final dir in directories) {
        await _scanDirectory(dir, foundDocuments, scannedPaths, 0, 4);
      }

      // Group by folder
      _folderGroups.clear();
      _folderGroups[_allItemsLabel] = foundDocuments;
      for (final doc in foundDocuments) {
        final folder = Directory(doc.path).parent.path.split('/').last;
        _folderGroups.putIfAbsent(folder, () => []).add(doc);
      }

      // Sort initially by date (most recent first)
      foundDocuments.sort((a, b) => b.modified.compareTo(a.modified));

      setState(() {
        _documents.clear();
        _documents.addAll(foundDocuments);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error scanning for documents: $e');
      setState(() {
        _isLoading = false;
        _error = 'Failed to scan for documents: $e';
      });
    }
  }

  /// Recursively scan a directory for document files
  Future<void> _scanDirectory(
    Directory dir,
    List<DocumentFile> results,
    Set<String> scannedPaths,
    int depth,
    int maxDepth,
  ) async {
    if (depth > maxDepth) return;

    try {
      // Avoid scanning the same path twice
      final canonicalPath = dir.path;
      if (scannedPaths.contains(canonicalPath)) return;
      scannedPaths.add(canonicalPath);

      // Skip certain directories
      final dirName = dir.path.split('/').last;
      if (dirName.startsWith('.') ||
          dirName == 'Android' ||
          dirName == 'cache' ||
          dirName == 'thumbnails') {
        return;
      }

      final entities = await dir.list().toList();

      for (final entity in entities) {
        if (entity is File) {
          final fileName = entity.path.split('/').last;
          if (fileName.startsWith('.')) continue;

          final ext = fileName.contains('.')
              ? fileName.split('.').last.toLowerCase()
              : '';

          if (widget.allowedExtensions.contains(ext)) {
            try {
              final stat = await entity.stat();
              results.add(DocumentFile(
                path: entity.path,
                name: fileName,
                size: stat.size,
                modified: stat.modified,
                extension: ext,
              ));
            } catch (e) {
              // Skip files we can't access
            }
          }
        } else if (entity is Directory) {
          await _scanDirectory(
              entity, results, scannedPaths, depth + 1, maxDepth);
        }
      }
    } catch (e) {
      // Skip directories we can't access
    }
  }

  /// Get filtered and sorted documents
  List<DocumentFile> get _filteredDocuments {
    var docs = _currentFolder == _allItemsLabel
        ? List<DocumentFile>.from(_documents)
        : List<DocumentFile>.from(_folderGroups[_currentFolder] ?? []);

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      docs = docs
          .where((doc) =>
              doc.name.toLowerCase().contains(query) ||
              doc.extension.toLowerCase().contains(query))
          .toList();
    }

    // Apply sorting
    switch (_sortOption) {
      case DocumentSortOption.nameAsc:
        docs.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case DocumentSortOption.nameDesc:
        docs.sort(
            (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case DocumentSortOption.dateAsc:
        docs.sort((a, b) => a.modified.compareTo(b.modified));
        break;
      case DocumentSortOption.dateDesc:
        docs.sort((a, b) => b.modified.compareTo(a.modified));
        break;
      case DocumentSortOption.sizeAsc:
        docs.sort((a, b) => a.size.compareTo(b.size));
        break;
      case DocumentSortOption.sizeDesc:
        docs.sort((a, b) => b.size.compareTo(a.size));
        break;
    }

    return docs;
  }

  void _toggleSelection(DocumentFile doc) {
    setState(() {
      _setSelected(doc, !_selectedDocuments.contains(doc));
    });
  }

  bool _setSelected(DocumentFile doc, bool isSelected,
      {bool showLimitError = true}) {
    if (isSelected) {
      if (_selectedDocuments.contains(doc)) return true;

      if (widget.maxSelection > 0 &&
          _selectedDocuments.length >= widget.maxSelection) {
        if (showLimitError) {
          _showMaxSelectionMessage();
        }
        return false;
      }

      _selectedDocuments.add(doc);
      return true;
    }

    _selectedDocuments.remove(doc);
    return true;
  }

  void _showMaxSelectionMessage() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Maximum ${widget.maxSelection} items can be selected'),
          duration: const Duration(seconds: 1),
        ),
      );
  }

  GlobalKey _tileKeyFor(String documentPath) {
    return _tileKeys.putIfAbsent(documentPath, GlobalKey.new);
  }

  void _startSlidingSelection(DocumentFile doc) {
    final shouldSelect = !_selectedDocuments.contains(doc);
    if (!_setSelected(doc, shouldSelect)) return;

    setState(() {
      _isSlidingSelection = true;
      _slidingSelectionValue = shouldSelect;
      _slidingTouchedDocumentPaths
        ..clear()
        ..add(doc.path);
    });
  }

  void _updateSlidingSelection(Offset globalPosition) {
    if (!_isSlidingSelection || _slidingSelectionValue == null) return;

    final documentPath = _documentPathAt(globalPosition);
    if (documentPath == null ||
        _slidingTouchedDocumentPaths.contains(documentPath)) {
      return;
    }

    final doc = _documentByPath(documentPath);
    if (doc == null) return;

    final applied =
        _setSelected(doc, _slidingSelectionValue!, showLimitError: false);
    if (!applied) {
      _showMaxSelectionMessage();
      _stopSlidingSelection();
      return;
    }

    setState(() {
      _slidingTouchedDocumentPaths.add(documentPath);
    });
  }

  void _stopSlidingSelection() {
    if (!_isSlidingSelection) return;

    setState(() {
      _isSlidingSelection = false;
      _slidingSelectionValue = null;
      _slidingTouchedDocumentPaths.clear();
    });
  }

  DocumentFile? _documentByPath(String documentPath) {
    for (final doc in _filteredDocuments) {
      if (doc.path == documentPath) return doc;
    }
    return null;
  }

  String? _documentPathAt(Offset globalPosition) {
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

  void _selectAll() {
    setState(() {
      final docs = _filteredDocuments;
      if (widget.maxSelection > 0) {
        for (final doc in docs) {
          if (_selectedDocuments.length >= widget.maxSelection) break;
          _selectedDocuments.add(doc);
        }
      } else {
        _selectedDocuments.addAll(docs);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedDocuments.clear();
    });
  }

  void _confirmSelection() {
    Navigator.pop(context, _selectedDocuments.toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        backgroundColor: context.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: context.textPrimary),
          onPressed: () => Navigator.pop(context, null),
        ),
        title: Text(
          widget.title,
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (_selectedDocuments.isNotEmpty)
            TextButton(
              onPressed: _clearSelection,
              child: const Text('Clear'),
            ),
          if (_documents.isNotEmpty)
            TextButton(
              onPressed: _selectAll,
              child: const Text('Select All'),
            ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          _buildSearchBar(),
          // Folder chips and sort
          _buildFiltersRow(),
          // Document list
          Expanded(
            child: _isLoading
                ? _buildLoadingState()
                : _error != null
                    ? _buildErrorState()
                    : _filteredDocuments.isEmpty
                        ? _buildEmptyState()
                        : _buildDocumentList(),
          ),
        ],
      ),
      bottomNavigationBar:
          _selectedDocuments.isNotEmpty ? _buildBottomBar() : null,
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: 'Search ${widget.itemLabelPlural}...',
          hintStyle: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textTertiary,
          ),
          prefixIcon: Icon(Icons.search, color: context.textTertiary),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: context.textTertiary),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: context.backgroundSecondary,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        style: TextStyle(
          fontFamily: 'ProductSans',
          color: context.textPrimary,
        ),
      ),
    );
  }

  Widget _buildFiltersRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          // Folder dropdown
          Expanded(
            child: PopupMenuButton<String>(
              initialValue: _currentFolder,
              onSelected: (folder) {
                setState(() => _currentFolder = folder);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: context.backgroundSecondary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder, size: 18, color: context.accentColor),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _currentFolder,
                        style: TextStyle(
                          fontFamily: 'ProductSans',
                          color: context.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.arrow_drop_down, color: context.textSecondary),
                  ],
                ),
              ),
              itemBuilder: (context) => _folderGroups.keys.map((folder) {
                final count = _folderGroups[folder]?.length ?? 0;
                return PopupMenuItem<String>(
                  value: folder,
                  child: Row(
                    children: [
                      Icon(
                        folder == _allItemsLabel
                            ? Icons.folder_special
                            : Icons.folder,
                        size: 18,
                        color: context.accentColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          folder,
                          style: const TextStyle(fontFamily: 'ProductSans'),
                        ),
                      ),
                      Text(
                        '($count)',
                        style: TextStyle(
                          fontFamily: 'ProductSans',
                          color: context.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(width: 12),
          // Sort dropdown
          PopupMenuButton<DocumentSortOption>(
            initialValue: _sortOption,
            onSelected: (option) {
              setState(() => _sortOption = option);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: context.backgroundSecondary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sort, size: 18, color: context.textSecondary),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, color: context.textSecondary),
                ],
              ),
            ),
            itemBuilder: (context) => DocumentSortOption.values.map((option) {
              return PopupMenuItem<DocumentSortOption>(
                value: option,
                child: Row(
                  children: [
                    if (option == _sortOption)
                      Icon(Icons.check, size: 18, color: context.accentColor)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 8),
                    Text(
                      option.label,
                      style: const TextStyle(fontFamily: 'ProductSans'),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(context.accentColor),
          ),
          const SizedBox(height: 16),
          Text(
            'Scanning for ${widget.itemLabelPlural}...',
            style: TextStyle(
              fontFamily: 'ProductSans',
              fontSize: 16,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              _error ?? 'An error occurred',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'ProductSans',
                fontSize: 16,
                color: context.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _scanForDocuments,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.accentColor,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            widget.stateIcon,
            size: 64,
            color: context.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty
                ? 'No ${widget.itemLabelPlural} matching "$_searchQuery"'
                : 'No ${widget.itemLabelPlural} found',
            style: TextStyle(
              fontFamily: 'ProductSans',
              fontSize: 18,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your ${widget.itemLabelPlural} will appear here when found on your device',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'ProductSans',
              fontSize: 14,
              color: context.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentList() {
    final docs = _filteredDocuments;
    _tileKeys.removeWhere(
      (documentPath, _) => !docs.any((doc) => doc.path == documentPath),
    );

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        return _buildDocumentTile(docs[index], index);
      },
    );
  }

  Widget _buildDocumentTile(DocumentFile doc, int index) {
    final isSelected = _selectedDocuments.contains(doc);
    final selectionIndex = _selectedDocuments.toList().indexOf(doc);

    return Padding(
      key: _tileKeyFor(doc.path),
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (_) => _startSlidingSelection(doc),
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
            onTap: () => _toggleSelection(doc),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // File type icon
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: doc.iconColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      doc.icon,
                      color: doc.iconColor,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // File info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc.name,
                          style: TextStyle(
                            fontFamily: 'ProductSans',
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: context.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              doc.formattedSize,
                              style: TextStyle(
                                fontFamily: 'ProductSans',
                                fontSize: 12,
                                color: context.textSecondary,
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              width: 3,
                              height: 3,
                              decoration: BoxDecoration(
                                color: context.textTertiary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            Text(
                              doc.formattedDate,
                              style: TextStyle(
                                fontFamily: 'ProductSans',
                                fontSize: 12,
                                color: context.textSecondary,
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              width: 3,
                              height: 3,
                              decoration: BoxDecoration(
                                color: context.textTertiary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: doc.iconColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                doc.extension.toUpperCase(),
                                style: TextStyle(
                                  fontFamily: 'ProductSans',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: doc.iconColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Selection indicator
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? context.accentColor
                          : Colors.white.withValues(alpha: 0.7),
                      border: Border.all(
                        color: isSelected
                            ? context.accentColor
                            : Colors.grey.shade400,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                    child: isSelected
                        ? Center(
                            child: Text(
                              '${selectionIndex + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'ProductSans',
                              ),
                            ),
                          )
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

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: context.backgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_selectedDocuments.length} selected',
              style: TextStyle(
                fontFamily: 'ProductSans',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: _confirmSelection,
            icon: const Icon(Icons.check, size: 20),
            label: Text('Hide $_itemLabelPluralCapitalized'),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.accentColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
