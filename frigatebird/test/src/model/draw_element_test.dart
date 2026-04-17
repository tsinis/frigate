import 'package:frigatebird/src/ffi/ffi_element_type.dart';
import 'package:frigatebird/src/model/draw_element.dart';
import 'package:frigatebird/src/model/ffi_color.dart';
import 'package:test/test.dart';

const _emptyText = '';

void main() {
  group('DrawElement.elementType', () {
    test(
      'RectElement returns rectangle',
      () => expect(
        const RectElement(height: 1, width: 1, x: 0, y: 0).elementType,
        FfiElementType.rectangle,
      ),
    );

    test(
      'TextElement returns text',
      () =>
          expect(const TextElement(text: _emptyText, x: 0, y: 0).elementType, FfiElementType.text),
    );

    test('sealed dispatch covers every subtype exhaustively', () {
      // Adding (say) CircleElement will require a FfiElementType.circle *and* a DrawElement
      // subtype that returns it — this test fails otherwise.
      const elements = <DrawElement>[
        RectElement(height: 1, width: 1, x: 0, y: 0),
        TextElement(text: _emptyText, x: 0, y: 0),
      ];
      expect(
        elements.map((e) => e.elementType).toSet(),
        FfiElementType.values.toSet(),
        reason: 'every FfiElementType value must be produced by some DrawElement subtype',
      );
    });
  });

  group('DrawElement base defaults (observed on TextElement which does NOT override them)', () {
    const text = TextElement(text: 'x', x: 0, y: 0);

    test(
      'fill defaults to opaque black',
      () => expect(text.fillColor.argb, FfiColor.black.argb, reason: 'FfiColor.black'),
    );

    test(
      'outline color defaults to transparent',
      () =>
          expect(text.outlineColor.argb, FfiColor.transparent.argb, reason: 'FfiColor.transparent'),
    );

    test('blur and rotation default to zero', () {
      expect(text.blur, 0, reason: 'blur default');
      expect(text.rotation, 0, reason: 'rotation default');
    });

    test('blur/outlineThickness/rotation are ints (SMI-friendly)', () {
      final TextElement(:blur, :outlineThickness, :rotation) = text;
      final isInt = isA<int>();
      expect(blur, isInt, reason: 'blur type');
      expect(outlineThickness, isInt, reason: 'outlineThickness type');
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

  group('TextElement.fontSize', () {
    test('is an alias for the inherited height field', () {
      const text = TextElement(fontSize: 42, text: 'q', x: 0, y: 0);
      expect(text.fontSize, text.height, reason: 'fontSize and height are the same storage');
      expect(text.fontSize, 42);
    });

    test(
      'hides width at zero',
      () => expect(const TextElement(fontSize: 42, text: 'q', x: 0, y: 0).width, 0),
    );

    test(
      'defaults to TextElement.defaultFontSize',
      () => expect(const TextElement(text: 'q', x: 0, y: 0).fontSize, TextElement.defaultFontSize),
    );
  });
}
