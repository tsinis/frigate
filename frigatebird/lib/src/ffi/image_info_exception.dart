/// Thrown when an FFI call returns a non-zero status code.
@pragma('vm:deeply-immutable')
final class ImageInfoException implements Exception {
  const ImageInfoException({required this.code, required this.message});

  final int code;
  final String message;

  @override
  String toString() => 'ImageInfoException(code: $code, message: $message)';
}
