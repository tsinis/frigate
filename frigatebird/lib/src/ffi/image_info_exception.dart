import 'ffi_error.dart';

/// Thrown when an FFI call returns a non-zero status code.
@pragma('vm:deeply-immutable')
final class ImageInfoException implements Exception {
  const ImageInfoException({required this.codeWire, required this.message});

  /// Convenience constructor that accepts an enum.
  factory ImageInfoException.from({required FfiErrorCode code, required String message}) =>
      ImageInfoException(codeWire: code.index, message: message);

  final int codeWire;
  final String message;

  /// FFI error code as an enum.
  FfiErrorCode get code => FfiErrorCode.fromCode(codeWire);

  @override
  String toString() => 'ImageInfoException(code: $code, message: $message)';
}
