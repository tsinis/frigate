import 'dart:math' show pi;
import 'dart:typed_data';

import 'package:frigatebird/frigatebird.dart';
import 'package:test/test.dart';

void main() => group('DrawElementRotationExtension', () {
  const square = RectElement(height: 100, width: 100, x: 0, y: 0);

  group('rotationRadians', () {
    test('converts degrees to radians', () {
      const rotated = RectElement(height: 100, rotation: 180, width: 100, x: 0, y: 0);

      expect(rotated.rotationRadians, closeTo(pi, 1e-9));
    });
  });

  group('center', () {
    test('is the un-rotated bounding-box center', () {
      const rect = RectElement(height: 40, width: 60, x: 10, y: 20);

      expect((rect.centerX, rect.centerY), equals((40.0, 40.0)));
    });
  });

  group('rotatePoint', () {
    test('is identity at zero rotation', () {
      expect(square.rotatePoint((x: 7, y: 9)), equals((x: 7.0, y: 9.0)));
    });

    test('rotates the top-left corner clockwise by 90 degrees', () {
      const rotated = RectElement(height: 100, rotation: 90, width: 100, x: 0, y: 0);
      final point = rotated.rotatePoint((x: 0, y: 0));

      expect(point.x, closeTo(100, 1e-9));
      expect(point.y, closeTo(0, 1e-9));
    });
  });

  group('inverseRotatePoint', () {
    test('round-trips with rotatePoint', () {
      const rotated = RectElement(height: 100, rotation: 37, width: 100, x: 0, y: 0);
      final point = rotated.inverseRotatePoint(rotated.rotatePoint((x: 12, y: 84)));

      expect(point.x, closeTo(12, 1e-9));
      expect(point.y, closeTo(84, 1e-9));
    });
  });

  group('handleCenterFor', () {
    test('returns axis-aligned corner at zero rotation', () {
      expect(square.handleCenterFor(.bottomRight), equals((x: 100.0, y: 100.0)));
    });

    test('follows the shape when rotated 90 degrees', () {
      const rotated = RectElement(height: 100, rotation: 90, width: 100, x: 0, y: 0);
      final point = rotated.handleCenterFor(.topLeft);

      expect(point.x, closeTo(100, 1e-9));
      expect(point.y, closeTo(0, 1e-9));
    });
  });

  group('handleHitTest', () {
    test('hits the rotated handle position', () {
      const rotated = RectElement(height: 100, rotation: 90, width: 100, x: 0, y: 0);

      expect(rotated.handleHitTest((x: 100, y: 0), 6), equals(HandlePosition.topLeft));
    });

    test('misses when no handle is near', () {
      expect(square.handleHitTest((x: 50, y: 50), 6), isNull);
    });

    test('returns null for zero-size elements', () {
      const empty = RectElement(height: 0, width: 0, x: 0, y: 0);

      expect(empty.handleHitTest((x: 0, y: 0), 6), isNull);
    });
  });

  group('isPointInside', () {
    test('contains its center', () => expect(square.isPointInside((x: 50, y: 50)), isTrue));

    test('excludes a point above the axis-aligned square', () {
      expect(square.isPointInside((x: 50, y: -10)), isFalse);
    });

    test('includes that point once rotated 45 degrees', () {
      const rotated = RectElement(height: 100, rotation: 45, width: 100, x: 0, y: 0);

      expect(rotated.isPointInside((x: 50, y: -10)), isTrue);
    });

    test('uses an ellipse test for ovals', () {
      const oval = OvalElement(height: 100, width: 100, x: 0, y: 0);

      expect(oval.isPointInside((x: 2, y: 2)), isFalse, reason: 'corner is outside the ellipse');
    });

    test('honors slop for ovals near the edge', () {
      const oval = OvalElement(height: 100, width: 100, x: 0, y: 0);

      expect(
        oval.isPointInside((x: 103, y: 50), slop: 4),
        isTrue,
        reason: 'a point just past the ellipse edge but within slop must register a hit',
      );
    });

    test('ray-casts polygons', () {
      final triangle = PolygonElement(
        height: 100,
        vertices: Float64x2List.fromList([Float64x2(0, 0), Float64x2(100, 0), Float64x2(50, 100)]),
        width: 100,
        x: 0,
        y: 0,
      );

      expect(
        (triangle.isPointInside((x: 50, y: 10)), triangle.isPointInside((x: 5, y: 90))),
        equals((true, false)),
        reason: 'point inside triangle should be true, point outside should be false',
      );
    });
  });

  group('rotationKnobCenter', () {
    test('sits above top-center at zero rotation', () {
      expect(square.rotationKnobCenter(30), equals((x: 50.0, y: -30.0)));
    });
  });

  group('isPointOnKnob', () {
    test('hits the knob above the shape', () {
      expect(square.isPointOnKnob(30, 8, (x: 50, y: -30)), isTrue);
    });

    test('misses far from the knob', () {
      expect(square.isPointOnKnob(30, 8, (x: 50, y: 50)), isFalse);
    });
  });

  group('angleToPoint', () {
    test('reads zero straight above the center', () {
      expect(square.angleToPoint((x: 50, y: 0)), equals(0));
    });

    test('reads 90 to the right', () => expect(square.angleToPoint((x: 100, y: 50)), equals(90)));

    test(
      'reads 180 straight below',
      () => expect(square.angleToPoint((x: 50, y: 100)), equals(180)),
    );
  });

  group('transformedBy', () {
    test('rotation-only adds degrees and keeps geometry', () {
      final result = square.transformedBy((x: 50, y: 50), pi / 2);

      expect(
        (result.x, result.y, result.width, result.height, result.rotation),
        equals((0.0, 0.0, 100.0, 100.0, 90)),
        reason: 'rotation-only should not change geometry, only rotation',
      );
    });

    test('uniform scale grows about the pivot', () {
      final result = square.transformedBy((x: 50, y: 50), 0, scaleFactor: 2);

      expect(
        (result.x, result.y, result.width, result.height),
        equals((-50.0, -50.0, 200.0, 200.0)),
        reason: 'uniform scale should grow about the pivot point, not the shape center',
      );
    });

    test('translation shifts the focal point', () {
      final result = square.transformedBy((x: 50, y: 50), 0, translation: (x: 10, y: 20));

      expect((result.x, result.y), equals((10.0, 20.0)));
    });

    test('scales polygon vertices about their center', () {
      final triangle = PolygonElement(
        height: 100,
        vertices: Float64x2List.fromList([Float64x2(0, 0), Float64x2(100, 0), Float64x2(50, 100)]),
        width: 100,
        x: 0,
        y: 0,
      );
      final result = triangle.transformedBy((x: 50, y: 50), 0, scaleFactor: 2);

      expect((result.width, result.height), equals((200.0, 200.0)));
    });

    test('keeps the polygon bounding box in sync with the scaled vertices', () {
      final triangle = PolygonElement(
        height: 100,
        vertices: Float64x2List.fromList([Float64x2(0, 0), Float64x2(100, 0), Float64x2(50, 100)]),
        width: 100,
        x: 0,
        y: 0,
      );
      final result = triangle.transformedBy((x: 50, y: 50), 0, scaleFactor: 2);
      final box = switch (result) {
        PolygonElement(:final vertices) => PolygonElement.boundingBoxOf(vertices),
        RectElement() || OvalElement() || TextElement() || MaskRegionElement() => null,
      };

      expect(
        (result.x, result.y, result.width, result.height),
        equals((box?.x, box?.y, box?.width, box?.height)),
        reason: 'copyWith recomputes the bbox from vertices, so x/y/width/height stay consistent',
      );
    });

    test('clamps the scale so neither dimension shrinks below minSize', () {
      final result = square.transformedBy((x: 50, y: 50), 0, scaleFactor: 0.01);

      expect(
        (result.width, result.height),
        equals((10.0, 10.0)),
        reason: 'pinching far down must clamp to the default minSize, not collapse to ~1px',
      );
    });
  });

  group('rotatedResized', () {
    test('matches resized when rotation is zero', () {
      final rotated = square.rotatedResized(dx: 20, dy: 10, handle: .bottomRight);
      final plain = square.resized(dx: 20, dy: 10, handle: .bottomRight);

      expect(
        (rotated.x, rotated.y, rotated.width, rotated.height),
        equals((plain.x, plain.y, plain.width, plain.height)),
        reason: 'rotatedResized should match resized when rotation is zero',
      );
    });

    test('keeps the opposite corner pinned in screen space when rotated', () {
      const rotated = RectElement(height: 100, rotation: 30, width: 100, x: 0, y: 0);
      final before = rotated.handleCenterFor(.topLeft);
      final resized = rotated.rotatedResized(dx: 25, dy: 15, handle: .bottomRight);
      final after = resized.handleCenterFor(.topLeft);

      expect(after.x, closeTo(before.x, 1e-6));
      expect(after.y, closeTo(before.y, 1e-6));
    });

    test('honors the minimum size clamp', () {
      final resized = square.rotatedResized(dx: -200, dy: -200, handle: .bottomRight);

      expect((resized.width, resized.height), equals((10.0, 10.0)));
    });
  });
});
