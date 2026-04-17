// ignore_for_file: prefer-extracting-callbacks
// ignore_for_file: prefer-extracting-function-callbacks

import 'package:flutter_test/flutter_test.dart';
import 'package:frigatedraw/frigatedraw.dart';

void main() => group(DrawPainter, () {
  const rect = RectElement(height: 50, width: 100, x: 10, y: 20);

  test('shouldRepaint is false when elements + selected index are unchanged', () {
    final elements = <DrawElement>[rect];
    final oldPainter = DrawPainter(elements, selectedIndex: 0);
    final newPainter = DrawPainter(elements, selectedIndex: 0);
    expect(
      newPainter.shouldRepaint(oldPainter),
      isFalse,
      reason: 'identical list + same selection means nothing to redraw',
    );
  });

  test('shouldRepaint is true when selectedIndex changes', () {
    final elements = <DrawElement>[rect];
    final oldPainter = DrawPainter(elements);
    final newPainter = DrawPainter(elements, selectedIndex: 0);
    expect(newPainter.shouldRepaint(oldPainter), isTrue, reason: 'handles appear/disappear');
  });

  test('shouldRepaint is true when elements list identity changes', () {
    final oldPainter = DrawPainter(List<DrawElement>.of([rect]));
    final newPainter = DrawPainter(List<DrawElement>.of([rect]));
    expect(
      newPainter.shouldRepaint(oldPainter),
      isTrue,
      reason: 'different list instance implies a possible content change',
    );
  });

  // Rect lives at (50, 30) .. (250, 130). Corners + edge midpoints must map to the matching
  // HandlePosition; the rect's interior must not match any handle.
  const hitRect = RectElement(height: 100, width: 200, x: 50, y: 30);

  group('hitTestHandle', () {
    test('maps each corner and edge midpoint to the expected handle', () {
      const cases = <({HandlePosition handle, Offset point})>[
        (handle: HandlePosition.topLeft, point: Offset(50, 30)),
        (handle: HandlePosition.topCenter, point: Offset(150, 30)),
        (handle: HandlePosition.topRight, point: Offset(250, 30)),
        (handle: HandlePosition.centerLeft, point: Offset(50, 80)),
        (handle: HandlePosition.centerRight, point: Offset(250, 80)),
        (handle: HandlePosition.bottomLeft, point: Offset(50, 130)),
        (handle: HandlePosition.bottomCenter, point: Offset(150, 130)),
        (handle: HandlePosition.bottomRight, point: Offset(250, 130)),
      ];
      for (final (:handle, :point) in cases) {
        expect(
          DrawPainter.hitTestHandle(point, element: hitRect),
          handle,
          reason: 'point $point should map to $handle',
        );
      }
    });

    test('returns null for the rect center (no handle in the middle)', () {
      expect(
        DrawPainter.hitTestHandle(const Offset(150, 80), element: hitRect),
        isNull,
        reason: 'center of the rect is handle-free',
      );
    });
  });

  group('isPointOnRect', () {
    test('is true on the outline', () {
      expect(
        DrawPainter.isPointOnRect(const Offset(50, 30), element: hitRect),
        isTrue,
        reason: 'top-left corner sits on the outline',
      );
    });

    test('is false in the interior', () {
      expect(
        DrawPainter.isPointOnRect(const Offset(150, 80), element: hitRect),
        isFalse,
        reason: 'rect center is hollow',
      );
    });

    test('is false far outside the rect', () {
      expect(
        DrawPainter.isPointOnRect(const Offset(500, 500), element: hitRect),
        isFalse,
        reason: 'well outside the rect and its hit-slop',
      );
    });
  });
});
