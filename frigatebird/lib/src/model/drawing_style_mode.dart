import 'ffi_color.dart';

/// Base for all drawing style presets in document-space.
@pragma('vm:deeply-immutable')
sealed class DrawingStyleMode {
  const DrawingStyleMode();
}

/// A solid color fill preset.
@pragma('vm:deeply-immutable')
final class ColorStyle extends DrawingStyleMode {
  const ColorStyle({
    this.color = FfiColor.black,
    this.outlineColor = FfiColor.transparent,
    this.outlineThickness = 0,
  });

  final FfiColor color;
  final FfiColor outlineColor;
  final int outlineThickness;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorStyle &&
          color == other.color &&
          outlineColor == other.outlineColor &&
          outlineThickness == other.outlineThickness;

  @override
  int get hashCode => Object.hash(color, outlineColor, outlineThickness);
}

/// A Gaussian region blur preset.
@pragma('vm:deeply-immutable')
final class BlurStyle extends DrawingStyleMode {
  const BlurStyle({this.blur = 10});

  final int blur;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is BlurStyle && blur == other.blur;

  @override
  int get hashCode => blur.hashCode;
}
