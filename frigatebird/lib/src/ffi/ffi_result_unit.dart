import 'dart:ffi';

import 'ffi_error.dart';
import 'ffi_result_common.dart';

/// Dart-side representation of a Rust `Result<(), FfiError>`.
sealed class FfiResultUnit {
  const FfiResultUnit();

  /// Decodes a status code from Rust into a [FfiResultUnit].
  ///
  /// If [code] is 0 (Success), returns [OkUnit].
  /// Otherwise, returns an [ErrUnit] with the message read from the arena's [errorBuf].
  static FfiResultUnit decode(int code, Pointer<Uint8> errorBuf, int errorCap) {
    // ignore: avoid-referencing-subclasses, sealed class factory pattern
    if (code == 0) return const OkUnit();

    final errorCode = mapFfiErrorCode(code);
    // When an error occurred, the arena's error buffer contains the null-terminated
    // error message.

    // ignore: avoid-referencing-subclasses, sealed class factory pattern
    return ErrUnit(errorCode, decodeFfiMessageFromBuffer(errorBuf, errorCap));
  }
}

final class OkUnit extends FfiResultUnit {
  const OkUnit();
}

final class ErrUnit extends FfiResultUnit {
  const ErrUnit(this.code, this.message);
  final FfiErrorCode code;
  final String message;
}
