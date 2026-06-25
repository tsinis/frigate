// ignore_for_file: avoid-similar-names, prefer-correct-identifier-length, prefer-moving-to-variable, description: Style exceptions for assertions in unit tests.
import 'dart:typed_data';

import 'package:frigatebird/frigatebird.dart';
import 'package:test/test.dart';

void main() {
  group('DrawElementResizeExtension.moved', () {
    test('moves a RectElement correctly', () {
      const rect = RectElement(height: 50, width: 50, x: 10, y: 20);
      final movedRect = rect.moved(15, 25);

      expect(movedRect.x, equals(25));
      expect(movedRect.y, equals(45));
      expect(movedRect.width, equals(50));
      expect(movedRect.height, equals(50));
    });

    test('moves an OvalElement correctly', () {
      const oval = OvalElement(height: 30, width: 30, x: -10, y: -20);
      final movedOval = oval.moved(5, 10);

      expect(movedOval.x, equals(-5));
      expect(movedOval.y, equals(-10));
      expect(movedOval.width, equals(30));
      expect(movedOval.height, equals(30));
    });

    test('moves a MaskRegionElement correctly', () {
      const mask = MaskRegionElement(height: 50, width: 50, x: 10, y: 20);
      final movedMask = mask.moved(15, 25);

      expect(movedMask.x, equals(25));
      expect(movedMask.y, equals(45));
      expect(movedMask.width, equals(50));
      expect(movedMask.height, equals(50));
    });

    test('moves a PolygonElement correctly', () {
      final vertices = Float64x2List.fromList([
        Float64x2(10, 10),
        Float64x2(20, 10),
        Float64x2(15, 20),
      ]);
      final poly = PolygonElement(height: 10, vertices: vertices, width: 10, x: 10, y: 10);
      final movedPoly = poly.moved(5, 5);

      switch (movedPoly) {
        case PolygonElement(
          height: final h,
          vertices: final polyVertices,
          width: final w,
          x: final px,
          y: final py,
        ):
          expect(px, equals(15));
          expect(py, equals(15));
          expect(w, equals(10));
          expect(h, equals(10));

          final firstVertex = polyVertices.firstOrNull;
          final secondVertex = polyVertices.elementAtOrNull(1);
          final thirdVertex = polyVertices.elementAtOrNull(2);

          if (firstVertex case Float64x2(x: final firstX, y: final firstY)) {
            expect(firstX, equals(15));
            expect(firstY, equals(15));
          } else {
            fail('firstVertex is null');
          }

          if (secondVertex case Float64x2(x: final secondX, y: final secondY)) {
            expect(secondX, equals(25));
            expect(secondY, equals(15));
          } else {
            fail('secondVertex is null');
          }

          if (thirdVertex case Float64x2(x: final thirdX, y: final thirdY)) {
            expect(thirdX, equals(20));
            expect(thirdY, equals(25));
          } else {
            fail('thirdVertex is null');
          }

        case RectElement():
          fail('movedPoly is a RectElement');

        case OvalElement():
          fail('movedPoly is an OvalElement');

        case TextElement():
          fail('movedPoly is a TextElement');

        case MaskRegionElement():
          fail('movedPoly is a MaskRegionElement');

        case BackgroundElement():
          fail('movedPoly is a BackgroundElement');
      }
    });
  });

  group('DrawElementResizeExtension.resized', () {
    test('resizes a RectElement from bottom right correctly', () {
      const rect = RectElement(height: 50, width: 50, x: 10, y: 20);
      final resizedRect = rect.resized(dx: 10, dy: 15, handle: .bottomRight);

      expect(resizedRect.x, equals(10));
      expect(resizedRect.y, equals(20));
      expect(resizedRect.width, equals(60));
      expect(resizedRect.height, equals(65));
    });

    test('resizes a RectElement from top left correctly', () {
      const rect = RectElement(height: 50, width: 50, x: 10, y: 20);
      final resizedRect = rect.resized(dx: -10, dy: -5, handle: .topLeft);

      expect(resizedRect.width, equals(60));
      expect(resizedRect.x, equals(0));
      expect(resizedRect.height, equals(55));
      expect(resizedRect.y, equals(15));
    });

    test('enforces minSize when resizing', () {
      const rect = RectElement(height: 20, width: 20, x: 10, y: 10);
      final resizedRect = rect.resized(dx: -15, dy: -15, handle: .bottomRight);

      expect(resizedRect.width, equals(10));
      expect(resizedRect.height, equals(10));
    });

    test('resizes a PolygonElement correctly', () {
      final vertices = Float64x2List.fromList([
        Float64x2(10, 10),
        Float64x2(20, 10),
        Float64x2(15, 20),
      ]);
      final poly = PolygonElement(height: 10, vertices: vertices, width: 10, x: 10, y: 10);
      final resizedPoly = poly.resized(dx: 10, dy: 10, handle: .bottomRight);

      switch (resizedPoly) {
        case PolygonElement(
          height: final h,
          vertices: final polyVertices,
          width: final w,
          x: final px,
          y: final py,
        ):
          expect(px, equals(10));
          expect(py, equals(10));
          expect(w, equals(20));
          expect(h, equals(20));

          final firstVertex = polyVertices.firstOrNull;
          final secondVertex = polyVertices.elementAtOrNull(1);
          final thirdVertex = polyVertices.elementAtOrNull(2);

          if (firstVertex case Float64x2(x: final firstX, y: final firstY)) {
            expect(firstX, equals(10));
            expect(firstY, equals(10));
          } else {
            fail('firstVertex is null');
          }

          if (secondVertex case Float64x2(x: final secondX, y: final secondY)) {
            expect(secondX, equals(30));
            expect(secondY, equals(10));
          } else {
            fail('secondVertex is null');
          }

          if (thirdVertex case Float64x2(x: final thirdX, y: final thirdY)) {
            expect(thirdX, equals(20));
            expect(thirdY, equals(30));
          } else {
            fail('thirdVertex is null');
          }

        case RectElement():
          fail('resizedPoly is a RectElement');

        case OvalElement():
          fail('resizedPoly is an OvalElement');

        case TextElement():
          fail('resizedPoly is a TextElement');

        case MaskRegionElement():
          fail('resizedPoly is a MaskRegionElement');

        case BackgroundElement():
          fail('resizedPoly is a BackgroundElement');
      }
    });

    test(
      'handles resizing PolygonElement with 0 width/height correctly to avoid division by zero',
      () {
        final vertices = Float64x2List.fromList([
          Float64x2(10, 10),
          Float64x2(10, 10),
          Float64x2(10, 10),
        ]);
        final poly = PolygonElement(height: 0, vertices: vertices, width: 0, x: 10, y: 10);
        final resizedPoly = poly.resized(dx: 10, dy: 10, handle: .bottomRight);

        switch (resizedPoly) {
          case PolygonElement(height: final h, vertices: final polyVertices, width: final w):
            expect(w, equals(10));
            expect(h, equals(10));

            final firstVertex = polyVertices.firstOrNull;
            final secondVertex = polyVertices.elementAtOrNull(1);
            final thirdVertex = polyVertices.elementAtOrNull(2);

            if (firstVertex case Float64x2(x: final firstX, y: final firstY)) {
              expect(firstX, equals(10));
              expect(firstY, equals(10));
            } else {
              fail('firstVertex is null');
            }

            if (secondVertex case Float64x2(x: final secondX, y: final secondY)) {
              expect(secondX, equals(10));
              expect(secondY, equals(10));
            } else {
              fail('secondVertex is null');
            }

            if (thirdVertex case Float64x2(x: final thirdX, y: final thirdY)) {
              expect(thirdX, equals(10));
              expect(thirdY, equals(10));
            } else {
              fail('thirdVertex is null');
            }

          case RectElement():
            fail('resizedPoly is a RectElement');

          case OvalElement():
            fail('resizedPoly is an OvalElement');

          case TextElement():
            fail('resizedPoly is a TextElement');

          case MaskRegionElement():
            fail('resizedPoly is a MaskRegionElement');

          case BackgroundElement():
            fail('resizedPoly is a BackgroundElement');
        }
      },
    );
    test(
      'resizes a RectElement from centerLeft, centerRight, topCenter, and bottomCenter correctly',
      () {
        const rect = RectElement(height: 50, width: 50, x: 10, y: 20);

        final leftResized = rect.resized(dx: -10, dy: 10, handle: .centerLeft);
        expect(leftResized.x, equals(0));
        expect(leftResized.y, equals(20));
        expect(leftResized.width, equals(60));
        expect(leftResized.height, equals(50));

        final rightResized = rect.resized(dx: 10, dy: 10, handle: .centerRight);
        expect(rightResized.x, equals(10));
        expect(rightResized.y, equals(20));
        expect(rightResized.width, equals(60));
        expect(rightResized.height, equals(50));

        final topResized = rect.resized(dx: 10, dy: -10, handle: .topCenter);
        expect(topResized.x, equals(10));
        expect(topResized.y, equals(10));
        expect(topResized.width, equals(50));
        expect(topResized.height, equals(60));

        final bottomResized = rect.resized(dx: 10, dy: 10, handle: .bottomCenter);
        expect(bottomResized.x, equals(10));
        expect(bottomResized.y, equals(20));
        expect(bottomResized.width, equals(50));
        expect(bottomResized.height, equals(60));
      },
    );

    test('resizes a MaskRegionElement correctly', () {
      const mask = MaskRegionElement(height: 50, width: 50, x: 10, y: 20);
      final resizedMask = mask.resized(dx: 10, dy: 15, handle: .bottomRight);

      expect(resizedMask.x, equals(10));
      expect(resizedMask.y, equals(20));
      expect(resizedMask.width, equals(60));
      expect(resizedMask.height, equals(65));
    });
  });
}
