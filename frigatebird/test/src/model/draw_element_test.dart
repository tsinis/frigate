import 'dart:typed_data';
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
      ];
      final types = elements
          .map(
            (e) => switch (e) {
              RectElement() => 'rect',
              TextElement() => 'text',
              OvalElement() => 'oval',
              PolygonElement() => 'polygon',
            },
          )
          .toSet();
      expect(
        types,
        const {'rect', 'text', 'oval', 'polygon'}, // Dart 3.8 format.
        reason: 'switch is exhaustive over all types',
      );
    });
  });
}
