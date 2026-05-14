// ignore_for_file: prefer-moving-to-variable
import 'dart:ffi';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:frigatebird/src/ffi/ffi_marshal.dart';
import 'package:frigatebird/src/model/draw_element.dart';
import 'package:frigatebird/src/model/ffi_color.dart';
import 'package:test/test.dart';

void main() {
  group('FFI Marshal Property-like Tests', () {
    test('DrawElement decode(encode(x)) == x round-trip with generated data', () {
      final random = Random(42); // Seeded for deterministic tests.

      // Test with various list sizes to mimic property testing.
      final testCases = [
        _generateRects(1, random),
        _generateRects(10, random),
        _generateRects(50, random),
        _generateOvals(1, random),
        _generateOvals(10, random),
        _generateOvals(50, random),
        _generateTexts(1, random),
        _generateTexts(10, random),
        _generateTexts(50, random),
      ];

      for (final elements in testCases) {
        if (elements.isEmpty) continue;

        final handle = FfiMarshal.encodeElements(elements, malloc);
        try {
          final decodeResult = FfiMarshal.decodeElements(
            handle.elementsPtr,
            handle.count,
            handle.textBufferPtr,
            payloadBufferLen: handle.arena.ptr.ref.textLen,
          );
          final decoded = decodeResult.elements;

          expect(decoded.length, elements.length);
          for (final (i, dec) in decoded.indexed) {
            _assertElementsEqual(dec, elements[i]);
          }
        } finally {
          handle.free();
        }
      }
    });
  });
}

void _assertElementsEqual(DrawElement actual, DrawElement expected) {
  expect(actual.runtimeType, expected.runtimeType);
  expect(actual.x, expected.x);
  expect(actual.y, expected.y);
  expect(actual.rotation, expected.rotation);
  expect(actual.fillColor.argb, expected.fillColor.argb);
  expect(actual.blur, expected.blur);

  if (actual is RectElement && expected is RectElement) {
    expect(actual.width, expected.width);
    expect(actual.height, expected.height);
    expect(actual.outlineColor.argb, expected.outlineColor.argb);
    expect(actual.outlineThickness, expected.outlineThickness);
    expect(actual.cornerRadius, expected.cornerRadius);
  } else if (actual is OvalElement && expected is OvalElement) {
    expect(actual.width, expected.width);
    expect(actual.height, expected.height);
    expect(actual.outlineColor.argb, expected.outlineColor.argb);
    expect(actual.outlineThickness, expected.outlineThickness);
  } else if (actual is TextElement && expected is TextElement) {
    expect(actual.text, expected.text);
    expect(actual.fontId, expected.fontId);
    expect(actual.fontSize, expected.fontSize);
  }
}

List<RectElement> _generateRects(int count, Random random) => .generate(count, (_) {
  final randDouble = random.nextDouble();
  const colorMax = 0xFFFFFFFF + 1;

  return RectElement(
    blur: random.nextInt(256),
    cornerRadius: random.nextInt(65536),
    fillColor: FfiColor(random.nextInt(colorMax)),
    height: randDouble * 1000,
    outlineColor: FfiColor(random.nextInt(colorMax)),
    outlineThickness: random.nextInt(256),
    rotation: random.nextInt(360) - 180,
    width: randDouble * 1000,
    x: randDouble * 1000 - 500,
    y: randDouble * 1000 - 500,
  );
});

List<OvalElement> _generateOvals(int count, Random random) => .generate(count, (_) {
  final randDouble = random.nextDouble();
  const colorMax = 0xFFFFFFFF + 1;

  return OvalElement(
    blur: random.nextInt(256),
    fillColor: FfiColor(random.nextInt(colorMax)),
    height: randDouble * 1000,
    outlineColor: FfiColor(random.nextInt(colorMax)),
    outlineThickness: random.nextInt(256),
    rotation: random.nextInt(360) - 180,
    width: randDouble * 1000,
    x: randDouble * 1000 - 500,
    y: randDouble * 1000 - 500,
  );
});

List<TextElement> _generateTexts(int count, Random random) => .generate(count, (_) {
  final randDouble = random.nextDouble();
  const colorMax = 0xFFFFFFFF + 1;

  return TextElement(
    blur: random.nextInt(256),
    fillColor: FfiColor(random.nextInt(colorMax)),
    fontId: random.nextInt(65536),
    height: randDouble * 100,
    rotation: random.nextInt(360) - 180,
    text: 'Rand: ${random.nextInt(1_000_000)}',
    x: randDouble * 1000 - 500,
    y: randDouble * 1000 - 500,
  );
});
