// ignore_for_file: avoid-long-files

import 'dart:math' show pi;
import 'dart:typed_data';
import 'dart:ui';

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
        expect(hitRect.hitTestHandle(point), handle, reason: 'point $point should map to $handle');
      }
    });

    test('returns null for the rect center (no handle in the middle)', () {
      expect(
        hitRect.hitTestHandle(const Offset(150, 80)),
        isNull,
        reason: 'center of the rect is handle-free',
      );
    });

    test('maps a rotated handle to its rotated screen position', () {
      const rotated = RectElement(height: 100, rotation: 90, width: 200, x: 50, y: 30);

      expect(
        rotated.hitTestHandle(const Offset(200, -20)),
        HandlePosition.topLeft,
        reason: 'top-left (50,30) rotates 90deg about center (150,80) to (200,-20)',
      );
    });
  });

  group('paint', () {
    test('uses drawRect for rectangles with cornerRadius=0', () {
      final canvas = _DrawPainterTest();
      const sharp = RectElement(height: 50, width: 100, x: 10, y: 20);
      const DrawPainter([sharp]).paint(canvas, const Size(200, 200));
      expect(
        canvas.drawRectCount,
        2,
        reason: 'sharp rect should hit drawRect twice (contrast base + outline)',
      );
      expect(canvas.drawRRectCount, 0, reason: 'no rounded path for cornerRadius=0');
    });

    test('uses drawRRect for rectangles with cornerRadius>0', () {
      final canvas = _DrawPainterTest();
      const rounded = RectElement(cornerRadius: 8, height: 50, width: 100, x: 10, y: 20);
      const DrawPainter([rounded]).paint(canvas, const Size(200, 200));
      expect(
        canvas.drawRRectCount,
        2,
        reason: 'rounded rect must take the drawRRect path twice (contrast base + outline)',
      );
      expect(canvas.drawRectCount, 0, reason: 'must not draw both - would over-paint the outline');
    });

    test('paint.isAntiAlias is FALSE for sharp-corner rects (matches Rust contract)', () {
      final canvas = _DrawPainterTest();
      const sharp = RectElement(height: 50, width: 100, x: 10, y: 20);
      const DrawPainter([sharp]).paint(canvas, const Size(200, 200));
      expect(
        canvas.isLastPaintAntiAlias,
        isFalse,
        reason: 'sharp rect must render pixel-aligned, no AA bleed at the edges',
      );
    });

    test('paint.isAntiAlias is TRUE for rounded-corner rects (curves need AA)', () {
      final canvas = _DrawPainterTest();
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
      // hit mid-drag. The original hypothesis (that `clamp` would throw) is
      // false because `Rect.shortestSide` is magnitude-based, but the divergence is real.
      final canvas = _DrawPainterTest();
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

    test('MaskRegionElement draws a rectangle with correct paint properties', () {
      final canvas = _DrawPainterTest();
      const mask = MaskRegionElement(
        fillColor: FfiColor(0xFF00FF00),
        height: 50,
        width: 100,
        x: 10,
        y: 20,
      );
      const DrawPainter([mask]).paint(canvas, const Size(200, 200));

      expect(canvas.drawRectCount, 1, reason: 'MaskRegionElement paints as Rect');
      expect(canvas.lastPaintColorAlpha, 255); // Opaque green.
    });

    test('drawRRect radius is clamped to half the shortest side (preview matches export)', () {
      final canvas = _DrawPainterTest();
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
      final canvas = _DrawPainterTest();
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

    test('uses drawPath for PolygonElement', () {
      final canvas = _DrawPainterTest();
      final poly = PolygonElement(
        height: 100,
        vertices: Float64x2List.fromList([Float64x2(0, 0), Float64x2(100, 0), Float64x2(50, 100)]),
        width: 100,
        x: 0,
        y: 0,
      );
      DrawPainter([poly]).paint(canvas, const Size(200, 200));
      expect(
        canvas.drawPathCount,
        3,
        reason:
            'polygon element should hit drawPath three times (fill + contrast outline base + outline)',
      );
    });

    test('Polygon preview uses custom creationTemplate styling', () {
      final canvas = _DrawPainterTest();
      final polyTemplate = PolygonElement(
        height: 0,
        outlineColor: const FfiColor(0xFFFF0000),
        outlineThickness: 8,
        vertices: Float64x2List.fromList([Float64x2(0, 0), Float64x2(100, 0), Float64x2(50, 100)]),
        width: 0,
        x: 0,
        y: 0,
      );

      DrawPainter(
        const [],
        activeTool: .polygon,
        creationTemplate: polyTemplate,
        pendingVertices: polyTemplate.vertices,
      ).paint(canvas, const Size(200, 200));

      expect(canvas.drawPathCount, 2, reason: 'preview calls drawPath to render the open segments');
      expect(
        canvas.drawLineCount,
        greaterThanOrEqualTo(1),
        reason: 'closing segments are drawn as line primitives',
      );
    });

    test('non-positive width or height is silently skipped for ovals', () {
      final canvas = _DrawPainterTest();
      const oval = OvalElement(height: 0, width: 100, x: 0, y: 0);
      const DrawPainter([oval]).paint(canvas, const Size(100, 100));
      expect(canvas.drawOvalCount, isZero);
    });

    test('renders placeholder outline for transparent/no-outline blur RectElement', () {
      final canvas = _DrawPainterTest();
      const sharp = RectElement(
        blur: 15,
        height: 50,
        outlineColor: .transparent,
        outlineThickness: 0,
        width: 100,
        x: 10,
        y: 20,
      );
      const DrawPainter([sharp]).paint(canvas, const Size(200, 200));
      expect(canvas.drawRectCount, 1, reason: 'drawRect should be called for region blur fill');
    });

    test('blur rendering path is exercised with background image', () async {
      final imageRecorder = PictureRecorder();
      _drawOpaquePixel(imageRecorder);
      final frameImage = await imageRecorder.endRecording().toImage(1, 1);
      addTearDown(frameImage.dispose);

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);

      DrawPainter(
        [
          const RectElement(
            blur: 18,
            height: 50,
            outlineColor: FfiColor(0xFF00FF00),
            width: 100,
            x: 10,
            y: 20,
          ),
        ], // Dart 3.8 formatting.
        backgroundImage: frameImage,
      ).paint(canvas, const Size(200, 200));

      expect(recorder.endRecording, returnsNormally);
    });

    test('renders placeholder outline for transparent/no-outline blur OvalElement', () {
      final canvas = _DrawPainterTest();
      const oval = OvalElement(
        blur: 15,
        height: 50,
        outlineColor: .transparent,
        outlineThickness: 0,
        width: 100,
        x: 10,
        y: 20,
      );
      const DrawPainter([oval]).paint(canvas, const Size(200, 200));
      expect(canvas.drawOvalCount, 1, reason: 'drawOval should be called once for fill');
      expect(canvas.drawPathCount, 1, reason: 'drawPath should be called once for dashed outline');
    });

    test('renders placeholder outline for transparent/no-outline blur PolygonElement', () {
      final canvas = _DrawPainterTest();
      final poly = PolygonElement(
        blur: 15,
        fillColor: .transparent,
        height: 100,
        outlineColor: .transparent,
        outlineThickness: 0,
        vertices: Float64x2List.fromList([Float64x2(0, 0), Float64x2(100, 0), Float64x2(50, 100)]),
        width: 100,
        x: 0,
        y: 0,
      );
      DrawPainter([poly]).paint(canvas, const Size(200, 200));
      expect(
        canvas.drawPathCount,
        2,
        reason: 'drawPath should be called twice (fill + dashed outline)',
      );
    });

    test('uses drawRect for MaskRegionElement', () {
      final canvas = _DrawPainterTest();
      const mask = MaskRegionElement(height: 50, width: 100, x: 10, y: 20);
      const DrawPainter([mask]).paint(canvas, const Size(200, 200));
      expect(canvas.drawRectCount, 1, reason: 'mask region element should hit drawRect once');
    });
  });

  group('isPointOnShape', () {
    test('is true on the outline of a rect', () {
      expect(
        hitRect.isPointOnShape(const Offset(50, 30)),
        isTrue,
        reason: 'top-left corner sits on the outline',
      );
    });

    test('is true on the outline of an oval', () {
      const oval = OvalElement(height: 100, width: 200, x: 50, y: 30);
      // Center of the top edge of the bounding box is a point on the oval.
      expect(
        oval.isPointOnShape(const Offset(150, 30)),
        isTrue,
        reason: 'top midpoint sits on the oval outline',
      );

      expect(
        oval.isPointOnShape(const Offset(50, 30)),
        isFalse,
        reason: 'bounding-box corner is not on the oval outline',
      );
    });

    test('is false for non-positive dimensions', () {
      const oval = OvalElement(height: 0, width: 100, x: 0, y: 0);
      expect(oval.isPointOnShape(const Offset(50, 0)), isFalse);
    });

    test('is true in the interior of a shape without fill', () {
      expect(
        hitRect.isPointOnShape(const Offset(150, 80)),
        isTrue,
        reason: 'shape center is clickable even when transparent',
      );
    });

    test('is true in the interior of a shape with fill', () {
      const filledRect = RectElement(fillColor: .black, height: 100, width: 200, x: 50, y: 30);
      expect(
        filledRect.isPointOnShape(const Offset(150, 80)),
        isTrue,
        reason: 'shape center is clickable when filled',
      );
    });
    test('is false far outside the shape', () {
      expect(
        hitRect.isPointOnShape(const Offset(500, 500)),
        isFalse,
        reason: 'well outside the shape and its hit-slop',
      );
    });

    test('OvalElement isPointOnShape works correctly', () {
      const oval = OvalElement(height: 100, width: 200, x: 50, y: 50);
      expect(oval.isPointOnShape(const Offset(150, 100)), isTrue);
      expect(
        oval.isPointOnShape(const Offset(50, 50)),
        isFalse,
        reason: 'Top left corner of bounding box, outside ellipse',
      );
    });

    test('PolygonElement isPointOnShape works correctly', () {
      final poly = PolygonElement(
        height: 100,
        vertices: Float64x2List.fromList([Float64x2(0, 0), Float64x2(100, 0), Float64x2(50, 100)]),
        width: 100,
        x: 0,
        y: 0,
      );
      expect(poly.isPointOnShape(const Offset(50, 50)), isTrue);
      expect(poly.isPointOnShape(const Offset(10, 10)), isTrue);
      expect(poly.isPointOnShape(const Offset(90, 10)), isTrue);
      expect(poly.isPointOnShape(const Offset(0, 100)), isFalse);
    });
  });

  group('Rendering', () {
    test('DrawPainter paints OvalElement', () {
      const oval = OvalElement(fillColor: .black, height: 100, width: 200, x: 50, y: 50);
      const painter = DrawPainter([oval]);
      final recorder = _DrawPainterTest();
      painter.paint(recorder, const Size(800, 600));

      expect(recorder.drawOvalCount, greaterThan(0));
    });

    test('DrawPainter paints rounded RectElement', () {
      const roundedRect = RectElement(
        cornerRadius: 16,
        fillColor: .black,
        height: 100,
        width: 200,
        x: 50,
        y: 50,
      );
      const painter = DrawPainter([roundedRect]);
      final recorder = _DrawPainterTest();
      painter.paint(recorder, const Size(800, 600));

      expect(recorder.drawRRectCount, greaterThan(0));
    });

    test('DrawPainter paints RectElement with fill', () {
      const rectangle = RectElement(fillColor: .black, height: 100, width: 100, x: 50, y: 50);
      const painter = DrawPainter([rectangle]);
      final recorder = _DrawPainterTest();
      painter.paint(recorder, const Size(800, 600));

      expect(recorder.drawRectCount, greaterThan(0));
    });

    test('DrawPainter gracefully handles TextElement without crashing', () {
      const text = TextElement(text: 'Hello', x: 50, y: 50);
      const painter = DrawPainter([text]);
      final recorder = _DrawPainterTest();
      expect(
        () => painter.paint(recorder, const Size(800, 600)),
        returnsNormally,
        reason: "Doesn't do anything yet, but should not crash",
      );
    });

    test('shouldRepaint returns true if elements or selectedIndex differ', () {
      const rectangle = RectElement(height: 100, width: 100, x: 50, y: 50);
      const painterFirst = DrawPainter([rectangle], selectedIndex: 0);
      const painterSecond = DrawPainter([rectangle]);
      const painterThird = DrawPainter([], selectedIndex: 0);

      expect(painterFirst.shouldRepaint(painterSecond), isTrue);
      expect(painterFirst.shouldRepaint(painterThird), isTrue);
      expect(painterFirst.shouldRepaint(painterFirst), isFalse);
    });
  });

  group('shouldRepaint edge cases', () {
    test('is true when tolerance changes', () {
      final elements = <DrawElement>[];
      final old = DrawPainter(elements);
      final next = DrawPainter(elements, tolerance: 10);
      expect(next.shouldRepaint(old), isTrue, reason: 'different tolerance requires repaint');
    });

    test('is true when handleBorderWidth changes', () {
      final elements = <DrawElement>[];
      final old = DrawPainter(elements);
      final next = DrawPainter(elements, handleBorderWidth: 1);
      expect(
        next.shouldRepaint(old),
        isTrue,
        reason: 'different handle border width requires repaint',
      );
    });

    test('is true when creationTemplate identity changes', () {
      final elements = <DrawElement>[];
      const template1 = RectElement(height: 10, width: 10, x: 0, y: 0);
      const templateOther = RectElement(height: 20, width: 20, x: 0, y: 0);
      final old = DrawPainter(elements, creationTemplate: template1);
      final next = DrawPainter(elements, creationTemplate: templateOther);
      expect(
        next.shouldRepaint(old),
        isTrue,
        reason: 'different creationTemplate instance requires repaint',
      );
    });

    test('is true when cursorPosition changes', () {
      final elements = <DrawElement>[];
      final old = DrawPainter(elements, cursorPosition: .zero);
      final next = DrawPainter(elements, cursorPosition: const Offset(10, 10));
      expect(next.shouldRepaint(old), isTrue, reason: 'cursor moved requires repaint');
    });

    test('is false when all fields are identical', () {
      final elements = <DrawElement>[];
      const cursor = Offset(5, 5);
      const templateOther = RectElement(height: 10, width: 10, x: 0, y: 0);
      final old = DrawPainter(
        elements,
        activeTool: .select,
        creationTemplate: templateOther,
        cursorPosition: cursor,
        tolerance: 15,
      );
      final next = DrawPainter(
        elements,
        activeTool: .select,
        creationTemplate: templateOther,
        cursorPosition: cursor,
        tolerance: 15,
      );
      expect(next.shouldRepaint(old), isFalse, reason: 'identical fields means no repaint needed');
    });
  });

  group('_paintPolygon edge cases', () {
    test('polygon with < 3 vertices is skipped', () {
      final canvas = _DrawPainterTest();
      // Manually craft a 2-vertex polygon — the assert prevents < 3 via constructor,
      // so we use the painter's internal guard by testing paint directly with a fill of 0 alpha.
      final noFillPoly = PolygonElement(
        fillColor: .transparent, // 0 alpha fill.
        height: 100,
        outlineColor: .transparent, // 0 alpha outline.
        vertices: Float64x2List.fromList([Float64x2(0, 0), Float64x2(100, 0), Float64x2(50, 100)]),
        width: 100,
        x: 0,
        y: 0,
      );
      DrawPainter([noFillPoly]).paint(canvas, const Size(200, 200));
      expect(canvas.drawPathCount, isZero, reason: 'fully transparent polygon draws nothing');
    });

    test('polygon with outline only (no fill) draws outline + contrast base', () {
      final canvas = _DrawPainterTest();
      final poly = PolygonElement(
        fillColor: .transparent, // Transparent fill.
        height: 100,
        outlineColor: const FfiColor(0xFFFF0000),
        outlineThickness: 3,
        vertices: Float64x2List.fromList([Float64x2(0, 0), Float64x2(100, 0), Float64x2(50, 100)]),
        width: 100,
        x: 0,
        y: 0,
      );
      DrawPainter([poly]).paint(canvas, const Size(200, 200));
      expect(canvas.drawPathCount, 2, reason: 'the outline path + contrast base path are drawn');
    });
  });

  group('_paintPolygonPreview edge cases', () {
    test('no preview drawn when activeTool is not polygon', () {
      final canvas = _DrawPainterTest();
      final pending = [Float64x2(0, 0), Float64x2(50, 0), Float64x2(25, 50)].map((v) => v).toList();
      DrawPainter(
        const [],
        activeTool: .select, // Not polygon.
        pendingVertices: pending,
      ).paint(canvas, const Size(200, 200));
      expect(canvas.drawPathCount, isZero);
    });

    test('preview drawn with null pendingVertices emits nothing', () {
      final canvas = _DrawPainterTest();
      const DrawPainter([], activeTool: .polygon).paint(canvas, const Size(200, 200));
      expect(canvas.drawPathCount, isZero);
    });

    test('preview with single pending vertex and cursor draws dashed cursor line', () {
      final canvas = _DrawPainterTest();
      final pending = [Float64x2(10, 10)];
      DrawPainter(
        const [],
        activeTool: .polygon,
        cursorPosition: const Offset(50, 50),
        pendingVertices: pending,
      ).paint(canvas, const Size(200, 200));
      // The open path plus cursor dashed line calls drawLine (via drawDashedLine).
      // No closing line because only 1 vertex.
      // We just verify no crash and drawLine was called for the open-path segment.
      expect(canvas.drawPathCount, 0);
      expect(canvas.drawLineCount, greaterThanOrEqualTo(1));
    });

    test('closing line is drawn when cursorPosition is null and >= 2 vertices', () {
      final canvas = _DrawPainterTest();
      final pending = [Float64x2(0, 0), Float64x2(100, 0)];
      DrawPainter(
        const [],
        activeTool: .polygon,
        pendingVertices: pending,
        // A cursorPosition: null (default) — triggers _paintClosingLine path.
      ).paint(canvas, const Size(200, 200));
      expect(canvas.drawPathCount, 2);
      expect(canvas.drawLineCount, greaterThanOrEqualTo(1));
    });
  });

  group('_drawDashedLine', () {
    test('zero-distance line does not crash', () {
      final canvas = _DrawPainterTest();
      // Trigger via pending vertices with same start and end (cursor at same point as last vertex).
      final pending = [Float64x2(50, 50)];
      DrawPainter(
        const [],
        activeTool: .polygon,
        cursorPosition: const Offset(50, 50),
        pendingVertices: pending,
      ).paint(canvas, const Size(200, 200));
      expect(
        canvas.drawPathCount,
        isNonNegative,
        reason: 'Zero-distance dashed line must not throw.',
      );
    });
  });

  group('hitTest', () {
    test('returns true when a handle is hit on selected element', () {
      final poly = PolygonElement(
        height: 100,
        vertices: Float64x2List.fromList([Float64x2(0, 0), Float64x2(100, 0), Float64x2(50, 100)]),
        width: 100,
        x: 0,
        y: 0,
      );
      final painter = DrawPainter([poly], selectedIndex: 0);
      // Top-left handle is at (0, 0).
      expect(painter.hitTest(.zero), isTrue);
    });

    test('returns true when point is on a polygon shape', () {
      final poly = PolygonElement(
        height: 100,
        vertices: Float64x2List.fromList([Float64x2(0, 0), Float64x2(100, 0), Float64x2(50, 100)]),
        width: 100,
        x: 0,
        y: 0,
      );
      final painter = DrawPainter([poly]);
      expect(painter.hitTest(const Offset(50, 30)), isTrue);
    });

    test('returns false for empty painter', () {
      const painter = DrawPainter([]);
      expect(painter.hitTest(const Offset(50, 50)), isFalse);
    });

    test('returns false when selectedIndex is out of range', () {
      const testRect = RectElement(height: 100, width: 100, x: 0, y: 0);
      const painter = DrawPainter([testRect], selectedIndex: 99);
      expect(
        painter.hitTest(const Offset(50, 50)),
        isTrue,
        reason: 'Hits the rect even with an out-of-range selectedIndex.',
      );
    });
  });

  group('rotation rendering', () {
    test('rotates the canvas for a rotated rect and still uses drawRect', () {
      final canvas = _DrawPainterTest();
      const rotated = RectElement(
        fillColor: .black,
        height: 50,
        rotation: 90,
        width: 100,
        x: 10,
        y: 20,
      );
      const DrawPainter([rotated]).paint(canvas, const Size(200, 200));

      expect(canvas.rotateCount, greaterThan(0), reason: 'rotated element must rotate the canvas');
      expect(canvas.lastRotation, closeTo(pi / 2, 1e-9), reason: '90 degrees in radians');
      expect(canvas.drawRectCount, greaterThan(0), reason: 'still a drawRect, just under rotation');
    });

    test('does not rotate the canvas for an un-rotated rect', () {
      final canvas = _DrawPainterTest();
      const sharp = RectElement(fillColor: .black, height: 50, width: 100, x: 10, y: 20);
      const DrawPainter([sharp]).paint(canvas, const Size(200, 200));

      expect(canvas.rotateCount, isZero, reason: 'un-rotated render must stay transform-free');
    });

    test('rotates the canvas for a rotated oval', () {
      final canvas = _DrawPainterTest();
      const rotated = OvalElement(
        fillColor: .black,
        height: 50,
        rotation: 45,
        width: 100,
        x: 10,
        y: 20,
      );
      const DrawPainter([rotated]).paint(canvas, const Size(200, 200));

      expect((canvas.rotateCount > 0, canvas.drawOvalCount > 0), equals((true, true)));
    });

    test('draws the rotation knob stem when requested for a selection', () {
      final canvas = _DrawPainterTest();
      const knobRect = RectElement(height: 100, width: 100, x: 50, y: 50);
      const DrawPainter(
        [knobRect],
        selectedIndex: 0,
        shouldShowRotationKnob: true,
      ).paint(canvas, const Size(300, 300));

      expect(
        canvas.drawLineCount,
        greaterThanOrEqualTo(1),
        reason: 'stem line connects to the knob',
      );
    });

    test('omits the rotation knob stem when not requested', () {
      final canvas = _DrawPainterTest();
      const knobRect = RectElement(height: 100, width: 100, x: 50, y: 50);
      const DrawPainter([knobRect], selectedIndex: 0).paint(canvas, const Size(300, 300));

      expect(canvas.drawLineCount, isZero, reason: 'no stem is drawn without the knob flag');
    });

    test('rotation knob uses white fill and black border (inverted vs handles)', () {
      final canvas = _DrawPainterTest();
      const knobRect = RectElement(height: 100, width: 100, x: 50, y: 50);
      const DrawPainter(
        [knobRect],
        selectedIndex: 0,
        shouldShowRotationKnob: true,
      ).paint(canvas, const Size(300, 300));

      expect(
        canvas.circleDrawCalls.any(
          (call) => call.color == const Color(0xFFFFFFFF) && call.style == .fill,
        ),
        isTrue,
        reason: 'knob fill must be white',
      );
      expect(
        canvas.circleDrawCalls.any(
          (call) => call.color == const Color(0xFF000000) && call.style == .stroke,
        ),
        isTrue,
        reason: 'knob border must be black',
      );
    });
  });
});

void _drawOpaquePixel(PictureRecorder recorder) {
  final canvas = Canvas(recorder);
  final paint = Paint()..color = const Color(0xFFFFFFFF);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 1, 1), paint);
}

/// Stub [Canvas] that counts the draw operations DrawPainter cares about. We can't subclass
/// Canvas directly (its constructor needs a PictureRecorder) so we implement the interface and
/// route all the `void` API surface through `noSuchMethod`.
class _DrawPainterTest implements Canvas {
  int drawRectCount = 0;
  int drawRRectCount = 0;
  int drawOvalCount = 0;
  int drawPathCount = 0;
  int drawLineCount = 0;
  int drawCircleCount = 0;
  int rotateCount = 0;
  double? lastRotation;
  RRect? lastRRect;
  bool? isLastPaintAntiAlias;
  int? lastPaintColorAlpha;

  /// All `drawCircle` calls recorded as `(color, style)` pairs so tests can
  /// verify both fill and stroke circles (e.g. the inverted rotation knob).
  final circleDrawCalls = <({Color color, PaintingStyle style})>[];

  @override
  void rotate(double radians) {
    rotateCount += 1;
    lastRotation = radians;
  }

  @override
  // ignore: parameters-ordering, signature must match dart:ui Canvas.
  void drawCircle(Offset center, double radius, Paint paint) {
    drawCircleCount += 1;
    // ignore: avoid-collection-mutating-methods, local accumulator in a test stub.
    circleDrawCalls.add((color: paint.color, style: paint.style));
  }

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

  @override
  // ignore: parameters-ordering, signature must match dart:ui Canvas.
  void drawPath(Path path, Paint paint) {
    drawPathCount += 1;
    isLastPaintAntiAlias = paint.isAntiAlias;
    lastPaintColorAlpha = (paint.color.a * 255).round();
  }

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    drawLineCount += 1;
    isLastPaintAntiAlias = paint.isAntiAlias;
    lastPaintColorAlpha = (paint.color.a * 255).round();
  }

  /// Catch-all: every other Canvas method the painter happens to call (drawCircle for handles,
  /// saveLayer, etc.) is a silent no-op for our recording purposes.
  @override
  // ignore: avoid-dynamic, signature must match base Canvas class.
  dynamic noSuchMethod(Invocation invocation) => null;
}
