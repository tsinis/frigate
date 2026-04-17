/// Public, centralized constants for draw/render operations.
///
/// Sealed (via `sealed`) with a private constructor so it cannot be instantiated or
/// subclassed — callers reference the static fields directly, tests import the same names.
sealed class DrawConstants {
  /// Minimum output-image quality accepted by `renderImage`. Values below are clamped up.
  ///
  /// "Quality" is format-specific: for JPEG it's the encoder's Q factor (0-100, visually lossy at
  /// the low end).
  static const minImageQuality = 0;

  /// Maximum output-image quality accepted by `renderImage`. Values above are clamped down.
  static const maxImageQuality = 100;

  /// Default output-image quality for `renderImage` when callers omit the argument.
  static const defaultImageQuality = 90;
}
