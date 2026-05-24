import 'dart:typed_data' show Float64x2, Float64x2List;
import 'dart:ui' show Color, Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:frigatebird/frigatebird.dart';
import 'package:frigatedraw/src/helpers/draw_element_extension.dart';
import 'package:frigatedraw/src/ui/draw_tool.dart';

void main() => group('DrawElementExtension', () {
  const rect = RectElement(
    fillColor: FfiColor(0xFFFF0000),
    height: 100,
    outlineColor: FfiColor(0xFF00FF00),
    outlineThickness: 4,
    width: 200,
    x: 50,
    y: 30,
  );

  const oval = OvalElement(
    fillColor: FfiColor(0xFF0000FF),
    height: 100,
    outlineColor: FfiColor(0xFFFFFFFF),
    outlineThickness: 4,
    width: 200,
    x: 50,
    y: 30,
  );

  final poly = PolygonElement(
    fillColor: const FfiColor(0xFFFFFFFF),
    height: 100,
    outlineThickness: 4,
    vertices: Float64x2List.fromList([Float64x2(50, 30), Float64x2(250, 30), Float64x2(150, 130)]),
    width: 200,
    x: 50,
    y: 30,
  );

  const text = TextElement(
    fillColor: .transparent,
    height: 40,
    outlineColor: FfiColor(0xFFFFFFFF),
    text: 'Hello',
    x: 10,
    y: 20,
  );

  group('rect / uiFillColor / uiOutlineColor getters', () {
    test('rect returns exact boundaries', () {
      expect(rect.rect, const Rect.fromLTWH(50, 30, 200, 100));
    });

    test('uiFillColor and uiOutlineColor map ARGB values correctly', () {
      expect(rect.uiFillColor, const Color(0xFFFF0000));
      expect(rect.uiOutlineColor, const Color(0xFF00FF00));
    });
  });

  group('copyWithDrag', () {
    test('resizes element to bounding box of two points', () {
      final dragged = rect.copyWithDrag(a: const Offset(10, 20), b: const Offset(110, 120));
      expect(dragged.x, 10.0);
      expect(dragged.y, 20.0);
      expect(dragged.width, 100.0);
      expect(dragged.height, 100.0);
    });
  });

  group('tool mapping', () {
    test('maps sealed class subtypes to respective DrawTool enums', () {
      expect(rect.tool, DrawTool.rectangle);
      expect(oval.tool, DrawTool.oval);
      expect(poly.tool, DrawTool.polygon);
      expect(text.tool, DrawTool.text);
    });
  });

  group('handleCenter', () {
    test('calculates correct Offset for all 8 HandlePositions', () {
      expect(rect.handleCenter(.topLeft), const Offset(50, 30));
      expect(rect.handleCenter(.topCenter), const Offset(150, 30));
      expect(rect.handleCenter(.topRight), const Offset(250, 30));
      expect(rect.handleCenter(.centerLeft), const Offset(50, 80));
      expect(rect.handleCenter(.centerRight), const Offset(250, 80));
      expect(rect.handleCenter(.bottomLeft), const Offset(50, 130));
      expect(rect.handleCenter(.bottomCenter), const Offset(150, 130));
      expect(rect.handleCenter(.bottomRight), const Offset(250, 130));
    });
  });

  group('hitTestHandle', () {
    test('returns matched handle within radius', () {
      expect(rect.hitTestHandle(const Offset(52, 32)), HandlePosition.topLeft);
      expect(rect.hitTestHandle(const Offset(150, 28)), HandlePosition.topCenter);
    });

    test('returns null when point is outside handle radius', () {
      expect(rect.hitTestHandle(const Offset(60, 40)), isNull);
    });

    test('returns null for TextElement', () {
      expect(text.hitTestHandle(const Offset(10, 20)), isNull);
    });

    test('returns null for zero-dimension elements', () {
      final zeroRect = rect.copyWith(height: 100, width: 0);
      expect(zeroRect.hitTestHandle(const Offset(50, 30)), isNull);
    });
  });

  group('isPointOnShape', () {
    test('returns false for zero-dimension elements', () {
      final zeroRect = rect.copyWith(height: 0, width: 100);
      expect(zeroRect.isPointOnShape(const Offset(50, 30)), isFalse);
    });

    test('returns false for points far outside outer bounds', () {
      expect(rect.isPointOnShape(const Offset(1000, 1000)), isFalse);
    });

    test('RectElement returns true inside outer bounds', () {
      expect(rect.isPointOnShape(const Offset(150, 80)), isTrue);
    });

    test('OvalElement matches elliptical bounds correctly', () {
      // Center of the oval is inside.
      expect(oval.isPointOnShape(const Offset(150, 80)), isTrue);

      // Corners of bounding box are outside the ellipse.
      expect(oval.isPointOnShape(const Offset(50, 30)), isFalse);
    });

    test('PolygonElement matches polygon bounds correctly', () {
      // Inside the triangular bounds.
      expect(poly.isPointOnShape(const Offset(150, 80)), isTrue);

      // Outside the triangular bounds.
      expect(poly.isPointOnShape(const Offset(50, 130)), isFalse);
    });
  });

  group('getPathForPolygon caching and metrics', () {
    test('multiple path calls return cached identical Path instances', () {
      final path1 = DrawElementExtension.getPathForPolygon(poly);
      final path2 = DrawElementExtension.getPathForPolygon(poly);
      expect(identical(path1, path2), isTrue);
    });
  });
});
