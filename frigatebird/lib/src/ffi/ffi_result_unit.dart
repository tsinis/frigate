// ignore_for_file: unused_field, prefer-single-declaration-per-file
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
final class FfiResultUnitPayload extends Union {
  external FfiError err;
  @Uint8()
  external int _dummyOk;
}

/// Raw FFI struct for a Result<(), FfiError>.
final class FfiResultUnitStruct extends Struct {
  @Uint8()
  external int tag;

  external FfiResultUnitPayload payload;

  @Uint8()
  external int _pad;

  FfiResultUnit toDomain(Pointer<Uint8> errorBuf, int errorCap) {
    if (tag == 0) return const OkUnit();
    final error = payload.err;
    final message = decodeFfiMessage(error, errorBuf, errorCap);

    return ErrUnit(mapFfiErrorCode(error.code), message);
  }
}
