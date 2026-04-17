// ignore_for_file: prefer-single-declaration-per-file
import 'dart:ffi';

import '../model/draw_element.dart';

/// Matches Rust `#[repr(C)] FfiRectElement` exactly: 4 × f64 (32) + 2 × u32 (8) = **40 bytes**.
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
}

extension RectElementFfi on RectElement {
  void writeTo(Pointer<FfiRectElement> pointer) {
    pointer.ref
      ..x = x
      ..y = y
      ..width = width
      ..height = height
      ..outlineThickness = outlineThickness
      ..outlineColorArgb = outlineColor.argb;
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
