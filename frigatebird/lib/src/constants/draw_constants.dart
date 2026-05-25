/// Public, centralized constants for draw/render operations.
///
/// Sealed class that cannot be instantiated or subclassed — callers reference
/// the static fields directly, tests import the same names.
sealed class DrawConstants {
  /// Minimum output-image quality accepted by `RenderImage.run`. Values below are clamped up.
  ///
  /// "Quality" is format-specific: for JPEG it's the encoder's Q factor (0-100, visually lossy at
  /// the low end).
  static const minImageQuality = 0;

  /// Maximum output-image quality accepted by `RenderImage.run`. Values above are clamped down.
  static const maxImageQuality = 100;

  /// Default output-image quality for `RenderImage.run` when callers omit the argument.
  static const defaultImageQuality = 90;

  /// Default blur radius for blur area elements and regions.
  static const defaultBlurRadius = 10;
}
