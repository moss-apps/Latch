import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import '../utils/path_utils.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:video_player/video_player.dart';
import '../models/vaulted_file.dart';
import '../providers/vault_providers.dart';
import '../services/auto_kill_service.dart';
import '../services/vault_service.dart';
import '../themes/app_colors.dart';
import '../utils/toast_utils.dart';
import '../widgets/file_info_sheet.dart';

enum _VideoLoadPhase { idle, decrypting, initializing, ready }

// Full-screen media viewer: images, videos, slideshow.
class MediaViewerScreen extends ConsumerStatefulWidget {
  final VaultedFile initialFile;
  final List<VaultedFile> files;
  final int initialIndex;

  /// A decrypted file already prepared by the caller. Used for the initial
  /// file so decryption does not happen on the main thread.
  final File? initialDecryptedFile;

  const MediaViewerScreen({
    super.key,
    required this.initialFile,
    required this.files,
    required this.initialIndex,
    this.initialDecryptedFile,
  });

  @override
  ConsumerState<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends ConsumerState<MediaViewerScreen> {
  late PageController _pageController;
  late int _currentIndex;
  // local copy so on-delete remove() mutates ours, not the caller's list
  late final List<VaultedFile> _files;
  bool _showControls = true;
  bool _isSlideshow = false;
  int _slideshowDuration = 3; // seconds

  // Video player for current video
  VideoPlayerController? _videoController;
  _VideoLoadPhase _videoPhase = _VideoLoadPhase.idle;
  bool _isVideoPlaying = false;
  double _playbackSpeed = 1.0;
  bool _isLooping = false;
  bool _isMuted = false;
  bool _forceLandscape = false;
  double? _decryptProgress;

  // Cancel token for in-flight video loads
  Completer<void>? _videoLoadCancel;

  // Image.file streams from disk; Image.memory stalled main-isolate decode on large images.
  final Map<String, File> _decryptedFileCache = {};

  // Debounce timer for video player updates (reduces setState calls)
  Timer? _videoUpdateTimer;
  static const _videoUpdateInterval = Duration(milliseconds: 250);

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _files = List.of(widget.files);
    _pageController = PageController(initialPage: _currentIndex);
    _loadCurrentMedia();

    // Hide system UI for immersive view
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _videoLoadCancel?.complete();
    _videoLoadCancel = null;
    _videoUpdateTimer?.cancel();
    _videoUpdateTimer = null;
    _videoController?.dispose();
    _videoController = null;
    _pageController.dispose();
    // Clear decrypted cache to free memory immediately
    _decryptedFileCache.clear();
    // Clean up temp decrypted files in background
    _cleanupTempFiles();
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  /// Clean up temporary decrypted files to prevent disk space leaks
  void _cleanupTempFiles() {
    try {
      VaultService.instance.cleanupTemp();
    } catch (e) {
      debugPrint('Error cleaning up temp files: $e');
    }
  }

  Future<void> _loadCurrentMedia() async {
    final file = _files[_currentIndex];

    if (file.isVideo) {
      await _initializeVideo(file);
      // Don't load video bytes into memory - videos are streamed from temp file.
      // This prevents massive memory pressure (e.g. 128MB+ videos).
      return;
    }

    // Resolve the decrypted File path for encrypted images. We keep the File
    // (not its bytes) so Image.file can stream the decode off the main isolate.
    if (file.isEncrypted &&
        file.isImage &&
        !_decryptedFileCache.containsKey(file.id)) {
      final decryptedFile = file.id == widget.initialFile.id
          ? widget.initialDecryptedFile
          : await ref.read(vaultServiceProvider).getVaultedFile(file.id);

      if (decryptedFile != null && await decryptedFile.exists()) {
        if (mounted) {
          setState(() {
            _decryptedFileCache[file.id] = decryptedFile;
          });
        }
      }
    }
  }

  Future<void> _initializeVideo(VaultedFile file) async {
    // Cancel any previous load
    _videoLoadCancel?.complete();
    final cancel = Completer<void>();
    _videoLoadCancel = cancel;

    if (!file.isVideo) return;

    try {
      // If the caller already prepared a decrypted file, use it directly.
      final preDecryptedFile =
          file.id == widget.initialFile.id ? widget.initialDecryptedFile : null;

      if (preDecryptedFile != null && await preDecryptedFile.exists()) {
        if (mounted && !cancel.isCompleted) {
          setState(() {
            _videoPhase = _VideoLoadPhase.initializing;
            _decryptProgress = null;
          });
        }

        final controller = VideoPlayerController.file(preDecryptedFile);
        await controller.initialize();

        if (cancel.isCompleted) {
          controller.dispose();
          return;
        }

        await _setupController(controller);
        return;
      }

      // Phase 1: decrypt
      if (file.isEncrypted && file.encryptionIv != null) {
        if (mounted && !cancel.isCompleted) {
          setState(() {
            _videoPhase = _VideoLoadPhase.decrypting;
            _decryptProgress = 0.0;
          });
        }

        final decryptedFile =
            await ref.read(vaultServiceProvider).getVaultedFile(
          file.id,
          onProgress: (processed, total) {
            if (!cancel.isCompleted && mounted && total > 0) {
              setState(() {
                _decryptProgress = processed / total;
              });
            }
          },
        );

        if (cancel.isCompleted || decryptedFile == null) {
          if (decryptedFile == null) {
            ToastUtils.showError('Failed to decrypt video');
          }
          return;
        }

        // Phase 2: init player
        if (mounted && !cancel.isCompleted) {
          setState(() {
            _videoPhase = _VideoLoadPhase.initializing;
            _decryptProgress = null;
          });
        }

        final controller = VideoPlayerController.file(decryptedFile);
        await controller.initialize();

        if (cancel.isCompleted) {
          controller.dispose();
          return;
        }

        await _setupController(controller);
        return;
      }

      // Plain file (not encrypted)
      if (mounted && !cancel.isCompleted) {
        setState(() {
          _videoPhase = _VideoLoadPhase.initializing;
        });
      }

      final controller = VideoPlayerController.file(File(file.vaultPath));
      await controller.initialize();

      if (cancel.isCompleted) {
        controller.dispose();
        return;
      }

      await _setupController(controller);
    } catch (e) {
      debugPrint('Error initializing video: $e');
      if (!cancel.isCompleted) {
        ToastUtils.showError('Failed to load video');
      }
    }
  }

  Future<void> _setupController(VideoPlayerController controller) async {
    _videoController = controller;

    await controller.setLooping(_isLooping);
    await controller.setPlaybackSpeed(_playbackSpeed);
    await controller.setVolume(_isMuted ? 0.0 : 1.0);

    controller.addListener(_onVideoUpdate);

    if (mounted) {
      setState(() {
        _videoPhase = _VideoLoadPhase.ready;
      });
    }
  }

  // Debounce video updates to avoid setState every frame.
  void _onVideoUpdate() {
    // Skip if timer is already scheduled (debouncing)
    if (_videoUpdateTimer?.isActive == true) return;

    // Schedule the actual setState call
    _videoUpdateTimer = Timer(_videoUpdateInterval, () {
      if (mounted) setState(() {});
    });
  }

  void _onPageChanged(int index) {
    _videoController?.pause();
    _videoController?.removeListener(_onVideoUpdate);

    // Cancel in-flight video load
    _videoLoadCancel?.complete();
    _videoLoadCancel = null;

    final oldController = _videoController;

    setState(() {
      _currentIndex = index;
      _videoController = null;
      _videoPhase = _VideoLoadPhase.idle;
      _isVideoPlaying = false;
      _decryptProgress = null;
      if (!_files[index].isVideo && _forceLandscape) {
        _forceLandscape = false;
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      }
    });

    // Dispose old controller after rebuild to avoid blocking swipe animation
    oldController?.dispose();

    _loadCurrentMedia();

    final file = _files[index];
    ref.read(vaultServiceProvider).updateFile(file.markViewed());
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  void _toggleFavorite() async {
    final file = _files[_currentIndex];
    final wasFavorite = file.isFavorite;
    await ref.read(vaultNotifierProvider.notifier).toggleFavorite(file.id);
    ToastUtils.showSuccess(
      wasFavorite ? 'Removed from favorites' : 'Added to favorites',
    );
  }

  void _toggleLooping() async {
    setState(() => _isLooping = !_isLooping);
    await _videoController?.setLooping(_isLooping);
  }

  // orientation lock for video viewing; pure global side effect.
  void _toggleOrientation() {
    setState(() => _forceLandscape = !_forceLandscape);
    if (_forceLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  void _startSlideshow() {
    if (_isSlideshow) {
      setState(() => _isSlideshow = false);
      return;
    }

    setState(() {
      _isSlideshow = true;
      _showControls = false;
    });

    _runSlideshow();
  }

  void _runSlideshow() async {
    while (_isSlideshow && mounted) {
      await Future.delayed(Duration(seconds: _slideshowDuration));
      if (!_isSlideshow || !mounted) break;

      // Move to next image (skip videos in slideshow)
      int nextIndex = _currentIndex;
      do {
        nextIndex = (nextIndex + 1) % _files.length;
        if (nextIndex == _currentIndex) break; // Completed full loop
      } while (_files[nextIndex].isVideo);

      if (nextIndex != _currentIndex) {
        _pageController.animateToPage(
          nextIndex,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  void _showSlideshowSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        decoration: BoxDecoration(
          color: context.backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Slideshow Settings',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                        fontFamily: 'ProductSans',
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Duration per slide',
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        color: context.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    StatefulBuilder(
                      builder: (context, setSheetState) => Row(
                        children: [
                          for (final seconds in [2, 3, 5, 10])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text('${seconds}s'),
                                selected: _slideshowDuration == seconds,
                                onSelected: (selected) {
                                  if (selected) {
                                    setSheetState(() {});
                                    setState(
                                        () => _slideshowDuration = seconds);
                                  }
                                },
                                selectedColor: context.accentColor,
                                labelStyle: TextStyle(
                                  color: _slideshowDuration == seconds
                                      ? Colors.white
                                      : context.textSecondary,
                                  fontFamily: 'ProductSans',
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _startSlideshow();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.accentColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          _isSlideshow ? 'Stop Slideshow' : 'Start Slideshow',
                          style: const TextStyle(fontFamily: 'ProductSans'),
                        ),
                      ),
                    ),
                    SizedBox(height: MediaQuery.of(context).padding.bottom),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleVideoPlayback() {
    if (_videoController == null || _videoPhase != _VideoLoadPhase.ready) {
      return;
    }

    setState(() {
      if (_isVideoPlaying) {
        _videoController!.pause();
      } else {
        _videoController!.play();
      }
      _isVideoPlaying = !_isVideoPlaying;
    });
  }

  void _seekVideo(Duration position) {
    if (_videoController == null || _videoPhase != _VideoLoadPhase.ready) {
      return;
    }
    _videoController!.seekTo(position);
  }

  void _skipForward() {
    if (_videoController == null || _videoPhase != _VideoLoadPhase.ready) {
      return;
    }
    final newPos =
        _videoController!.value.position + const Duration(seconds: 10);
    final duration = _videoController!.value.duration;
    _seekVideo(newPos > duration ? duration : newPos);
  }

  void _skipBackward() {
    if (_videoController == null || _videoPhase != _VideoLoadPhase.ready) {
      return;
    }
    final newPos =
        _videoController!.value.position - const Duration(seconds: 10);
    _seekVideo(newPos < Duration.zero ? Duration.zero : newPos);
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '${duration.inHours > 0 ? '${duration.inHours}:' : ''}$minutes:$seconds';
  }

  void _showFileInfo() {
    final file = _files[_currentIndex];
    final extra = <(String, String)>[];
    if (file.hasTags) extra.add(('Tags', file.tags.join(', ')));
    if (file.viewCount > 0) extra.add(('Views', file.viewCount.toString()));
    FileInfoSheet.show(
      context,
      file,
      title: 'File Information',
      typeLabel: file.type.displayName,
      extraRows: extra.isEmpty ? null : extra,
    );
  }

  void _showExportOptions(VaultedFile file) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: BoxDecoration(
          color: context.backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
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
                      'Export Options',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                        fontFamily: 'ProductSans',
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.download_outlined,
                            color: AppColors.accent),
                      ),
                      title: const Text('Export to Downloads',
                          style: TextStyle(
                              fontFamily: 'ProductSans',
                              fontWeight: FontWeight.w500)),
                      subtitle: Text('Save file to Downloads folder',
                          style: TextStyle(
                              fontFamily: 'ProductSans',
                              fontSize: 12,
                              color: AppColors.lightTextSecondary)),
                      contentPadding: EdgeInsets.zero,
                      onTap: () {
                        Navigator.pop(context);
                        _exportToDownloads(file);
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: context.accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child:
                            Icon(Icons.open_in_new, color: context.accentColor),
                      ),
                      title: const Text('Open with...',
                          style: TextStyle(
                              fontFamily: 'ProductSans',
                              fontWeight: FontWeight.w500)),
                      subtitle: Text('Open file with an external app',
                          style: TextStyle(
                              fontFamily: 'ProductSans',
                              fontSize: 12,
                              color: AppColors.lightTextSecondary)),
                      contentPadding: EdgeInsets.zero,
                      onTap: () {
                        Navigator.pop(context);
                        _openWithExternalApp(file);
                      },
                    ),
                  ],
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportToDownloads(VaultedFile file) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          content: Row(
            children: [
              CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(AppColors.accent)),
              const SizedBox(width: 20),
              Expanded(
                  child: Text('Exporting ${file.originalName}...',
                      style: const TextStyle(fontFamily: 'ProductSans'))),
            ],
          ),
        ),
      );

      final downloadsDir = await PathUtils.getDownloadsDirectory();

      if (downloadsDir == null) {
        if (mounted) Navigator.pop(context);
        ToastUtils.showError('Could not access Downloads folder');
        return;
      }

      final destinationPath = '${downloadsDir.path}/${file.originalName}';
      final vaultService = ref.read(vaultServiceProvider);
      final exportedFile =
          await vaultService.exportFile(file.id, destinationPath);

      if (mounted) Navigator.pop(context);

      if (exportedFile != null) {
        ToastUtils.showSuccess('Exported to Downloads/${file.originalName}');
      } else {
        ToastUtils.showError('Failed to export file');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint('Error exporting file: $e');
      ToastUtils.showError('Failed to export file');
    }
  }

  Future<void> _openWithExternalApp(VaultedFile file) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          content: Row(
            children: [
              CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(AppColors.accent)),
              const SizedBox(width: 20),
              Expanded(
                  child: Text('Preparing ${file.originalName}...',
                      style: const TextStyle(fontFamily: 'ProductSans'))),
            ],
          ),
        ),
      );

      final vaultService = ref.read(vaultServiceProvider);
      final decryptedFile = await vaultService.getVaultedFile(file.id);

      if (mounted) Navigator.pop(context);

      if (decryptedFile != null && await decryptedFile.exists()) {
        final result = await AutoKillService.runSafe(
            () => OpenFilex.open(decryptedFile.path));
        if (result.type != ResultType.done) {
          ToastUtils.showError('No app found to open this file type');
        }
      } else {
        ToastUtils.showError('Failed to prepare file');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint('Error opening file: $e');
      ToastUtils.showError('Failed to open file');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentFile = _files[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        // Use translucent behavior so child widgets (like video control buttons)
        // can still receive tap events
        behavior: HitTestBehavior.translucent,
        onTap: _toggleControls,
        child: Stack(
          children: [
            // Main content
            if (currentFile.isImage)
              _buildImageGallery()
            else if (currentFile.isVideo)
              _buildVideoPlayer(currentFile)
            else
              _buildUnsupportedFile(currentFile),

            // Top controls
            if (_showControls) _buildTopControls(currentFile),

            // Bottom controls
            if (_showControls) _buildBottomControls(currentFile),

            // Slideshow indicator
            if (_isSlideshow)
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.slideshow,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Slideshow',
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'ProductSans',
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 18,
                          ),
                          onPressed: () => setState(() => _isSlideshow = false),
                          tooltip: 'Close slideshow',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 36, minHeight: 36),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageGallery() {
    return PhotoViewGallery.builder(
      scrollPhysics: const BouncingScrollPhysics(),
      builder: (context, index) {
        final file = _files[index];

        if (file.isEncrypted) {
          final decryptedFile = _decryptedFileCache[file.id];
          if (decryptedFile != null) {
            // Use customChild for encrypted images to handle decode errors
            return PhotoViewGalleryPageOptions.customChild(
              child: PhotoView.customChild(
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 3,
                heroAttributes: PhotoViewHeroAttributes(tag: file.id),
                child: Image.file(
                  decryptedFile,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    debugPrint('Error decoding encrypted image: $error');
                    return _buildImageErrorPlaceholder(file);
                  },
                ),
              ),
            );
          }
          // Loading placeholder
          return PhotoViewGalleryPageOptions.customChild(
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          );
        }

        // Use customChild with Image.file for proper error handling
        return PhotoViewGalleryPageOptions.customChild(
          child: PhotoView.customChild(
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 3,
            heroAttributes: PhotoViewHeroAttributes(tag: file.id),
            child: Image.file(
              File(file.vaultPath),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                debugPrint('Error decoding image file: $error');
                return _buildImageErrorPlaceholder(file);
              },
            ),
          ),
        );
      },
      itemCount: _files.length,
      loadingBuilder: (context, event) => Center(
        child: CircularProgressIndicator(
          value: event == null
              ? null
              : event.cumulativeBytesLoaded / (event.expectedTotalBytes ?? 1),
          color: Colors.white,
        ),
      ),
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      pageController: _pageController,
      onPageChanged: _onPageChanged,
    );
  }

  Widget _buildImageErrorPlaceholder(VaultedFile file) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: 80,
            color: Colors.white54,
          ),
          const SizedBox(height: 16),
          Text(
            file.originalName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontFamily: 'ProductSans',
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Unable to display this image',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 14,
              fontFamily: 'ProductSans',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'The file may be corrupted or in an unsupported format',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 12,
              fontFamily: 'ProductSans',
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPlayer(VaultedFile file) {
    if (_videoPhase != _VideoLoadPhase.ready || _videoController == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_videoPhase == _VideoLoadPhase.decrypting &&
                _decryptProgress != null) ...[
              SizedBox(
                width: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _decryptProgress,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${(_decryptProgress! * 100).round()}%',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 12),
              const Text(
                'Decrypting video...',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ] else ...[
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 12),
              Text(
                _videoPhase == _VideoLoadPhase.initializing
                    ? 'Loading video...'
                    : 'Preparing...',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ],
        ),
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio: _videoController!.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(_videoController!),
            if (_showControls)
              GestureDetector(
                onTap: () {},
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.replay_10, size: 36),
                      color: Colors.white,
                      tooltip: 'Back 10 seconds',
                      onPressed: _skipBackward,
                    ),
                    IconButton(
                      icon: Icon(
                        _isVideoPlaying ? Icons.pause : Icons.play_arrow,
                        size: 48,
                        color: Colors.white,
                      ),
                      tooltip: _isVideoPlaying ? 'Pause' : 'Play',
                      onPressed: _toggleVideoPlayback,
                    ),
                    IconButton(
                      icon: const Icon(Icons.forward_10, size: 36),
                      color: Colors.white,
                      tooltip: 'Forward 10 seconds',
                      onPressed: _skipForward,
                    ),
                  ],
                ),
              ),
            // Tap area needed to toggle controls
            if (!_showControls)
              GestureDetector(
                onTap: _toggleControls,
                behavior: HitTestBehavior.translucent,
                child: Container(color: Colors.transparent),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnsupportedFile(VaultedFile file) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.insert_drive_file,
            size: 100,
            color: Colors.white54,
          ),
          const SizedBox(height: 16),
          Text(
            file.originalName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontFamily: 'ProductSans',
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Preview not available for this file type',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 14,
              fontFamily: 'ProductSans',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopControls(VaultedFile file) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black54,
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              tooltip: 'Back',
              onPressed: () => Navigator.pop(context),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.originalName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'ProductSans',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${_currentIndex + 1} of ${_files.length}',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontFamily: 'ProductSans',
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                file.isFavorite ? Icons.favorite : Icons.favorite_border,
                color: file.isFavorite ? Colors.red : Colors.white,
              ),
              tooltip: 'Favorite',
              onPressed: _toggleFavorite,
            ),
            IconButton(
              icon: const Icon(Icons.info_outline, color: Colors.white),
              tooltip: 'File info',
              onPressed: _showFileInfo,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls(VaultedFile file) {
    if (file.isVideo) return _buildVideoBottomControls(file);
    return _buildImageBottomControls(file);
  }

  Widget _buildVideoBottomControls(VaultedFile file) {
    final position = _videoController?.value.position ?? Duration.zero;
    final duration = _videoController?.value.duration ?? Duration.zero;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: GestureDetector(
        onTap: () {},
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 16,
            right: 16,
            top: 20,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black87,
                Colors.transparent,
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Progress Bar and Time
              Row(
                children: [
                  Text(
                    _formatDuration(position),
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'ProductSans',
                      fontSize: 12,
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        thumbColor: context.accentColor,
                        activeTrackColor: context.accentColor,
                        inactiveTrackColor: Colors.white24,
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6.0),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 14.0),
                      ),
                      child: Slider(
                        value: position.inMilliseconds
                            .toDouble()
                            .clamp(0.0, duration.inMilliseconds.toDouble()),
                        min: 0.0,
                        max: duration.inMilliseconds.toDouble(),
                        onChanged: (value) {
                          _seekVideo(Duration(milliseconds: value.toInt()));
                        },
                      ),
                    ),
                  ),
                  Text(
                    _formatDuration(duration),
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'ProductSans',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                   IconButton(
                      icon: Icon(
                        _isLooping ? Icons.repeat_one : Icons.repeat,
                        color: _isLooping ? AppColors.accent : Colors.white,
                      ),
                      tooltip: 'Loop',
                      onPressed: _toggleLooping,
                    ),
                   IconButton(
                      icon: Icon(
                        _isMuted ? Icons.volume_off : Icons.volume_up,
                       color: Colors.white,
                     ),
                     tooltip: _isMuted ? 'Unmute' : 'Mute',
                     onPressed: () {
                      setState(() {
                        _isMuted = !_isMuted;
                        _videoController?.setVolume(_isMuted ? 0.0 : 1.0);
                      });
                    },
                  ),
                   IconButton(
                     icon: Icon(
                       _isVideoPlaying
                           ? Icons.pause_circle_filled
                           : Icons.play_circle_filled,
                       color: Colors.white,
                       size: 48,
                     ),
                     tooltip: _isVideoPlaying ? 'Pause' : 'Play',
                     onPressed: _toggleVideoPlayback,
                   ),
                   IconButton(
                     icon: Text(
                       '${_playbackSpeed}x',
                       style: const TextStyle(
                         color: Colors.white,
                         fontWeight: FontWeight.bold,
                         fontSize: 14,
                         fontFamily: 'ProductSans',
                       ),
                     ),
                     tooltip: 'Playback speed',
                     onPressed: () {
                      setState(() {
                        if (_playbackSpeed == 1.0) {
                          _playbackSpeed = 1.5;
                        } else if (_playbackSpeed == 1.5) {
                          _playbackSpeed = 2.0;
                        } else if (_playbackSpeed == 2.0) {
                          _playbackSpeed = 0.5;
                        } else {
                          _playbackSpeed = 1.0;
                        }
_videoController?.setPlaybackSpeed(_playbackSpeed);
                      });
                     },
                   ),
                    IconButton(
                      icon: Icon(
                        _forceLandscape
                            ? Icons.stay_current_portrait
                            : Icons.stay_current_landscape,
                        color: _forceLandscape
                            ? AppColors.accent
                            : Colors.white,
                      ),
                      tooltip: _forceLandscape
                          ? 'Play vertically'
                          : 'Play horizontally',
                      onPressed: _toggleOrientation,
                    ),
                 ],
               ),
             ],
           ),
         ),
       ),
     );
   }

  Widget _buildImageBottomControls(VaultedFile file) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      // Absorb taps to prevent parent GestureDetector from toggling controls
      child: GestureDetector(
        onTap: () {}, // Absorb tap to prevent propagation
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 8,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black54,
                Colors.transparent,
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Previous
                  IconButton(
                    icon: const Icon(Icons.skip_previous, color: Colors.white),
                    tooltip: 'Previous',
                    onPressed: _currentIndex > 0
                        ? () => _pageController.previousPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            )
                        : null,
                  ),
                  // Slideshow (only for images)
                  if (_files.where((f) => f.isImage).length > 1)
                    IconButton(
                      icon: Icon(
                        _isSlideshow ? Icons.stop : Icons.slideshow,
                        color: Colors.white,
                      ),
                      tooltip: 'Slideshow',
                      onPressed: _showSlideshowSettings,
                    ),
                  // Share/Export
                  IconButton(
                    icon: const Icon(Icons.share, color: Colors.white),
                    tooltip: 'Share',
                    onPressed: () => _showExportOptions(file),
                  ),
                  // Delete
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.white),
                    tooltip: 'Delete',
                    onPressed: () => _confirmDelete(file),
                  ),
                  // Next
                  IconButton(
                    icon: const Icon(Icons.skip_next, color: Colors.white),
                    tooltip: 'Next',
                    onPressed: _currentIndex < _files.length - 1
                        ? () => _pageController.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            )
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(VaultedFile file) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          'Delete File',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textPrimary,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${file.originalName}"?',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: context.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final success = await ref
                  .read(vaultNotifierProvider.notifier)
                  .deleteFiles([file.id]);
              if (success) {
                ToastUtils.showSuccess('File deleted');
                if (_files.length == 1) {
                  if (mounted) Navigator.pop(context);
                } else {
                  // Remove from list and update
                  setState(() {
                    _files.remove(file);
                    if (_currentIndex >= _files.length) {
                      _currentIndex = _files.length - 1;
                    }
                  });
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text(
              'Delete',
              style: TextStyle(fontFamily: 'ProductSans'),
            ),
          ),
        ],
      ),
    );
  }
}
