// ignore_for_file: unused_field, prefer-single-declaration-per-file, prefer-correct-identifier-length
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
final class FfiResultCountStruct extends Struct {
  @Uint8()
  external int tag;

  external FfiResultCountPayload payload;

  @Array(3)
  external Array<Uint8> _pad;

  FfiResultCount toDomain(Pointer<Uint8> errorBuf, int errorCap) {
    if (tag == 0) return OkCount(payload.ok);
    final error = payload.err;
    final message = decodeFfiMessage(error, errorBuf, errorCap);

    return ErrCount(mapFfiErrorCode(error.code), message);
  }
}
