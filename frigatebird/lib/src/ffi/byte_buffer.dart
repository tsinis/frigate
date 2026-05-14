import 'dart:ffi';

/// Native finalizer signature for freeing a [ByteBuffer].
typedef ByteBufferFinalizerFunc = Void Function(ByteBuffer);

/// Matches Rust `#[repr(C)] ByteBuffer` exactly.
final class ByteBuffer extends Struct {
  external Pointer<Uint8> ptr;

  @Size()
  external int len;
}
