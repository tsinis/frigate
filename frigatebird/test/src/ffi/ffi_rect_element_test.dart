import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:frigatebird/src/ffi/ffi_rect_element.dart';
import 'package:frigatebird/src/model/draw_element.dart';
import 'package:frigatebird/src/model/ffi_color.dart';
import 'package:test/test.dart';

void main() => group(FfiRectElement, () {
  test('struct is 48 bytes (Rust-Dart layout lockstep)', () {
    expect(sizeOf<FfiRectElement>(), 48, reason: 'wire-size contract after adding shapeParam');
  });

  test('writeTo round-trips every field including shapeParam', () {
    const rect = RectElement(
      cornerRadius: 13,
      height: 50,
      outlineColor: FfiColor(0xFF_AA_BB_CC),
      outlineThickness: 4,
      width: 100,
      x: 10,
      y: 20,
    );
    final ptr = malloc<FfiRectElement>();
    try {
      rect.writeTo(ptr);
      final FfiRectElement(
        :height,
        :outlineColorArgb,
        :outlineThickness,
        :shapeParam,
        :width,
        :x,
        :y,
      ) = ptr.ref;
      expect((x, y), (10.0, 20.0), reason: 'position round-trip');
      expect((width, height), (100.0, 50.0), reason: 'bounds round-trip');
      expect(outlineThickness, 4, reason: 'outline thickness round-trip');
      expect(outlineColorArgb, 0xFF_AA_BB_CC, reason: 'outline color round-trip');
      expect(shapeParam, 13, reason: 'corner radius reaches the wire as shape_param');
    } finally {
      malloc.free(ptr);
    }
  });

  test('toNative writes shapeParam contiguously across multiple rects', () {
    const inputs = <RectElement>[
      RectElement(cornerRadius: 1, height: 10, width: 10, x: 0, y: 0),
      RectElement(cornerRadius: 99, height: 10, width: 10, x: 0, y: 0),
      // Default cornerRadius == 0.
      RectElement(height: 10, width: 10, x: 0, y: 0),
    ];
    final ptr = inputs.toNative(malloc);
    try {
      expect((ptr + 0).ref.shapeParam, 1, reason: 'first rect shapeParam');
      expect((ptr + 1).ref.shapeParam, 99, reason: 'second rect shapeParam');
      expect((ptr + 2).ref.shapeParam, 0, reason: 'unset cornerRadius defaults to 0');
    } finally {
      malloc.free(ptr);
    }
  });

  test('shapeParam respects the u32 wire range when written', () {
    // The Dart-side cornerRadius is `int`; the FFI field is u32. Writing a value within u32
    // range must round-trip exactly - anything past u32 would silently truncate, which is a
    // bug we want to catch loudly elsewhere (model/UI layer should clamp before reaching FFI).
    const max = RectElement(cornerRadius: 0xFFFFFFFF, height: 10, width: 10, x: 0, y: 0);
    final ptr = malloc<FfiRectElement>();
    try {
      max.writeTo(ptr);
      expect(
        ptr.ref.shapeParam,
        0xFFFFFFFF,
        reason: 'u32::MAX must survive intact across the FFI write',
      );
    } finally {
      malloc.free(ptr);
    }
  });
});
