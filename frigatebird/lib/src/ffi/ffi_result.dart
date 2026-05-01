// Padding fields are required FFI layout artefacts, not unused dead code.
// All four Result/payload classes live here — they're a single wire-protocol surface.
// `Ok` is 2 chars but it's the canonical Rust-style result name; splitting or renaming
// would obscure intent.
// `fromRaw` uses `as T` which is unavoidable in a generic factory that narrows T? to T.
// ignore_for_file: unused_field, prefer-single-declaration-per-file, member-ordering, prefer-correct-type-name, avoid-type-casts

import 'dart:convert' show utf8;
import 'dart:ffi';

import 'ffi_error.dart';

/// Dart-side representation of a Rust `Result<T, FfiError>`.
sealed class FfiResult<T> {
  const FfiResult();

  // Factory body is required to conditionally construct Ok/Err; logic cannot be extracted.
  // ignore: avoid-non-empty-constructor-bodies
  factory FfiResult.fromRaw(FfiErrorCode code, String message, T? value) {
    if (code != .success) return Err(code, message);

    return Ok(value as T);
  }
}

final class Ok<T> extends FfiResult<T> {
  const Ok(this.value);

  final T value;
}

final class Err<T> extends FfiResult<T> {
  const Err(this.code, this.message);

  final FfiErrorCode code;
  final String message;
}

/// FFI payload for a result that returns nothing (`void`).
/// The Ok variant carries `()` (zero bytes in Rust), so only the error arm is needed here.
/// When `tag == 0` the union is not read; when `tag == 1` `err` is valid.
final class FfiResultUnitPayload extends Union {
  external FfiError err;
}

/// Raw FFI struct for a `Result<void, FfiError>`.
///
/// Layout: `tag(u8=1) + _pad(u8=1) + FfiResultUnitPayload(FfiError=4) = 6 bytes`.
/// The single padding byte aligns `payload` to [FfiError]'s 2-byte alignment.
final class FfiResultUnit extends Struct {
  @Uint8()
  external int tag;

  @Array(1)
  external Array<Uint8> _pad;

  external FfiResultUnitPayload payload;

  FfiResult<void> toDomain(Pointer<Uint8> errorBuf, int errorCap) {
    if (tag == 0) return const Ok(null);
    final error = payload.err;
    final message = _decodeMessage(error, errorBuf, errorCap);

    return Err(FfiErrorCode.fromCode(error.code), message);
  }
}

/// FFI payload for a result that returns a u32.
final class FfiResultCountPayload extends Union {
  /// `@Uint32()` — the success value is a `u32` element count on the Rust side.
  @Uint32()
  external int count;
  external FfiError err;
}

/// Raw FFI struct for a `Result<u32, FfiError>`.
final class FfiResultCount extends Struct {
  @Uint8()
  external int tag;

  @Array(3)
  external Array<Uint8> _pad;

  external FfiResultCountPayload payload;

  FfiResult<int> toDomain(Pointer<Uint8> errorBuf, int errorCap) {
    if (tag == 0) return Ok(payload.count);
    final error = payload.err;
    final message = _decodeMessage(error, errorBuf, errorCap);

    return Err(FfiErrorCode.fromCode(error.code), message);
  }
}

String _decodeMessage(FfiError error, Pointer<Uint8> errorBuf, int errorCap) {
  // Empty string is the correct sentinel for "no message from Rust".
  // ignore: no-empty-string
  if (error.messageLen == 0 || errorBuf == nullptr) return '';
  final len = error.messageLen.clamp(0, errorCap);
  final bytes = errorBuf.asTypedList(len);

  return utf8.decode(bytes);
}
