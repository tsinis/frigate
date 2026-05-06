// Test inlines short closures inside `expect` / iteration helpers — extracting them named
// would make the cases harder to read at a glance.
// ignore_for_file: prefer-extracting-callbacks, prefer-extracting-function-callbacks
// _RecordingCanvas is a test-only stub that lives at file bottom; main() is the entry point.
// ignore_for_file: prefer-match-file-name
// noSuchMethod requires a dynamic return per the Object contract.
// ignore_for_file: avoid-dynamic

import 'dart:ui' show Canvas, Offset, Paint, RRect, Rect;

import 'package:flutter/rendering.dart' show Size;
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

  group('paint', () {
    test('uses drawRect for rectangles with cornerRadius=0', () {
      final canvas = _RecordingCanvas();
      const sharp = RectElement(height: 50, width: 100, x: 10, y: 20);
      const DrawPainter([sharp]).paint(canvas, const Size(200, 200));
      expect(canvas.drawRectCount, 1, reason: 'sharp rect should hit drawRect once');
      expect(canvas.drawRRectCount, 0, reason: 'no rounded path for cornerRadius=0');
    });

    test('uses drawRRect for rectangles with cornerRadius>0', () {
      final canvas = _RecordingCanvas();
      const rounded = RectElement(cornerRadius: 8, height: 50, width: 100, x: 10, y: 20);
      const DrawPainter([rounded]).paint(canvas, const Size(200, 200));
      expect(canvas.drawRRectCount, 1, reason: 'rounded rect must take the drawRRect path');
      expect(canvas.drawRectCount, 0, reason: 'must not draw both - would over-paint the outline');
    });

    test('paint.isAntiAlias is FALSE for sharp-corner rects (matches Rust contract)', () {
      final canvas = _RecordingCanvas();
      const sharp = RectElement(height: 50, width: 100, x: 10, y: 20);
      const DrawPainter([sharp]).paint(canvas, const Size(200, 200));
      expect(
        canvas.isLastPaintAntiAlias,
        isFalse,
        reason: 'sharp rect must render pixel-aligned, no AA bleed at the edges',
      );
    });

    test('paint.isAntiAlias is TRUE for rounded-corner rects (curves need AA)', () {
      final canvas = _RecordingCanvas();
      const rounded = RectElement(cornerRadius: 8, height: 50, width: 100, x: 10, y: 20);
      const DrawPainter([rounded]).paint(canvas, const Size(200, 200));
      expect(
        canvas.isLastPaintAntiAlias,
        isTrue,
        reason: 'rounded corners need AA so the curve does not look jagged',
      );
    });

    test('non-positive width or height is silently skipped (mirrors Rust export)', () {
      // Rust's `draw_rect_on_pixmap` short-circuits on `width <= 0 || height <= 0`. Without
      // the matching guard in the painter, Flutter would happily render a flipped rect from
      // a negative-width `Rect.fromLTWH` — a preview-vs-export divergence the user would
      // hit mid-drag. The original CodeRabbit hypothesis (that `clamp` would throw) is
      // false because `Rect.shortestSide` is magnitude-based, but the divergence is real.
      final canvas = _RecordingCanvas();
      const cases = <RectElement>[
        RectElement(cornerRadius: 8, height: 10, width: -10, x: 0, y: 0),
        RectElement(cornerRadius: 8, height: -10, width: 10, x: 0, y: 0),
        RectElement(cornerRadius: 8, height: 0, width: 10, x: 0, y: 0),
        RectElement(cornerRadius: 8, height: 10, width: 0, x: 0, y: 0),
        RectElement(height: 0, width: 0, x: 0, y: 0),
      ];
      const DrawPainter(cases).paint(canvas, const Size(100, 100));
      expect(
        (canvas.drawRectCount, canvas.drawRRectCount),
        (0, 0),
        reason: 'every non-positive-dimension rect must be skipped without painting',
      );
    });

    test('drawRRect radius is clamped to half the shortest side (preview matches export)', () {
      final canvas = _RecordingCanvas();
      // Rect is 100x40, so the largest visually-meaningful radius is 20. We pass 9999 to
      // verify the preview clamps just like Rust does.
      const rounded = RectElement(cornerRadius: 9999, height: 40, width: 100, x: 0, y: 0);
      const DrawPainter([rounded]).paint(canvas, const Size(200, 200));
      final radius = canvas.lastRRect?.tlRadiusX;
      expect(radius, isNotNull, reason: 'drawRRect call captured');
      expect(
        radius,
        20.0,
        reason: 'clamped to min(width, height) / 2 = 20 to mirror Rust auto-clamp',
      );
    });

    test('uses drawOval for OvalElement', () {
      final canvas = _RecordingCanvas();
      const oval = OvalElement(
        fillColor: .black, // Explicitly > 0 alpha for fill.
        height: 50,
        outlineColor: .transparent, // Explicitly 0 alpha for outline.
        width: 100,
        x: 10,
        y: 20,
      );
      const DrawPainter([oval]).paint(canvas, const Size(200, 200));
      expect(
        canvas.drawOvalCount,
        1,
        reason: 'oval element should hit drawOval once for the fill (outline is transparent)',
      );
      expect(canvas.lastPaintColorAlpha, 255, reason: 'black fill has alpha 255');
    });
  });

  group('isPointOnShape', () {
    test('is true on the outline of a rect', () {
      expect(
        DrawPainter.isPointOnShape(const Offset(50, 30), element: hitRect),
        isTrue,
        reason: 'top-left corner sits on the outline',
      );
    });

    test('is true on the outline of an oval', () {
      const oval = OvalElement(height: 100, width: 200, x: 50, y: 30);
      // Center of the top edge of the bounding box is a point on the oval.
      expect(
        DrawPainter.isPointOnShape(const Offset(150, 30), element: oval),
        isTrue,
        reason: 'top midpoint sits on the oval outline',
      );

      expect(
        DrawPainter.isPointOnShape(const Offset(50, 30), element: oval),
        isFalse,
        reason: 'bounding-box corner is not on the oval outline',
      );
    });

    test('is false in the interior of a shape', () {
      expect(
        DrawPainter.isPointOnShape(const Offset(150, 80), element: hitRect),
        isFalse,
        reason: 'shape center is hollow',
      );
    });

    test('is false far outside the shape', () {
      expect(
        DrawPainter.isPointOnShape(const Offset(500, 500), element: hitRect),
        isFalse,
        reason: 'well outside the shape and its hit-slop',
      );
    });
  });
});

/// Stub [Canvas] that counts the draw operations DrawPainter cares about. We can't subclass
/// Canvas directly (its constructor needs a PictureRecorder) so we implement the interface and
/// route all the `void` API surface through `noSuchMethod`.
class _RecordingCanvas implements Canvas {
  int drawRectCount = 0;
  int drawRRectCount = 0;
  int drawOvalCount = 0;
  RRect? lastRRect;
  bool? isLastPaintAntiAlias;
  int? lastPaintColorAlpha;

  @override
  // ignore: parameters-ordering, signature must match dart:ui Canvas.
  void drawRect(Rect rect, Paint paint) {
    drawRectCount += 1;
    isLastPaintAntiAlias = paint.isAntiAlias;
    lastPaintColorAlpha = (paint.color.a * 255).round();
  }

  @override
  // ignore: parameters-ordering, signature must match dart:ui Canvas.
  void drawRRect(RRect rrect, Paint paint) {
    drawRRectCount += 1;
    lastRRect = rrect;
    isLastPaintAntiAlias = paint.isAntiAlias;
    lastPaintColorAlpha = (paint.color.a * 255).round();
  }

  @override
  // ignore: parameters-ordering, signature must match dart:ui Canvas.
  void drawOval(Rect rect, Paint paint) {
    drawOvalCount += 1;
    isLastPaintAntiAlias = paint.isAntiAlias;
    lastPaintColorAlpha = (paint.color.a * 255).round();
  }

  /// Catch-all: every other Canvas method the painter happens to call (drawCircle for handles,
  /// saveLayer, etc.) is a silent no-op for our recording purposes.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
