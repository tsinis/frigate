import 'dart:ffi';

// [FfiErrorCode] and [FfiError] are a tightly coupled pair — [FfiError.code] carries a
// [FfiErrorCode] discriminant. Keeping them together avoids cross-file import noise.
// ignore_for_file: prefer-single-declaration-per-file

// Padding fields are required FFI layout artifacts, not unused dead code.
// _pad appears between code and messageLen because that's the wire layout — not Dart style.
// ignore_for_file: unused_field, member-ordering

// Wire order is dictated by the Rust discriminants (success=0, panic=1, …).
// Sorting alphabetically would change .index values and break every fromCode lookup.
// ignore_for_file: enum-constants-ordering

/// Error codes returned from Rust. Order **must** match `FfiErrorCode` in the Rust crate.
// TODO: Should be handled without enum needed in sealed class directly,
//  instead of being a separate enum. Aligns with main refactor - returning int.
enum FfiErrorCode {
  /// No error (Rust `Ok = 0`). Renamed from `ok` — minimum identifier length is 3 characters.
  success,
  panic,
  invalidArg,
  io,
  decode,
  encode,
  font,
  render,
  utf8,

  /// A wire code outside the known range — typically a version skew where a newer Rust binary
  /// emits a discriminant this Dart build doesn't recognize. Kept separate from [panic] so
  /// telemetry can distinguish a real Rust panic from a version-skew mismatch.
  unknown;

  /// Looks up a [FfiErrorCode] by its wire index.
  ///
  /// Returns [unknown] for any code outside the known range — a newer Rust binary returning an
  /// unrecognized discriminant surfaces as [unknown] rather than being misreported as [panic].
  static FfiErrorCode fromCode(int code) {
    // `unknown` is at index 9 and is NOT a wire code emitted by Rust; codes 0–8 map 1:1.
    const wireCount = 9;

    return !code.isNegative && code < wireCount ? values[code] : unknown;
  }

  /// Human-readable description used in exception messages.
  String get description => switch (this) {
    success => 'success',
    panic => 'Rust panic',
    invalidArg => 'invalid argument',
    io => 'I/O error',
    decode => 'image decode failed',
    encode => 'image write failed',
    font => 'font parse failed',
    render => 'render error',
    utf8 => 'invalid UTF-8',
    unknown => 'unrecognized error code',
  };
}

/// A structured error returned from Rust FFI. Matches `#[repr(C)] struct FfiError`.
///
/// Field types match the Rust wire representation:
/// - [code] is `u8` — only 9 discriminants; fits in one byte.
/// - [_pad] is explicit C alignment filler so [messageLen] lands on a 2-byte boundary.
/// - [messageLen] is `u16` — message lengths up to 65 535 bytes; arena cap is `FfiAbi.errorCapBytes`.
///
/// Total: 4 bytes, alignment: 2.
final class FfiError extends Struct {
  @Uint8()
  external int code;

  @Uint8()
  external int _pad;

  @Uint16()
  external int messageLen;
}
