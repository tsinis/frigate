import 'dart:typed_data';
import 'package:frigatebird/src/constants/draw_constants.dart';
import 'package:frigatebird/src/model/draw_element.dart';
import 'package:frigatebird/src/model/ffi_color.dart';
import 'package:test/test.dart';

const _emptyText = '';

void main() {
  group('DrawElement base defaults (observed on TextElement which does NOT override them)', () {
    const text = TextElement(text: 'x', x: 0, y: 0);

    test(
      'fill defaults to opaque black',
      () => expect(text.fillColor.argb, FfiColor.black.argb, reason: 'FfiColor.black'),
    );

    test('blur and rotation default to zero', () {
      expect(text.blur, 0, reason: 'blur default');
      expect(text.rotation, 0, reason: 'rotation default');
    });

    test('blur and rotation are ints (SMI-friendly)', () {
      final TextElement(:blur, :rotation) = text;
      final isInt = isA<int>();
      expect(blur, isInt, reason: 'blur type');
      expect(rotation, isInt, reason: 'rotation type');
    });
  });

  group('RectElement default overrides', () {
    const rect = RectElement(height: 1, width: 1, x: 0, y: 0);

    test(
      'fill color is transparent so the image shows through the rectangle',
      () => expect(rect.fillColor.argb, FfiColor.transparent.argb),
    );

    test(
      'outline color is black so the rectangle is visible without extra setup',
      () => expect(rect.outlineColor.argb, FfiColor.black.argb),
    );

    test('outline thickness is 2 pixels', () => expect(rect.outlineThickness, 2));
  });

  group('RectElement.cornerRadius', () {
    test(
      'defaults to 0 (sharp corners)',
      () => expect(const RectElement(height: 1, width: 1, x: 0, y: 0).cornerRadius, isZero),
    );
  });

  group('TextElement.fontSize', () {
    test('is an alias for the inherited height field', () {
      const text = TextElement(height: 42, text: 'q', x: 0, y: 0);
      expect(text.fontSize, text.height, reason: 'fontSize and height are the same storage');
      expect(text.fontSize, 42);
    });

    test(
      'hides width at zero',
      () => expect(const TextElement(height: 42, text: 'q', x: 0, y: 0).width, 0),
    );

    test(
      'defaults to TextElement.defaultFontSize',
      () => expect(const TextElement(text: 'q', x: 0, y: 0).fontSize, TextElement.defaultFontSize),
    );
  });

  group('OvalElement default overrides', () {
    const oval = OvalElement(height: 1, width: 1, x: 0, y: 0);

    test(
      'fill color is transparent so the image shows through the oval',
      () => expect(oval.fillColor.argb, FfiColor.transparent.argb),
    );

    test(
      'outline color is black so the oval is visible without extra setup',
      () => expect(oval.outlineColor.argb, FfiColor.black.argb),
    );

    test('outline thickness is 2 pixels', () => expect(oval.outlineThickness, 2));
  });

  group('sealed class type discrimination', () {
    test('RectElement is-check returns true', () {
      const e = RectElement(height: 1, width: 1, x: 0, y: 0);
      expect(e, isA<RectElement>(), reason: 'sealed subtype');
    });

    test('TextElement is-check returns true', () {
      const e = TextElement(text: _emptyText, x: 0, y: 0);
      expect(e, isA<TextElement>(), reason: 'sealed subtype');
    });

    test('sealed switch covers every subtype exhaustively', () {
      final elements = <DrawElement>[
        const RectElement(height: 1, width: 1, x: 0, y: 0),
        const TextElement(text: _emptyText, x: 0, y: 0),
        const OvalElement(height: 1, width: 1, x: 0, y: 0),
        PolygonElement(
          height: 1,
          vertices: Float64x2List.fromList([Float64x2(0, 0), Float64x2(1, 0), Float64x2(0, 1)]),
          width: 1,
          x: 0,
          y: 0,
        ),
        const MaskRegionElement(height: 1, width: 1, x: 0, y: 0),
      ];
      final types = elements
          .map(
            (e) => switch (e) {
              RectElement() => 'rect',
              TextElement() => 'text',
              OvalElement() => 'oval',
              PolygonElement() => 'polygon',
              MaskRegionElement() => 'mask',
            },
          )
          .toSet();
      expect(
        types,
        const {'rect', 'text', 'oval', 'polygon', 'mask'}, // Dart 3.8 format.
        reason: 'switch is exhaustive over all types',
      );
    });
  });

  group('MaskRegionElement copyWith and toString', () {
    test('default properties are set correctly', () {
      const mask = MaskRegionElement(height: 50, width: 80, x: 10, y: 20);
      expect(mask.blur, equals(DrawConstants.defaultBlurRadius));
      expect(mask.fillColor, equals(FfiColor.transparent));
      expect(mask.outlineColor, FfiColor.transparent);
      expect(mask.outlineThickness, isZero);
    });

    test('copyWith works correctly', () {
      const mask = MaskRegionElement(height: 50, width: 80, x: 10, y: 20);
      final updated = mask.copyWith(blur: 25, height: 100, rotation: 90, width: 200, x: 5, y: 15);

      expect(updated.blur, equals(25));
      expect(updated.height, equals(100));
      expect(updated.rotation, equals(90));
      expect(updated.width, equals(200));
      expect(updated.x, equals(5));
      expect(updated.y, equals(15));
    });

    test('toString contains correct values', () {
      const mask = MaskRegionElement(height: 50, width: 80, x: 10, y: 20);
      final str = mask.toString();
      expect(str, contains('MaskRegionElement'));
      expect(str, contains('x: 10.0'));
      expect(str, contains('y: 20.0'));
      expect(str, contains('width: 80.0'));
      expect(str, contains('height: 50.0'));
    });

    test('value equality and hashCode works correctly', () {
      const FfiColor blackColor = .black;
      const FfiColor transparentColor = .transparent;
      const baseElement = MaskRegionElement(
        blur: 5,
        fillColor: blackColor,
        height: 50,
        rotation: 10,
        width: 80,
        x: 10,
        y: 20,
      );
      const identicalElement = MaskRegionElement(
        blur: 5,
        fillColor: blackColor,
        height: 50,
        rotation: 10,
        width: 80,
        x: 10,
        y: 20,
      );
      const yOffsetElement = MaskRegionElement(
        blur: 5,
        fillColor: blackColor,
        height: 50,
        rotation: 10,
        width: 80,
        x: 10,
        y: 21,
      );
      const redFillElement = MaskRegionElement(
        blur: 5,
        fillColor: FfiColor(0xFFFF0000),
        height: 50,
        rotation: 10,
        width: 80,
        x: 10,
        y: 20,
      );

      final baseHashCode = baseElement.hashCode;

      expect(baseElement, equals(identicalElement));
      expect(baseHashCode, equals(identicalElement.hashCode));
      expect(baseElement, isNot(equals(yOffsetElement)));
      expect(baseHashCode, isNot(equals(yOffsetElement.hashCode)));
      expect(baseElement, isNot(equals(redFillElement)));
      expect(baseHashCode, isNot(equals(redFillElement.hashCode)));

      // Test copyWith with the same fillColor.
      final copiedSameColor = baseElement.copyWith(fillColor: baseElement.fillColor);
      expect(copiedSameColor, equals(baseElement));
      expect(copiedSameColor.hashCode, equals(baseHashCode));

      // Test copyWith with a different fillColor.
      final copiedDiffColor = baseElement.copyWith(fillColor: transparentColor);
      expect(copiedDiffColor, isNot(equals(baseElement)));
      expect(copiedDiffColor.hashCode, isNot(equals(baseHashCode)));
      expect(copiedDiffColor.fillColor, equals(transparentColor));

      // Assert that attempting to change outline properties throws assertions.
      final throwsAssertion = throwsA(isA<AssertionError>());
      expect(() => baseElement.copyWith(outlineColor: blackColor), throwsAssertion);
      expect(() => baseElement.copyWith(outlineThickness: 2), throwsAssertion);
    });
  });
}
