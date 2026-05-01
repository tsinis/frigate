import 'dart:ffi';

import 'ffi_error.dart';
import 'ffi_result_common.dart';

/// Dart-side representation of a Rust `Result<(), FfiError>`.
sealed class FfiResultUnit {
  const FfiResultUnit();
}

final class OkUnit extends FfiResultUnit {
  const OkUnit();
}

final class ErrUnit extends FfiResultUnit {
  const ErrUnit(this.code, this.message);
  final FfiErrorCode code;
  final String message;
}

/// FFI payload for a result that returns nothing (void).
///
/// `_dummyOk` exists because Dart's `Union` type requires at least one field. The `Ok(())`
/// variant in Rust carries no payload; this byte is never read and is only present to satisfy
/// the Dart FFI layout requirement.
// ignore_for_file: unused_field, prefer-single-declaration-per-file
final class FfiResultUnitPayload extends Union {
  external FfiError err;
  @Uint8()
  external int _dummyOk;
}

/// Raw FFI struct for a Result<(), FfiError>.
///
/// Rust `repr(C, u8)` enum layout: discriminant `u8` (offset 0) + 1-byte implicit padding
/// (Dart inserts this automatically to align the `FfiError` union to its natural 2-byte boundary)
/// + payload union (4 bytes) = **6 bytes total**, align 2.
final class FfiResultUnitStruct extends Struct {
  @Uint8()
  external int tag;

  external FfiResultUnitPayload payload;

  // No explicit _pad here: Rust's implicit padding between the discriminant and the payload
  // union is handled by Dart's automatic C-layout rules. Adding an explicit byte would
  // over-extend the struct to 8 bytes, reading 2 bytes of stack garbage on every call.

  FfiResultUnit toDomain(Pointer<Uint8> errorBuf, int errorCap) {
    if (tag == 0) return const OkUnit();
    final error = payload.err;
    final message = decodeFfiMessage(error, errorBuf, errorCap);

    return ErrUnit(mapFfiErrorCode(error.code), message);
  }
}
