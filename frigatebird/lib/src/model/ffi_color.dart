/// ARGB color matching Flutter's `Color` convention.
///
/// Packed format: `0xAARRGGBB` (alpha in high byte, blue in low byte).
/// Passed to Rust as-is — Rust unpacks with bit shifts.
@pragma('vm:deeply-immutable')
final class FfiColor {
  /// Constructs from a packed `0xAARRGGBB` int. Asserts the value fits in `u32` (the wire
  /// type). Without this guard, a negative or oversized int would silently wrap or truncate
  /// during FFI marshaling and produce a garbage color downstream.
  const FfiColor(this.argb)
    : assert(
        argb >= 0 && argb <= 0xFFFFFFFF,
        'argb must fit in a u32 (0..=0xFFFFFFFF); the FFI wire slot is Uint32 and out-of-range '
        'values silently wrap or truncate.',
      );

  // ignore: parameters-ordering, it's more natural and intuitive for ARGB.
  const FfiColor.from({int alpha = 255, int red = 0, int green = 0, int blue = 0})
    : assert(alpha >= 0 && alpha <= 255, 'alpha must be in [0, 255]'),
      assert(red >= 0 && red <= 255, 'red must be in [0, 255]'),
      assert(green >= 0 && green <= 255, 'green must be in [0, 255]'),
      assert(blue >= 0 && blue <= 255, 'blue must be in [0, 255]'),
      argb = (alpha << 24) | (red << 16) | (green << 8) | blue;

  /// Fully opaque black (0xFF000000) — the conventional default fill color.
  static const black = FfiColor(0xFF000000);

  /// Fully transparent (0x00000000) — the conventional "no visible color" sentinel.
  static const transparent = FfiColor(0);

  final int argb;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is FfiColor && other.argb == argb;

  @override
  int get hashCode => argb.hashCode;

  @override
  String toString() => 'FfiColor(0x${argb.toRadixString(16).padLeft(8, '0').toUpperCase()})';
}
