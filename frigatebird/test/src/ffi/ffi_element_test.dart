// Inline lambdas used by helper function; they capture shared bundle state so can't be extracted.
// ignore_for_file: prefer-extracting-function-callbacks
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:frigatebird/src/ffi/ffi_element.dart';
import 'package:frigatebird/src/ffi/ffi_element_type.dart';
import 'package:frigatebird/src/ffi/serialized_elements.dart';
import 'package:frigatebird/src/helpers/extensions/ffi/draw_element_list_ffi.dart';
import 'package:frigatebird/src/model/draw_element.dart';
import 'package:frigatebird/src/model/ffi_color.dart';
import 'package:test/test.dart';

/// Helper: serialize [elements], hand the result to [run], guarantee `free()` on exit.
T _withSerialized<T>(List<DrawElement> elements, T Function(SerializedElements bundle) run) {
  final serialized = elements.toNative(malloc);
  try {
    return run(serialized);
  } finally {
    serialized.free();
  }
}

void main() {
  group(FfiElement, () {
    test(
      'struct is 72 bytes (Rust-Dart layout lockstep)',
      () => expect(sizeOf<FfiElement>(), 72, reason: 'wire-size contract'),
    );
  });

  group(FfiElementType, () {
    test(
      'rectangle has wire value 0',
      () => expect(FfiElementType.rectangle.value, isZero, reason: 'rectangle discriminator'),
    );

    test(
      'text has wire value 1',
      () => expect(FfiElementType.text.value, 1, reason: 'text discriminator'),
    );
  });

  group('DrawElementListFfi.toNative', () {
    test('serializes a single rectangle in pixel space', () {
      const rect = RectElement(
        fillColor: FfiColor(0xFF_11_22_33),
        height: 50,
        outlineColor: FfiColor(0xFF_AA_BB_CC),
        outlineThickness: 4,
        rotation: 90,
        width: 100,
        x: 10,
        y: 20,
      );

      _withSerialized<void>([rect], (bundle) {
        final FfiElement(
          :elementType,
          :fillColorArgb,
          :height,
          :outlineColorArgb,
          :outlineThickness,
          :rotationDeg,
          :width,
          :x,
          :y,
        ) = bundle.elementsPtr.ref;
        expect(elementType, FfiElementType.rectangle.value, reason: 'discriminator');
        expect((x, y), (10.0, 20.0), reason: 'position');
        expect((width, height), (100.0, 50.0), reason: 'bounds');
        expect(outlineThickness, 4, reason: 'thickness round-trip');
        expect(fillColorArgb, 0xFF_11_22_33, reason: 'fill color round-trip');
        expect(outlineColorArgb, 0xFF_AA_BB_CC, reason: 'outline color round-trip');
        expect(rotationDeg, 90, reason: 'rotation stays in int degrees on the wire');
      });
    });

    test('serializes a TextElement and packs UTF-8 into shared buffer', () {
      const element = TextElement(
        fillColor: FfiColor(0xFF_FF_00_00),
        fontSize: 32,
        text: 'hello',
        x: 5,
        y: 6,
      );

      _withSerialized<void>([element], (bundle) {
        final FfiElement(:elementType, :height, :textLength, :textOffset, :x, :y) =
            bundle.elementsPtr.ref;
        expect(elementType, FfiElementType.text.value, reason: 'discriminator');
        expect((x, y), (5.0, 6.0), reason: 'position');
        expect(height, 32, reason: 'TextElement stores font size in base `height`');
        expect((textOffset, textLength), (0, 5), reason: 'UTF-8 slice for "hello"');
        expect(bundle.textBufferLen, 5, reason: 'shared text buffer holds exactly "hello"');
      });
    });

    test('mixed list packs each text slice with correct offsets', () {
      const rect = RectElement(height: 1, width: 1, x: 0, y: 0);
      const first = TextElement(text: 'AB', x: 0, y: 0);
      const second = TextElement(text: 'CDE', x: 0, y: 0);

      _withSerialized<void>([rect, first, second], (bundle) {
        expect(bundle.count, 3, reason: '3 elements written');
        expect(bundle.textBufferLen, 5, reason: '"AB" + "CDE" = 5 bytes');
        final firstText = (bundle.elementsPtr + 1).ref;
        final secondText = (bundle.elementsPtr + 2).ref;
        expect((firstText.textOffset, firstText.textLength), (0, 2), reason: 'first text slice');
        expect(
          (secondText.textOffset, secondText.textLength),
          (2, 3),
          reason: 'second text slice starts where first ended',
        );
      });
    });

    test('empty list produces zero elements and no text buffer', () {
      _withSerialized<void>(const [], (bundle) {
        expect((bundle.count, bundle.textBufferLen), (0, 0), reason: 'no allocation needed');
      });
    });

    test('rotation is passed as int degrees (Rust converts to radians)', () {
      const rect = RectElement(height: 1, rotation: 180, width: 1, x: 0, y: 0);

      _withSerialized<void>([rect], (bundle) {
        expect(
          bundle.elementsPtr.ref.rotationDeg,
          180,
          reason: 'degrees on the wire, no Dart-side conversion',
        );
      });
    });

    test('TextElement text bytes land contiguously in the shared buffer', () {
      const greeting = TextElement(text: 'Frigate', x: 0, y: 0);
      // ASCII: 'F','r','i','g','a','t','e'.
      const frigateAsciiBytes = [0x46, 0x72, 0x69, 0x67, 0x61, 0x74, 0x65];

      _withSerialized<void>([greeting], (bundle) {
        expect(bundle.textBufferLen, frigateAsciiBytes.length, reason: 'byte count');
        final bytes = bundle.textBufferPtr.asTypedList(bundle.textBufferLen);
        expect(bytes, frigateAsciiBytes, reason: 'bytes land in order in the shared buffer');
      });
    });
  });
}
