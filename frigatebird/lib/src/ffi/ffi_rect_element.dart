// ignore_for_file: prefer-single-declaration-per-file
import 'dart:ffi';

import '../model/draw_element.dart';

/// Matches Rust `#[repr(C)] FfiRectElement` exactly: 4 × f64 (32) + 3 × u32 (12) = 44 content,
/// padded to **48 bytes** for 8-byte struct alignment.
///
/// Coordinates are **document-space pixels** (no normalization). Rust uses them as-is.
/// [outlineThickness] is `u32` on the wire to stay in Dart's SMI range without boxing.
final class FfiRectElement extends Struct {
  @Double()
  external double x;

  @Double()
  external double y;

  @Double()
  external double width;

  @Double()
  external double height;

  @Uint32()
  external int outlineThickness;

  @Uint32()
  external int outlineColorArgb;

  /// Corner radius in pixels (0 = sharp corners). Clamped to `min(width, height) / 2` at
  /// render time on the Rust side.
  @Uint32()
  external int shapeParam;
}

extension RectElementFfi on RectElement {
  void writeTo(Pointer<FfiRectElement> pointer) {
    pointer.ref
      ..x = x
      ..y = y
      ..width = width
      ..height = height
      ..outlineThickness = outlineThickness
      ..outlineColorArgb = outlineColor.argb
      ..shapeParam = shapeParam;
  }
}

extension RectElementListFfi on List<RectElement> {
  /// Allocate a contiguous array, write each element's pixel-space fields, return the pointer.
  /// Caller MUST free the returned pointer.
  Pointer<FfiRectElement> toNative(Allocator allocator) {
    final pointer = allocator<FfiRectElement>(length);
    for (int i = 0; i < length; i += 1) {
      this[i].writeTo(pointer + i);
    }

    return pointer;
  }
}
