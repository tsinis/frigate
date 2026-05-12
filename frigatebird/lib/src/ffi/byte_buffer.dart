import 'dart:ffi';

/// Native finalizer signature for freeing a [ByteBuffer].
typedef ByteBufferFinalizerFunc = Void Function(Pointer<ByteBuffer>);

/// Matches Rust `#[repr(C)] ByteBuffer` exactly.
final class ByteBuffer extends Struct {
  external Pointer<Uint8> data;

  @Size()
  external int length;
}
