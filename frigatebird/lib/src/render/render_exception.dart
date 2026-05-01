import '../ffi/ffi_error.dart';

/// Thrown by `RenderImage.run` for every non-zero error code returned by Rust.
///
/// [code] carries the structured [FfiErrorCode] discriminant; [message] is the UTF-8 string
/// written by Rust into the arena error buffer (empty when Rust provides no detail).
///
/// Use [code] in a switch to branch on the specific failure kind, or catch [RenderException] as
/// a base type when the exact kind does not matter.
final class RenderException implements Exception {
  const RenderException(this.code, [this.message = '']);

  /// Structured error code from Rust.
  final FfiErrorCode code;

  /// Short UTF-8 description written by Rust into the arena, or an empty string.
  final String message;

  @override
  String toString() {
    // Empty string is the correct sentinel for "no detail from Rust".
    // ignore: no-empty-string
    final detail = message.isEmpty ? '' : ': $message';

    return 'RenderException(${code.description}$detail)';
  }
}
