import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/widgets/hold_preview_card.dart';

void main() {
  const screen = Size(400, 800);
  const card = Size(260, 260);

  test('centers on finger when there is room above', () {
    final rect = holdPreviewRect(const Offset(200, 600), screen, card);
    expect(rect.left, 70);
    expect(rect.bottom, closeTo(600 - 56, 0.01));
  });

  test('flips below finger when too close to top', () {
    final rect = holdPreviewRect(const Offset(200, 30), screen, card);
    expect(rect.top, closeTo(30 + 56, 0.01));
  });

  test('clamps to screen edges', () {
    final leftEdge = holdPreviewRect(const Offset(5, 600), screen, card);
    expect(leftEdge.left, 12);

    final rightEdge = holdPreviewRect(
        const Offset(395, 600), screen, card);
    expect(rightEdge.right, 388);

    // Finger at very bottom: card sits above the finger, still fully visible.
    final bottom = holdPreviewRect(const Offset(200, 799), screen, card);
    expect(bottom.bottom, closeTo(799 - 56, 0.01));
    expect(bottom.bottom <= 788, isTrue);
  });

  test('tiny screen never produces negative offsets', () {
    final rect = holdPreviewRect(
        const Offset(10, 10), const Size(100, 100), card);
    expect(rect.left, greaterThanOrEqualTo(12));
    expect(rect.top, greaterThanOrEqualTo(12));
  });
}
