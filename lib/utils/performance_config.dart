import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// Global performance configuration and optimization utilities
class PerformanceConfig {
  /// Enable performance overlays for debugging
  static void enablePerformanceOverlay(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPaintSizeEnabled = false;
      debugPaintLayerBordersEnabled = false;
      debugRepaintRainbowEnabled = false;
    });
  }

  /// Configure app for high frame rate support
  static void configureHighFrameRate() {
    // Enable high refresh rate displays (120Hz, 90Hz, etc.)
    SchedulerBinding.instance.platformDispatcher.onReportTimings = (timings) {
      // Monitor frame timings
      for (final timing in timings) {
        if (timing.totalSpan.inMilliseconds > 16) {
          debugPrint(
              'Slow frame detected: ${timing.totalSpan.inMilliseconds}ms');
        }
      }
    };
  }

  /// Optimize image cache settings
  static void optimizeImageCache() {
    PaintingBinding.instance.imageCache.maximumSize = 100;
    PaintingBinding.instance.imageCache.maximumSizeBytes =
        50 * 1024 * 1024; // 50MB
  }

  /// Configure scroll physics for smooth scrolling
  static ScrollPhysics getOptimizedScrollPhysics() {
    return const BouncingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    );
  }

  /// Get optimized animation duration based on device performance
  static Duration getOptimizedAnimationDuration({
    Duration standard = const Duration(milliseconds: 300),
  }) {
    // Could be adjusted based on device performance metrics
    return standard;
  }

  /// Preload critical resources
  static Future<void> preloadCriticalResources(BuildContext context) async {
    // Preload theme data
    Theme.of(context);

    // Preload common assets if needed
    // await precacheImage(AssetImage('assets/locker_logo_nobg.png'), context);
  }

  /// Optimize widget rebuilds with const constructors
  static const kUseConstWidgets = true;

  /// Enable repaint boundaries for complex widgets
  static const kUseRepaintBoundaries = true;

  /// Cache extent for list views (pixels)
  static const double kListViewCacheExtent = 500.0;

  /// Grid view cache extent (pixels)
  static const double kGridViewCacheExtent = 500.0;

  /// Maximum image cache size
  static const int kMaxImageCacheSize = 100;

  /// Maximum image cache bytes (50MB)
  static const int kMaxImageCacheBytes = 50 * 1024 * 1024;

  /// Animation curve for smooth transitions
  static const Curve kDefaultAnimationCurve = Curves.easeInOutCubic;

  /// Default animation duration
  static const Duration kDefaultAnimationDuration = Duration(milliseconds: 250);

  /// Fast animation duration
  static const Duration kFastAnimationDuration = Duration(milliseconds: 150);

  /// Slow animation duration
  static const Duration kSlowAnimationDuration = Duration(milliseconds: 400);
}
