import 'dart:ui' show Color;

/// ARGB color matching Flutter's [Color] convention.
///
/// Packed format: `0xAARRGGBB` (alpha in high byte, blue in low byte).
/// Passed to Rust as-is — Rust unpacks with bit shifts.
@pragma('vm:deeply-immutable')
final class FfiColor {
  const FfiColor(this.argb);

  // ignore: parameters-ordering, it's more natural and intuitive for ARGB.
  const FfiColor.fromARGB({int alpha = 255, int red = 0, int green = 0, int blue = 0})
    : argb = (alpha << 24) | (red << 16) | (green << 8) | blue;

  FfiColor.fromColor(Color color) : this(color.toARGB32());

  final int argb;

  int get alpha => (argb >> 24) & 0xFF;

  int get red => (argb >> 16) & 0xFF;

  int get green => (argb >> 8) & 0xFF;

  int get blue => argb & 0xFF;

  /// Converts to `dart:ui` [Color] for rendering only.
  Color toColor() => .new(argb);

  @override
  String toString({bool short = false}) => short
      ? toColor().toString()
      : 'FfiColor.fromARGB(alpha: $alpha, red: $red, green: $green, blue: $blue)';
}
