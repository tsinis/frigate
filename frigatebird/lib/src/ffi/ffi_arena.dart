import 'dart:ffi';

/// A multi-buffer arena for passing variable-length data across FFI.
/// Matches Rust `#[repr(C)] FfiArena`.
final class FfiArena extends Struct {
  external Pointer<Uint8> textBuf;
  @Size()
  external int textLen;

  external Pointer<Uint8> imageBuf;
  @Size()
  external int imageLen;

  external Pointer<Uint8> errorBuf;
  @Size()
  external int errorCap;
}
