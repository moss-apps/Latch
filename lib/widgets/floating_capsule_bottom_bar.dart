import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../themes/app_colors.dart';

/// Which end the import (feature) button parks on when the total item count
/// is even and there is no exact middle slot.
enum FeatureSide { left, right }

/// A single tappable entry in the bottom bar.
class NavTab {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const NavTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
}

/// A squircle (superellipse) rotated 45° into a curved-diamond orientation.
/// Convex continuously-curved sides with smoothly rounded points.
/// `n` is the superellipse exponent: 2 = circle, higher = squarer
/// (~4-5 is the premium squircle sweet spot).
class CurvedDiamondBorder extends OutlinedBorder {
  final double n;
  final double rotation;

  const CurvedDiamondBorder({
    this.n = 4.5,
    this.rotation = math.pi / 4,
    super.side,
  });

  static double _sgnPow(double v, double e) =>
      (v < 0 ? -1.0 : 1.0) * math.pow(v.abs(), e).toDouble();

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    const steps = 80;
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final cosR = math.cos(rotation);
    final sinR = math.sin(rotation);

    final pts = <Offset>[];
    var maxExt = 0.0;
    for (var i = 0; i < steps; i++) {
      final t = 2 * math.pi * i / steps;
      final ux = _sgnPow(math.cos(t), 2 / n);
      final uy = _sgnPow(math.sin(t), 2 / n);
      final x = ux * cosR - uy * sinR;
      final y = ux * sinR + uy * cosR;
      final ext = x.abs() > y.abs() ? x.abs() : y.abs();
      if (ext > maxExt) maxExt = ext;
      pts.add(Offset(x, y));
    }
    final half = rect.width < rect.height ? rect.width / 2 : rect.height / 2;
    final s = half / maxExt;

    final path = Path();
    for (var i = 0; i < steps; i++) {
      final dx = cx + pts[i].dx * s;
      final dy = cy + pts[i].dy * s;
      if (i == 0) {
        path.moveTo(dx, dy);
      } else {
        path.lineTo(dx, dy);
      }
    }
    return path..close();
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  ShapeBorder scale(double t) =>
      CurvedDiamondBorder(n: n, rotation: rotation, side: side.scale(t));

  @override
  CurvedDiamondBorder copyWith({
    BorderSide? side,
    double? n,
    double? rotation,
  }) =>
      CurvedDiamondBorder(
        n: n ?? this.n,
        rotation: rotation ?? this.rotation,
        side: side ?? this.side,
      );

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}
}

/// Floating capsule bottom bar.
///
/// Total slots = tabs + the feature (import) button, capped to 5.
/// When the total is odd the feature sits dead-center and the diamond pokes
/// above the capsule; when even it parks on [featureSide] inside the capsule.
class FloatingCapsuleBottomBar extends StatelessWidget {
  static const int _maxSlots = 5;

  final List<NavTab> tabs;
  final NavTab feature;
  final FeatureSide featureSide;
  final bool showFeature;

  // Geometry
  static const double _capsuleHeight = 62;
  static const double _capsuleRadius = 31;
  static const double _tabWidth = 64;
  static const double _elevatedDiamond = 58;
  static const double _inlineDiamond = 44;
  static const double _protrusion = 20;
  static const double _squircleN = 4.5;

  const FloatingCapsuleBottomBar({
    super.key,
    required this.tabs,
    required this.feature,
    this.featureSide = FeatureSide.right,
    this.showFeature = true,
  });

  @override
  Widget build(BuildContext context) {
    // ponytail: hard cap at 5 total slots (feature + up to 4 tabs).
    final visibleTabs = (tabs.length >= _maxSlots)
        ? tabs.sublist(0, _maxSlots - 1)
        : tabs;

    final slots = visibleTabs.length + (showFeature ? 1 : 0);
    final featureInMiddle = showFeature && slots.isOdd;

    final accent = context.accentColor;
    final totalHeight = featureInMiddle
        ? _capsuleHeight + _protrusion
        : _capsuleHeight;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.of(context).padding.bottom + 10,
      ),
      child: SizedBox(
        height: totalHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Center(
                child: _capsule(context, visibleTabs, accent, featureInMiddle),
              ),
            ),
            if (featureInMiddle)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Center(child: _diamond(context, accent, elevated: true)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _capsule(
    BuildContext context,
    List<NavTab> tabs,
    Color accent,
    bool featureInMiddle,
  ) {
    List<Widget> rowChildren;
    if (featureInMiddle) {
      // Reserve a centered gap for the protruding diamond.
      final half = tabs.length ~/ 2;
      final left = tabs.sublist(0, half);
      final right = tabs.sublist(half);
      rowChildren = [
        for (final t in left) _tab(context, t),
        SizedBox(width: _elevatedDiamond + 6),
        for (final t in right) _tab(context, t),
      ];
    } else {
      final tabsRow = tabs.map((t) => _tab(context, t)).toList();
      if (!showFeature) {
        rowChildren = tabsRow;
      } else if (featureSide == FeatureSide.left) {
        rowChildren = [_inlineDiamondSlot(context, accent), ...tabsRow];
      } else {
        rowChildren = [...tabsRow, _inlineDiamondSlot(context, accent)];
      }
    }

    return Container(
      height: _capsuleHeight,
      decoration: BoxDecoration(
        color: context.backgroundColor,
        borderRadius: BorderRadius.circular(_capsuleRadius),
        border: Border.all(color: context.borderColor.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDarkMode ? 0.5 : 0.18),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(mainAxisSize: MainAxisSize.min, children: rowChildren),
    );
  }

  Widget _tab(BuildContext context, NavTab tab) {
    final accent = context.accentColor;
    final color = tab.selected ? accent : context.textTertiary;
    return SizedBox(
      width: _tabWidth,
      child: Tooltip(
        message: tab.label,
        child: InkWell(
          onTap: tab.onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(tab.icon, size: 22, color: color),
                const SizedBox(height: 3),
                Text(
                  tab.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 10,
                    fontWeight: tab.selected ? FontWeight.w600 : FontWeight.normal,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _inlineDiamondSlot(BuildContext context, Color accent) {
    return SizedBox(
      width: _tabWidth,
      child: Center(child: _diamond(context, accent, elevated: false)),
    );
  }

  Widget _diamond(BuildContext context, Color accent, {required bool elevated}) {
    final size = elevated ? _elevatedDiamond : _inlineDiamond;
    return Tooltip(
      message: feature.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: feature.onTap,
          customBorder: const CurvedDiamondBorder(n: _squircleN),
          child: Container(
            width: size,
            height: size,
            decoration: ShapeDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accent, accent.withValues(alpha: 0.82)],
              ),
              shadows: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.45),
                  blurRadius: elevated ? 16 : 8,
                  offset: const Offset(0, 6),
                ),
              ],
              shape: const CurvedDiamondBorder(n: _squircleN),
            ),
            child: Icon(
              feature.icon,
              color: Colors.white,
              size: elevated ? 28 : 24,
            ),
          ),
        ),
      ),
    );
  }
}
