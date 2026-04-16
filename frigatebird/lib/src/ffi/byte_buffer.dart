import 'dart:ffi';

/// Matches Rust `#[repr(C)] ByteBuffer` exactly.
final class ByteBuffer extends Struct {
  external Pointer<Uint8> data;

  @Size()
  external int length;
}
