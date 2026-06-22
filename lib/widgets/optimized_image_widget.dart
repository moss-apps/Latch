import 'package:flutter/material.dart';
import 'dart:io';

/// Optimized image widget with caching and performance improvements
class OptimizedImageWidget extends StatelessWidget {
  final File imageFile;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? errorWidget;
  final bool enableMemoryCache;
  
  const OptimizedImageWidget({
    super.key,
    required this.imageFile,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
    this.enableMemoryCache = true,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Image.file(
        imageFile,
        fit: fit,
        width: width,
        height: height,
        cacheWidth: width?.toInt(),
        cacheHeight: height?.toInt(),
        errorBuilder: (context, error, stackTrace) {
          return errorWidget ?? 
              const Center(
                child: Icon(Icons.error_outline, color: Colors.red),
              );
        },
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: child,
          );
        },
      ),
    );
  }
}
