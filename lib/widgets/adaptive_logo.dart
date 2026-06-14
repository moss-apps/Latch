import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// A logo widget that automatically switches between the light and dark
/// variants of the Latch logo so it stays visible in any theme.
class AdaptiveLogo extends StatelessWidget {
  final double size;
  final BoxFit fit;

  const AdaptiveLogo({
    super.key,
    this.size = 100,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SvgPicture.asset(
      isDark
          ? 'assets/reverse_locker_logo_nobg.svg'
          : 'assets/locker_logo_nobg.svg',
      width: size,
      height: size,
      fit: fit,
    );
  }
}
