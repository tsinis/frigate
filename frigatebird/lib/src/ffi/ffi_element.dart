import 'dart:ffi';

/// Unified element struct passed across the FFI boundary. Tagged by [elementType] so a single
/// array can mix shape kinds. Matches Rust `#[repr(C)] FfiElement` byte-for-byte: total
/// **72 bytes** (verified by a runtime `sizeOf` test).
///
/// Variable-length text lives in a separate shared UTF-8 buffer — each text element references its
/// slice via [textOffset] (byte offset) and [textLength] (byte length).
///
/// [blur], [outlineThickness] and [rotationDeg] are packed as `u32`/`i32` on the wire (not `f64`):
/// the Dart-side model keeps them as `int`, which stays in the SMI tag range without heap boxing.
/// Rust converts [rotationDeg] to radians at render time.
final class FfiElement extends Struct {
  @Uint32()
  external int elementType;

  // 4 bytes implicit padding inserted here by Dart Struct layout to align the next f64 to 8.

  @Double()
  external double x;

  @Double()
  external double y;

  @Double()
  external double width;

  @Double()
  external double height;

  @Int32()
  external int rotationDeg;

  @Uint32()
  external int fillColorArgb;

  @Uint32()
  external int outlineColorArgb;

  @Uint32()
  external int outlineThickness;

  @Uint32()
  external int blur;

  @Uint32()
  external int textOffset;

  @Uint32()
  external int textLength;

  /// Generic shape-specific scalar in pixels — interpreted per-element-type by Rust:
  /// rectangle = corner radius, text = unused (always 0). Fits in the previous trailing
  /// padding slot so total struct size stays 72 bytes.
  @Uint32()
  external int shapeParam;
}
