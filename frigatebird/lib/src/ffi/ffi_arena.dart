import 'dart:ffi';

import 'byte_buffer.dart';

/// Mirrors Rust `#[repr(C)] FfiArena`.
///
/// Layout MUST match `crates/<...>/src/ffi.rs::FfiArena`. If the Rust struct
/// changes (field order, types, sizes), update this declaration AND
/// `FfiAbi.assertArena()` together.
final class FfiArena extends Struct {
  external Pointer<Uint8> textBuf;
  @Size()
  external int textLen;

  // Reserved for future in-place image ops (e.g. byte-stream merge).
  // Always null/0 today — no Rust function reads these fields yet.
  external Pointer<Uint8> imageBuf;

  @Size()
  external int imageLen;

  external ByteBuffer error;
}
