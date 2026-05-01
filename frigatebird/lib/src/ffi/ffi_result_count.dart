// ignore_for_file: prefer-single-declaration-per-file, prefer-correct-identifier-length
import 'dart:ffi';

import 'ffi_error.dart';
import 'ffi_result_common.dart';

/// Dart-side representation of a Rust `Result<u32, FfiError>`.
sealed class FfiResultCount {
  const FfiResultCount();
}

final class OkCount extends FfiResultCount {
  const OkCount(this.value);
  final int value;
}

final class ErrCount extends FfiResultCount {
  const ErrCount(this.code, this.message);
  final FfiErrorCode code;
  final String message;
}

/// FFI payload for a result that returns a u32.
final class FfiResultCountPayload extends Union {
  @Uint32()
  external int ok;
  external FfiError err;
}

/// Raw FFI struct for a `Result<u32, FfiError>`.
///
/// Rust `repr(C, u8)` enum layout: discriminant `u8` (offset 0) + 3-byte implicit padding
/// (Dart inserts this to align the `u32` union variant to its natural 4-byte boundary)
/// + payload union (4 bytes) = **8 bytes total**, align 4.
final class FfiResultCountStruct extends Struct {
  @Uint8()
  external int tag;

  // No explicit _pad here: the 3 padding bytes between the discriminant and the payload union
  // are inserted automatically by Dart's C-layout rules (same as Rust's implicit padding).
  // Adding @Array(3) _pad here would push the struct to 12 bytes — 4 beyond Rust's 8.

  external FfiResultCountPayload payload;

  FfiResultCount toDomain(Pointer<Uint8> errorBuf, int errorCap) {
    if (tag == 0) return OkCount(payload.ok);
    final error = payload.err;
    final message = decodeFfiMessage(error, errorBuf, errorCap);

    return ErrCount(mapFfiErrorCode(error.code), message);
  }
}
