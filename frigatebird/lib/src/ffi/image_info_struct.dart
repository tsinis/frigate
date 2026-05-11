import 'dart:ffi';

// Padding fields are required FFI layout artifacts, not unused dead code.
// ignore_for_file: unused_field

/// Mirrors Rust `#[repr(C)] ImageInformation`.
/// Layout MUST match `frigatebird/rust/src/lib.rs::ImageInformation`.
final class ImageInfoStruct extends Struct {
  @Uint32()
  external int width; // Post-orientation.

  @Uint32()
  external int height; // Post-orientation.

  @Uint8()
  external int format; // 0 = PNG, 1 = JPEG, 255 = unknown.

  @Uint8()
  external int orientation; // Raw EXIF tag 1..=8 (diagnostic only).

  @Array(2)
  external Array<Uint8> _pad;
}
