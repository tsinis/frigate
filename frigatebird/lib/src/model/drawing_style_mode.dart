import 'ffi_color.dart';

/// Base for all drawing style presets in document-space.
@pragma('vm:deeply-immutable')
sealed class DrawingStyleMode {
  const DrawingStyleMode({this.outlineColor = FfiColor.transparent, this.outlineThickness = 0});

  final FfiColor outlineColor;
  final int outlineThickness;
}

/// A solid color fill preset.
@pragma('vm:deeply-immutable')
final class ColorStyle extends DrawingStyleMode {
  const ColorStyle({
    this.color = FfiColor.black,
    super.outlineColor = FfiColor.transparent,
    super.outlineThickness = 0,
  });

  final FfiColor color;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorStyle &&
          runtimeType == other.runtimeType &&
          color == other.color &&
          outlineColor == other.outlineColor &&
          outlineThickness == other.outlineThickness;

  @override
  int get hashCode => Object.hash(color, outlineColor, outlineThickness);
}

/// A Gaussian region blur preset.
@pragma('vm:deeply-immutable')
final class BlurStyle extends DrawingStyleMode {
  const BlurStyle({
    this.blur = 10,
    super.outlineColor = FfiColor.transparent,
    super.outlineThickness = 0,
  });

  final int blur;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlurStyle &&
          runtimeType == other.runtimeType &&
          blur == other.blur &&
          outlineColor == other.outlineColor &&
          outlineThickness == other.outlineThickness;

  @override
  int get hashCode => Object.hash(blur, outlineColor, outlineThickness);
}
