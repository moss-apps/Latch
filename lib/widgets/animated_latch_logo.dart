import 'package:flutter/material.dart';

/// Latch dot-matrix logo that assembles on entrance: each of the 21 dots
/// flies in from a radial-outward start and settles into its final position,
/// staggered so the logo blooms from the center outward. Geometry is taken
/// verbatim from assets/locker_logo_nobg.svg (viewBox 481x652, r=31.36).
class AnimatedLatchLogo extends StatelessWidget {
  final Animation<double> progress;
  final double size;
  final Color color;

  const AnimatedLatchLogo({
    super.key,
    required this.progress,
    this.size = 96,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _LatchLogoPainter(progress: progress, color: color),
    );
  }
}

class _Dot {
  final Offset target;
  final Offset start;
  final double delay;
  final double duration;
  const _Dot(this.target, this.start, this.delay, this.duration);
}

class _LatchLogoPainter extends CustomPainter {
  final Animation<double> progress;
  final Color color;

  _LatchLogoPainter({required this.progress, required this.color})
      : super(repaint: progress);

  // Raw circle centers (cx, cy) from the SVG.
  static const List<Offset> _raw = [
    Offset(31.3605, 527.102),
    Offset(31.3605, 422.567),
    Offset(31.3605, 318.031),
    Offset(31.3605, 620.339),
    Offset(80.8761, 224.795),
    Offset(80.8761, 120.260),
    Offset(397.517, 224.795),
    Offset(397.517, 120.260),
    Offset(135.604, 31.3606),
    Offset(345.395, 31.3606),
    Offset(241.151, 31.3606),
    Offset(449.639, 527.102),
    Offset(449.639, 422.567),
    Offset(449.639, 318.031),
    Offset(449.639, 620.339),
    Offset(135.604, 318.031),
    Offset(240.140, 318.031),
    Offset(344.676, 318.031),
    Offset(135.604, 620.339),
    Offset(240.140, 620.339),
    Offset(344.676, 620.339),
  ];

  static const double _viewW = 481.0;
  static const double _viewH = 652.0;
  static const double _dotR = 31.3607;

  // Dots staggered so the nearest to the logo centroid bloom first.
  static final List<_Dot> dots = _buildDots();
  static List<_Dot> _buildDots() {
    double cx = 0, cy = 0;
    for (final o in _raw) {
      cx += o.dx;
      cy += o.dy;
    }
    cx /= _raw.length;
    cy /= _raw.length;
    final center = Offset(cx, cy);

    final order = List<int>.generate(_raw.length, (i) => i)
      ..sort((a, b) =>
          (_raw[a] - center).distance.compareTo((_raw[b] - center).distance));

    const staggerSpan = 1.0;
    const dotDur = 0.85;
    final n = _raw.length;
    final out = <_Dot>[];
    for (var k = 0; k < n; k++) {
      final o = _raw[order[k]];
      final radial = (o - center) * 1.6;
      final start = Offset(center.dx + radial.dx, center.dy + radial.dy);
      final delay = (k / (n - 1)) * staggerSpan;
      out.add(_Dot(o, start, delay, dotDur));
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.height / _viewH;
    final scaledW = _viewW * scale;
    final xOff = (size.width - scaledW) / 2;
    final r = _dotR * scale;

    final paint = Paint()..style = PaintingStyle.fill;
    for (final d in dots) {
      final local = ((progress.value - d.delay) / d.duration).clamp(0.0, 1.0);
      final e = Curves.easeOut.transform(local);
      final x = xOff + (d.start.dx + (d.target.dx - d.start.dx) * e) * scale;
      final y = (d.start.dy + (d.target.dy - d.start.dy) * e) * scale;
      paint.color = color.withValues(alpha: e);
      canvas.drawCircle(Offset(x, y), r * (0.3 + 0.7 * e), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LatchLogoPainter old) => color != old.color;
}
