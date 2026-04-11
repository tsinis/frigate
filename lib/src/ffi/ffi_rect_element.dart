// ignore_for_file: prefer-single-declaration-per-file
import 'dart:ffi';

import '../frigate_draw_dart.dart';

/// Matches Rust `#[repr(C)] FfiRectElement` exactly. 44 bytes data: 5x f64 (40) + 1x u32 (4),
/// padded to 48.
///
/// Coordinates are **normalized** (0.0-1.0 relative to image dimensions). Rust denormalizes using
/// its own decoded dimensions.
final class FfiRectElement extends Struct {
  @Double()
  external double x;

  @Double()
  external double y;

  @Double()
  external double width;

  @Double()
  external double height;

  @Double()
  external double strokeWidth;

  @Uint32()
  external int colorArgb;
}

extension RectElementFfi on RectElement {
  /// Normalize and write this element's data into pre-allocated native memory.
  ///
  /// Coordinates are divided by image dimensions to produce 0.0-1.0 range. Rust denormalizes using
  /// its own decoded dimensions, eliminating any Dart↔Rust decoder dimension mismatch.
  void writeTo(Pointer<FfiRectElement> pointer, {required int imgHeight, required int imgWidth}) {
    // ignore: avoid-mutating-parameters, it's purpose is to mutate the pointed-to struct fields.
    pointer.ref
      ..x = x / imgWidth
      ..y = y / imgHeight
      ..width = width / imgWidth
      ..height = height / imgHeight
      ..strokeWidth = strokeWidth / imgWidth
      ..colorArgb = color.argb;
  }
}

extension RectElementListFfi on List<RectElement> {
  /// Allocate native array, normalize + write all elements. Caller MUST free the returned pointer.
  Pointer<FfiRectElement> toNative(
    Allocator allocator, {
    required int imgHeight,
    required int imgWidth,
  }) {
    final pointer = allocator<FfiRectElement>(length);
    for (int i = 0; i < length; i += 1) {
      // ignore: avoid-unsafe-collection-methods, bounded by 0..length loop.
      this[i].writeTo(pointer + i, imgHeight: imgHeight, imgWidth: imgWidth);
    }

    return pointer;
  }
}
