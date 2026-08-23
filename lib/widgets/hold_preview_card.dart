import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

/// Computes a clamped on-screen rect for the hold-to-preview card so it stays
/// fully visible, preferring a spot above the finger.
Rect holdPreviewRect(Offset finger, Size screen, Size card) {
  const margin = 12.0;

  final left = (finger.dx - card.width / 2).clamp(
    margin,
    (screen.width - card.width - margin).clamp(margin, double.infinity),
  ).toDouble();
  var top = finger.dy - card.height - 56;
  if (top < margin) top = finger.dy + 56;
  top = top.clamp(
    margin,
    (screen.height - card.height - margin).clamp(margin, double.infinity),
  );

  return Rect.fromLTWH(left, top, card.width, card.height);
}

/// Floating card shown while the user holds a grid tile in the media picker.
/// Follows [position]; swaps content when [asset] changes (peek & select).
class HoldPreviewCard extends StatelessWidget {
  final ValueListenable<AssetEntity?> asset;
  final ValueListenable<Offset> position;

  const HoldPreviewCard({super.key, required this.asset, required this.position});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Offset>(
      valueListenable: position,
      builder: (context, finger, _) {
        final screen = MediaQuery.of(context).size;
        final side =
            (screen.shortestSide * 0.65).clamp(200.0, 340.0).toDouble();
        final rect = holdPreviewRect(finger, screen, Size(side, side));

        return Positioned.fromRect(
          rect: rect,
          child: IgnorePointer(
            child: ValueListenableBuilder<AssetEntity?>(
              valueListenable: asset,
              builder: (context, asset, _) {
                if (asset == null) return const SizedBox.shrink();
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  builder: (context, t, child) => Opacity(
                    opacity: t,
                    child: Transform.scale(scale: 0.9 + 0.1 * t, child: child),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 24,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      // Keyed so a new hold starts fresh (no stale video frame).
                      child: KeyedSubtree(
                        key: ValueKey(asset.id),
                        child: Container(
                          color: Colors.black,
                          child: _AssetPreviewContent(asset: asset),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _AssetPreviewContent extends StatelessWidget {
  final AssetEntity asset;

  const _AssetPreviewContent({required this.asset});

  @override
  Widget build(BuildContext context) {
    if (asset.type == AssetType.video) return _VideoPreview(asset: asset);
    return _ImagePreview(asset: asset);
  }
}

class _ImagePreview extends StatefulWidget {
  final AssetEntity asset;

  const _ImagePreview({required this.asset});

  @override
  State<_ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<_ImagePreview> {
  late final Future<Uint8List?> _future = widget.asset.thumbnailDataWithSize(
    const ThumbnailSize(1200, 1200),
    quality: 90,
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null && bytes.isNotEmpty) {
          return Image.memory(bytes, fit: BoxFit.contain);
        }
        if (snapshot.hasError) {
          return const Center(
            child: Icon(Icons.broken_image, color: Colors.white54),
          );
        }
        return const Center(
          child: CircularProgressIndicator(color: Colors.white70),
        );
      },
    );
  }
}

class _VideoPreview extends StatefulWidget {
  final AssetEntity asset;

  const _VideoPreview({required this.asset});

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  VideoPlayerController? _controller;
  Timer? _initTimer;
  late final Future<Uint8List?> _thumb = widget.asset.thumbnailDataWithSize(
    const ThumbnailSize(1200, 1200),
    quality: 90,
  );

  @override
  void initState() {
    super.initState();
    // ponytail: 150ms delay so quick accidental holds never touch disk.
    _initTimer = Timer(const Duration(milliseconds: 150), _init);
  }

  Future<void> _init() async {
    try {
      final file = await widget.asset.file;
      if (file == null || !mounted) return;
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
    } catch (_) {
      if (mounted) setState(() => _controller = null);
    }
  }

  @override
  void dispose() {
    _initTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return FutureBuilder<Uint8List?>(
        future: _thumb,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes != null && bytes.isNotEmpty) {
            return Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(bytes, fit: BoxFit.contain),
                const Center(
                  child: Icon(Icons.play_arrow,
                      size: 48, color: Colors.white70),
                ),
              ],
            );
          }
          return const SizedBox.expand();
        },
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio:
            controller.value.aspectRatio == 0
                ? 1
                : controller.value.aspectRatio,
        child: VideoPlayer(controller),
      ),
    );
  }
}
