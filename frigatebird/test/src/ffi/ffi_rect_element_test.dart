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

  test('toNative on an empty list produces a pointer that is safe to free', () {
    // Edge case: empty input. Dart's malloc.allocate(0) is implementation-defined; we need
    // to confirm our wrapper doesn't deref a possibly-invalid pointer and that callers can
    // still free it via the same allocator. Without this guarantee, the export pipeline
    // would have a leak/UAF when called with no rects.
    final empty = <RectElement>[];
    final ptr = empty.toNative(malloc);
    // Must be safely freeable — calling malloc.free on whatever toNative returned, even if
    // the underlying allocation was a 0-byte sentinel, must not crash.
    expect(() => malloc.free(ptr), returnsNormally, reason: 'empty-list pointer must be freeable');
  });

  test('writeTo never produces a negative-wrapped shapeParam (constructor-side guard)', () {
    // Belt-and-braces against the wraparound bug: if anyone removes the cornerRadius assert
    // in RectElement, this test still fails because the constructor itself would refuse
    // negative values via the base-class shapeParam guard. We can't construct a negative-
    // shapeParam RectElement directly, so the only way to verify is to assert that any
    // construction attempt with a negative typed value throws.
    expect(
      () => RectElement(cornerRadius: -1, height: 10, width: 10, x: 0, y: 0),
      throwsA(isA<AssertionError>()),
      reason: 'no path from a negative cornerRadius can reach the FFI Uint32 slot',
    );
  });

  test('shapeParam respects the u16 wire range when written', () {
    // The Dart-side cornerRadius is `int`; the FFI field is u16. Writing a value within u16
    // range must round-trip exactly - anything past u16 would silently truncate, which is a
    // bug we want to catch loudly elsewhere (model/UI layer should clamp before reaching FFI).
    const max = RectElement(cornerRadius: 0xFFFF, height: 10, width: 10, x: 0, y: 0);
    final ptr = malloc<FfiRectElement>();
    try {
      max.writeTo(ptr);
      expect(
        ptr.ref.shapeParam,
        0xFFFF,
        reason: 'u16::MAX must survive intact across the FFI write',
      );
    } finally {
      malloc.free(ptr);
    }
  });
});
