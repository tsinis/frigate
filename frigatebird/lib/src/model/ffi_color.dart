/// ARGB color matching Flutter's `Color` convention.
///
/// Packed format: `0xAARRGGBB` (alpha in high byte, blue in low byte).
/// Passed to Rust as-is — Rust unpacks with bit shifts.
@pragma('vm:deeply-immutable')
final class FfiColor {
  const FfiColor(this.argb); // TODO(tsinis): assert values outside the 32-bit ARGB range.

  // ignore: parameters-ordering, it's more natural and intuitive for ARGB.
  const FfiColor.from({int alpha = 255, int red = 0, int green = 0, int blue = 0})
    // TODO(tsinis): add asserts for 0-255 range(s).
    : argb = (alpha << 24) | (red << 16) | (green << 8) | blue;

  /// Fully opaque black (0xFF000000) — the conventional default fill colour.
  static const black = FfiColor(0xFF000000);

  /// Fully transparent (0x00000000) — the conventional "no visible colour" sentinel.
  static const transparent = FfiColor(0);

  final int argb;

  @override
  String toString() => 'FfiColor(0x${argb.toRadixString(16).padLeft(8, '0').toUpperCase()})';
}
