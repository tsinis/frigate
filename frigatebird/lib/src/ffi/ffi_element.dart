// Padding fields are required FFI layout artefacts, not unused dead code.
// ignore_for_file: unused_field

// All four payload structs + the outer FfiElement are a single FFI surface; splitting across
// files would create artificial import indirection for tightly coupled layout types.
// ignore_for_file: prefer-single-declaration-per-file

// The _pad fields in TextPayload and FfiElement must appear at specific byte offsets dictated
// by the Rust #[repr(C)] layout and cannot be moved after public fields.
// ignore_for_file: member-ordering

import 'dart:ffi';

import 'ffi_abi.dart';

/// Payload for a rectangle element.
final class RectanglePayload extends Struct {
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

  @Uint8()
  external int outlineThickness;

  @Uint8()
  external int blur;

  @Uint16()
  external int cornerRadius;
}

/// Payload for a text element.
final class TextPayload extends Struct {
  @Double()
  external double x;

  @Double()
  external double y;

  @Double()
  external double height;

  @Int32()
  external int rotationDeg;

  @Uint32()
  external int fillColorArgb;

  @Uint8()
  external int blur;

  /// Explicit padding to keep `fontId` 4-byte aligned, matching Rust `_pad: [u8; 3]`.
  @Array(3)
  external Array<Uint8> _pad;

  @Uint32()
  external int fontId;

  @Uint32()
  external int textOffset;

  @Uint32()
  external int textLen;
}

/// Payload for an oval element.
final class OvalPayload extends Struct {
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

  @Uint8()
  external int outlineThickness;

  @Uint8()
  external int blur;

  /// Explicit padding to keep the struct size 48 bytes, matching Rust `_pad: [u8; 2]`.
  @Array(2)
  external Array<Uint8> _pad;
}

/// Union of all possible element payloads.
final class FfiPayload extends Union {
  /// Size anchor: forces the union to be 48 bytes to match Rust payloads.
  @Array(FfiAbi.payloadBytes)
  external Array<Uint8> _raw;

  external RectanglePayload rectangle;
  external TextPayload text;
  external OvalPayload oval;
}

/// Tagged-union element struct passed across the FFI boundary.
/// Matches Rust `#[repr(C, u8)] FfiElement`.
final class FfiElement extends Struct {
  @Uint8()
  external int tag;

  /// Explicit padding after the tag byte so `payload` starts at offset 8 (double alignment),
  /// matching the Rust `#[repr(C, u8)]` layout: tag(1) + pad(7) + payload(48) = 56 bytes.
  @Array(7)
  external Array<Uint8> _pad;

  external FfiPayload payload;
}
