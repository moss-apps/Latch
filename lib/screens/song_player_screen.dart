import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../models/vaulted_file.dart';
import '../services/flick_integration_service.dart';
import '../providers/vault_providers.dart';
import '../services/auto_kill_service.dart';
import '../themes/app_colors.dart';
import '../utils/toast_utils.dart';

class SongPlayerScreen extends ConsumerStatefulWidget {
  final VaultedFile file;

  const SongPlayerScreen({
    super.key,
    required this.file,
  });

  @override
  ConsumerState<SongPlayerScreen> createState() => _SongPlayerScreenState();
}

class _SongPlayerScreenState extends ConsumerState<SongPlayerScreen>
    with WidgetsBindingObserver {
  final AudioPlayer _player = AudioPlayer();

  bool _isLoading = true;
  bool _isCheckingFlick = true;
  bool _isFlickAvailable = false;
  bool _reenableAutoKillOnResume = false;
  String? _error;
  File? _playbackFile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSong();
    _loadFlickAvailability();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_reenableAutoKillOnResume) {
      AutoKillService.setEnabled(true);
    }
    _player.dispose();
    // Clean up temp decrypted files to prevent disk leaks
    _cleanupTempFiles();
    super.dispose();
  }

  void _cleanupTempFiles() {
    try {
      ref.read(vaultServiceProvider).cleanupTemp();
    } catch (e) {
      debugPrint('Error cleaning up temp files: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _reenableAutoKillOnResume) {
      _reenableAutoKillOnResume = false;
      AutoKillService.setEnabled(true);
    }
  }

  Future<void> _loadFlickAvailability() async {
    final isAvailable = await FlickIntegrationService.isAvailable();
    if (!mounted) return;

    setState(() {
      _isFlickAvailable = isAvailable;
      _isCheckingFlick = false;
    });
  }

  Future<void> _loadSong() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final vaultService = ref.read(vaultServiceProvider);
      final file = widget.file.isEncrypted && widget.file.encryptionIv != null
          ? await vaultService.getVaultedFile(widget.file.id)
          : File(widget.file.vaultPath);

      if (file == null || !await file.exists()) {
        setState(() {
          _error = 'Failed to prepare song';
          _isLoading = false;
        });
        return;
      }

      _playbackFile = file;
      await _player.setFilePath(file.path);

      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load song: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _togglePlayback() async {
    try {
      if (_player.playing) {
        await _player.pause();
      } else {
        await _player.play();
      }
    } catch (e) {
      ToastUtils.showError('Playback failed: $e');
    }
  }

  Future<void> _seek(Duration position) async {
    final duration = _player.duration;
    if (duration == null) return;
    final target = position > duration ? duration : position;
    await _player.seek(target);
  }

  void _toggleFavorite() async {
    await ref.read(vaultNotifierProvider.notifier).toggleFavorite(widget.file.id);
    ToastUtils.showSuccess(
      widget.file.isFavorite ? 'Removed from favorites' : 'Added to favorites',
    );
  }

  Future<void> _exportToDownloads() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          content: Row(
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(AppColors.accent),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  'Exporting ${widget.file.originalName}...',
                  style: const TextStyle(fontFamily: 'ProductSans'),
                ),
              ),
            ],
          ),
        ),
      );

      Directory? downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
        if (!await downloadsDir.exists()) {
          downloadsDir = await getExternalStorageDirectory();
        }
      } else {
        downloadsDir = await getDownloadsDirectory();
      }

      if (downloadsDir == null) {
        if (mounted) Navigator.pop(context);
        ToastUtils.showError('Could not access Downloads folder');
        return;
      }

      final destinationPath = '${downloadsDir.path}/${widget.file.originalName}';
      final exportedFile = await ref
          .read(vaultServiceProvider)
          .exportFile(widget.file.id, destinationPath);

      if (mounted) Navigator.pop(context);

      if (exportedFile != null) {
        ToastUtils.showSuccess('Exported to Downloads/${widget.file.originalName}');
      } else {
        ToastUtils.showError('Failed to export file');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ToastUtils.showError('Failed to export file: $e');
    }
  }

  Future<void> _openWithExternalApp() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          content: Row(
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(AppColors.accent),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  'Preparing ${widget.file.originalName}...',
                  style: const TextStyle(fontFamily: 'ProductSans'),
                ),
              ),
            ],
          ),
        ),
      );

      final decryptedFile = await ref
          .read(vaultServiceProvider)
          .getVaultedFile(widget.file.id);

      if (mounted) Navigator.pop(context);

      if (decryptedFile != null && await decryptedFile.exists()) {
        final result =
            await AutoKillService.runSafe(() => OpenFilex.open(decryptedFile.path));
        if (result.type != ResultType.done) {
          ToastUtils.showError('No app found to open this file type');
        }
      } else {
        ToastUtils.showError('Failed to prepare file');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ToastUtils.showError('Failed to open file: $e');
    }
  }

  Future<void> _playWithFlick() async {
    final playbackFile = _playbackFile;
    if (playbackFile == null) {
      ToastUtils.showError('Song is not ready yet');
      return;
    }

    try {
      await AutoKillService.setEnabled(false);
      _reenableAutoKillOnResume = true;

      await FlickIntegrationService.openAudioFile(
        filePath: playbackFile.path,
        mimeType: widget.file.mimeType,
      );
    } on PlatformException catch (e) {
      _reenableAutoKillOnResume = false;
      await AutoKillService.setEnabled(true);

      final message = switch (e.code) {
        'FLICK_NOT_INSTALLED' => 'Flick is not installed',
        'FLICK_UNAVAILABLE' => 'Flick cannot open this song',
        'FILE_NOT_FOUND' => 'Failed to prepare song for Flick',
        _ => e.message ?? 'Failed to open Flick',
      };
      ToastUtils.showError(message);
    } catch (e) {
      _reenableAutoKillOnResume = false;
      await AutoKillService.setEnabled(true);
      ToastUtils.showError('Failed to open Flick: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: Text(
          'Song Player',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _toggleFavorite,
            icon: Icon(
              widget.file.isFavorite ? Icons.favorite : Icons.favorite_border,
              color: widget.file.isFavorite ? Colors.red : context.textPrimary,
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: context.textPrimary),
            onSelected: (value) {
              switch (value) {
                case 'export':
                  _exportToDownloads();
                  break;
                case 'external':
                  _openWithExternalApp();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'export', child: Text('Export to Downloads')),
              PopupMenuItem(value: 'external', child: Text('Open with...')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(context.accentColor),
                  ),
                )
              : _error != null
                  ? _buildErrorState()
                  : _buildPlayer(),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(
            _error ?? 'Something went wrong',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'ProductSans',
              fontSize: 16,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadSong,
            style: ElevatedButton.styleFrom(
              backgroundColor: context.accentColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayer() {
    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      builder: (context, playerSnapshot) {
        final playerState = playerSnapshot.data;
        final isPlaying = playerState?.playing ?? false;
        final processingState = playerState?.processingState;

        return StreamBuilder<Duration?>(
          stream: _player.durationStream,
          builder: (context, durationSnapshot) {
            final duration = durationSnapshot.data ?? Duration.zero;

            return StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (context, positionSnapshot) {
                final position = positionSnapshot.data ?? Duration.zero;
                final sliderMax = duration.inMilliseconds.toDouble();
                final sliderValue = sliderMax == 0
                    ? 0.0
                    : position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: const Icon(
                        Icons.music_note,
                        size: 72,
                        color: Colors.purple,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      widget.file.originalName,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${widget.file.extension.toUpperCase()} • ${widget.file.formattedSize}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        fontSize: 14,
                        color: context.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Slider(
                      value: sliderValue,
                      max: sliderMax == 0 ? 1 : sliderMax,
                      activeColor: context.accentColor,
                      onChanged: sliderMax == 0
                          ? null
                          : (value) => _seek(Duration(milliseconds: value.round())),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(position),
                            style: TextStyle(
                              fontFamily: 'ProductSans',
                              color: context.textSecondary,
                            ),
                          ),
                          Text(
                            _formatDuration(duration),
                            style: TextStyle(
                              fontFamily: 'ProductSans',
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: position > const Duration(seconds: 10)
                              ? () => _seek(position - const Duration(seconds: 10))
                              : () => _seek(Duration.zero),
                          icon: Icon(
                            Icons.replay_10,
                            color: context.textPrimary,
                            size: 32,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: context.accentColor,
                          ),
                          child: IconButton(
                            onPressed: processingState == ProcessingState.loading ||
                                    processingState == ProcessingState.buffering
                                ? null
                                : _togglePlayback,
                            icon: Icon(
                              isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                              size: 40,
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        IconButton(
                          onPressed: duration > const Duration(seconds: 10)
                              ? () => _seek(position + const Duration(seconds: 10))
                              : null,
                          icon: Icon(
                            Icons.forward_10,
                            color: context.textPrimary,
                            size: 32,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (!_isCheckingFlick && _isFlickAvailable && _playbackFile != null)
                      FilledButton.icon(
                        onPressed: _playWithFlick,
                        icon: const Icon(Icons.music_note),
                        label: const Text('Play with Flick'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    if (!_isCheckingFlick && _isFlickAvailable && _playbackFile != null)
                      const SizedBox(height: 12),
                    if (_playbackFile != null)
                      OutlinedButton.icon(
                        onPressed: _openWithExternalApp,
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Open with External App'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.textPrimary,
                          side: BorderSide(color: context.borderColor),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;

    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}
