// Colocates the Struct, its writer extension, and the list-writer extension — they're a
// single FFI surface and split across files would be artificial separation.
// ignore_for_file: prefer-single-declaration-per-file, unused_field, member-ordering
// _pad is a required FFI layout artefact, not unused dead code; its position after
// outlineThickness is dictated by the wire layout — not Dart style conventions.
import 'dart:ffi';
import '../model/draw_element.dart';

/// Matches Rust `#[repr(C)] FfiRectElement` exactly:
/// 4 × f64 (32) + u8 (1) + pad3 (3) + u32 (4) + u32 (4) = 44 content,
/// padded to **48 bytes** for 8-byte struct alignment.
///
/// Coordinates are **document-space pixels** (no normalization). Rust uses them as-is.
/// [outlineThickness] is `u8` (stroke width in pixels; 0–255 covers every realistic overlay).
/// [outlineColorArgb] and [shapeParam] remain `u32` — ARGB color occupies a full 4-byte slot
/// and keeps [shapeParam] naturally aligned at offset 40 without extra padding fields.
final class FfiRectElement extends Struct {
  @Double()
  external double x;

  @Double()
  external double y;

  @Double()
  external double width;

  @Double()
  external double height;

  @Uint8()
  external int outlineThickness;

  /// Three bytes of C alignment padding between [outlineThickness] (u8, offset 32) and
  /// [outlineColorArgb] (u32, offset 36). Required to match `#[repr(C)]` implicit padding.
  @Array(3)
  // ignore: unused_field, _pad is required C alignment padding; not dead code.
  external Array<Uint8> _pad;

  @Uint32()
  external int outlineColorArgb;

  /// Corner radius in pixels (0 = sharp corners). Clamped to `min(width, height) / 2` at
  /// render time on the Rust side.
  @Uint32()
  external int shapeParam;
}

extension RectElementFfi on RectElement {
  void writeTo(Pointer<FfiRectElement> pointer) {
    assert(outlineThickness >= 0 && outlineThickness <= 255, 'outlineThickness must be in 0..255');
    assert(cornerRadius >= 0 && cornerRadius <= 65535, 'cornerRadius must be in 0..65535');

    pointer.ref
      ..x = x
      ..y = y
      ..width = width
      ..height = height
      ..outlineThickness = outlineThickness.clamp(0, 255)
      ..outlineColorArgb = outlineColor.argb
      ..shapeParam = cornerRadius.clamp(0, 65535);
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
