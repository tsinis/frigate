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
    test('RectElement decode(encode(x)) == x round-trip with generated data', () {
      final random = Random(42); // Seeded for deterministic tests.

      // Test with various list sizes to mimic property testing.
      final testCases = [
        _generateRects(1, random),
        _generateRects(10, random),
        _generateRects(50, random),
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
          for (final (i, item) in decoded.indexed) {
            expect(item.toString(), elements[i].toString());
          }
        } finally {
          handle.free();
        }
      }
    });
  });
}

List<RectElement> _generateRects(int count, Random random) => .generate(count, (_) {
  const colorMax = 0xFFFFFFFF + 1;
  final randDouble = random.nextDouble();

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
