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
/// All destinations remain available. When labels no longer fit, the tabs
/// scroll independently of the always-reachable import action.
class FloatingCapsuleBottomBar extends StatelessWidget {
  final List<NavTab> tabs;
  final NavTab feature;
  final FeatureSide featureSide;
  final bool showFeature;

  // Geometry
  static const double _capsuleHeight = 62;
  static const double _capsuleRadius = 31;
  static const double _tabWidth = 64;
  static const double _elevatedDiamond = 58;
  static const double _inlineDiamond = 48;
  static const double _protrusion = 20;
  static const double _squircleN = 4.5;

  static const _labelStyle = TextStyle(
      fontFamily: 'GoogleSansFlex',
      fontSize: 12,
      height: 1.3,
      fontWeight: FontWeight.w600);

  static double _height(BuildContext context) {
    final painter = TextPainter(
      text: const TextSpan(text: 'Ag', style: _labelStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    // Include vertical padding and the capsule's one-pixel borders. Measure
    // the actual line rather than assuming the system text scaler is linear.
    final height = math.max(_capsuleHeight, 22 + 3 + painter.height + 16 + 2);
    painter.dispose();
    return height.ceilToDouble();
  }

  /// Conservative footprint, excluding safe-area insets, for extended bodies.
  static double bottomFootprintFor(BuildContext context) =>
      _height(context) + _protrusion + 10;

  const FloatingCapsuleBottomBar({
    super.key,
    required this.tabs,
    required this.feature,
    this.featureSide = FeatureSide.right,
    this.showFeature = true,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.accentColor;
    final widths = tabs.map((tab) {
      final painter = TextPainter(
        text: TextSpan(text: tab.label, style: _labelStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = math.max(_tabWidth, painter.width + 24);
      painter.dispose();
      return width;
    }).toList();
    final height = _height(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          10,
        ),
        child: LayoutBuilder(builder: (context, constraints) {
          final requiredWidth = widths.fold<double>(12, (a, b) => a + b) +
              (showFeature ? _tabWidth : 0);
          final fits = requiredWidth <= constraints.maxWidth;
          final featureInMiddle = fits &&
              showFeature &&
              (tabs.length + 1).isOdd &&
              widths.every((width) => width == _tabWidth);
          final tabWidgets = [
            for (var i = 0; i < tabs.length; i++)
              _tab(context, tabs[i], widths[i], height)
          ];
          final featureSlot = SizedBox(
              width: _tabWidth,
              height: height,
              child: Center(child: _diamond(context, accent, elevated: false)));
          final List<Widget> children;
          if (!fits) {
            children = [
              if (showFeature && featureSide == FeatureSide.left) featureSlot,
              Expanded(
                  child: _ScrollableTabs(tabs: tabs, children: tabWidgets)),
              if (showFeature && featureSide == FeatureSide.right) featureSlot,
            ];
          } else if (featureInMiddle) {
            final half = tabs.length ~/ 2;
            children = [
              ...tabWidgets.take(half),
              const SizedBox(width: _tabWidth),
              ...tabWidgets.skip(half)
            ];
          } else {
            children = [
              if (showFeature && featureSide == FeatureSide.left) featureSlot,
              ...tabWidgets,
              if (showFeature && featureSide == FeatureSide.right) featureSlot,
            ];
          }
          return SizedBox(
            height: height + (featureInMiddle ? _protrusion : 0),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Center(
                    child: Container(
                      height: height,
                      constraints:
                          BoxConstraints(maxWidth: constraints.maxWidth),
                      decoration: BoxDecoration(
                        color: context.backgroundColor,
                        borderRadius: BorderRadius.circular(_capsuleRadius),
                        border: Border.all(
                            color: context.borderColor.withValues(alpha: 0.5)),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(
                                  alpha: context.isDarkMode ? 0.5 : 0.18),
                              blurRadius: 20,
                              offset: const Offset(0, 8))
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                          mainAxisSize:
                              fits ? MainAxisSize.min : MainAxisSize.max,
                          children: children),
                    ),
                  ),
                ),
                if (featureInMiddle)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Center(
                        child: _diamond(context, accent, elevated: true)),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _tab(BuildContext context, NavTab tab, double width, double height) {
    final accent = context.accentColor;
    final color = tab.selected ? accent : context.textSecondary;
    return Semantics(
      label: tab.label,
      button: true,
      selected: tab.selected,
      onTap: tab.onTap,
      child: ExcludeSemantics(
          child: SizedBox(
        width: width,
        height: height,
        child: Tooltip(
          message: tab.label,
          excludeFromSemantics: true,
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
                    style: _labelStyle.copyWith(
                      fontWeight:
                          tab.selected ? FontWeight.w600 : FontWeight.normal,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      )),
    );
  }

  Widget _diamond(BuildContext context, Color accent,
      {required bool elevated}) {
    final size = elevated ? _elevatedDiamond : _inlineDiamond;
    return Semantics(
      label: feature.label,
      button: true,
      onTap: feature.onTap,
      child: ExcludeSemantics(
          child: Tooltip(
        message: feature.label,
        excludeFromSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: feature.onTap,
            customBorder: const CurvedDiamondBorder(n: _squircleN),
            child: Container(
              width: size,
              height: size,
              decoration: ShapeDecoration(
                color: accent,
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
      )),
    );
  }
}

class _ScrollableTabs extends StatefulWidget {
  const _ScrollableTabs({required this.tabs, required this.children});
  final List<NavTab> tabs;
  final List<Widget> children;
  @override
  State<_ScrollableTabs> createState() => _ScrollableTabsState();
}

class _ScrollableTabsState extends State<_ScrollableTabs> {
  final _controller = ScrollController();
  final _keys = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _revealSelection();
  }

  @override
  void didUpdateWidget(_ScrollableTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabs.indexWhere((t) => t.selected) !=
        widget.tabs.indexWhere((t) => t.selected)) {
      _revealSelection();
    }
  }

  void _revealSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = widget.tabs.indexWhere((t) => t.selected);
      final context = _keys[index]?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(context,
            alignment: 0.5, duration: Duration.zero);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
        controller: _controller,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (var i = 0; i < widget.children.length; i++)
              Focus(
                onFocusChange: (focused) {
                  final context = _keys[i]?.currentContext;
                  if (focused && context != null) {
                    Scrollable.ensureVisible(context,
                        alignment: 0.5, duration: Duration.zero);
                  }
                },
                child: KeyedSubtree(
                    key: _keys.putIfAbsent(i, GlobalKey.new),
                    child: widget.children[i]),
              ),
          ]),
        ),
      );
}
