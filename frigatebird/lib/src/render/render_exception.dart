// ignore_for_file: prefer-single-declaration-per-file, avoid-referencing-subclasses
// The sealed hierarchy lives in one file so switch-dispatch stays exhaustive and every variant
// is discoverable at a glance. `RenderException.fromCode` necessarily names every concrete
// subtype — that's the whole point of the factory — so the avoid-referencing-subclasses rule
// is suppressed at the file level.

/// Thrown by `RenderImage.run` when the Rust FFI call returns a non-zero error code.
///
/// Sealed — switch over instances to branch on the specific failure. The numeric [code] mirrors
/// `RenderError` discriminants in the Rust crate; callers that don't care about the specific kind
/// can still inspect it.
sealed class RenderException implements Exception {
  const RenderException(this.code, {required this.message, required this.name});

  /// Wire-level error code returned by the Rust FFI call.
  final int code;

  /// Stable subclass name. Stored explicitly (not via `runtimeType`) so [toString] stays
  /// readable in release/obfuscated builds where `runtimeType.toString()` may be minified.
  final String name;

  /// Short human-readable description used by [toString].
  final String message;

  /// Picks the right [RenderException] subtype for a wire `code`. Unknown codes fall back to
  /// [UnknownRenderException] so a newer Rust binary that returns an unrecognized error still
  /// surfaces usefully (without requiring a matching Dart library update).
  static RenderException fromCode(int code) => switch (code) {
    1 => const ImageDecodeException(),
    2 => const FontReadException(),
    3 => const FontParseException(),
    4 => const TextNotUtf8Exception(),
    5 => const PathNotUtf8Exception(),
    6 => const ImageWriteException(),
    7 => const NullPointerException(),
    8 => const MissingFontException(),
    99 => const RustPanicException(),
    _ => UnknownRenderException(code),
  };

  @override
  String toString() => '$name(code: $code, $message)';
}

/// The source image couldn't be read or decoded.
final class ImageDecodeException extends RenderException {
  const ImageDecodeException()
    : super(1, message: 'image decode failed', name: 'ImageDecodeException');
}

/// The font file couldn't be read from disk.
final class FontReadException extends RenderException {
  const FontReadException() : super(2, message: 'font read failed', name: 'FontReadException');
}

/// Font bytes read from disk but couldn't be parsed as a usable font.
final class FontParseException extends RenderException {
  const FontParseException() : super(3, message: 'font parse failed', name: 'FontParseException');
}

/// The annotation text was not valid UTF-8 when Rust interpreted it.
final class TextNotUtf8Exception extends RenderException {
  const TextNotUtf8Exception()
    : super(4, message: 'text not valid UTF-8', name: 'TextNotUtf8Exception');
}

/// One of the file paths was not valid UTF-8.
final class PathNotUtf8Exception extends RenderException {
  const PathNotUtf8Exception()
    : super(5, message: 'path not valid UTF-8', name: 'PathNotUtf8Exception');
}

/// Encoding / writing the output image to disk failed (includes unsupported extensions).
final class ImageWriteException extends RenderException {
  const ImageWriteException()
    : super(6, message: 'image write failed', name: 'ImageWriteException');
}

/// A required pointer (path, text, or params) was null when Rust dereferenced it.
final class NullPointerException extends RenderException {
  const NullPointerException()
    : super(7, message: 'null pointer argument', name: 'NullPointerException');
}

/// A `TextElement` was included in the list but no `fontPath` was supplied.
final class MissingFontException extends RenderException {
  const MissingFontException()
    : super(8, message: 'text element present without font', name: 'MissingFontException');
}

/// Rust panicked inside `catch_unwind`. Indicates a bug in native code.
final class RustPanicException extends RenderException {
  const RustPanicException() : super(99, message: 'Rust panic', name: 'RustPanicException');
}

/// Fallback for codes this Dart build doesn't recognize (e.g. a newer Rust binary added a new
/// discriminant).
final class UnknownRenderException extends RenderException {
  const UnknownRenderException(super.code)
    : super(message: 'unknown error', name: 'UnknownRenderException');
}
