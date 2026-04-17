part of 'draw_element.dart';

@pragma('vm:deeply-immutable')
final class RectElement extends DrawElement {
  const RectElement({
    required super.height,
    required super.width,
    required super.x,
    required super.y,
    super.blur,
    // Transparent fill by default — a rectangle overlay should show the image through it. Text
    // is the opposite: fill colour IS the text colour, so the base default of opaque-black fits.
    super.fillColor = FfiColor.transparent,
    // Black outline by default — a rectangle is useless without a visible outline.
    super.outlineColor = FfiColor.black,
    super.outlineThickness = 2,
    super.rotation,
  });

  @override
  FfiElementType get elementType => .rectangle;

  @override
  String toString() =>
      'RectElement(x: $x, y: $y, width: $width, height: $height, fillColor: $fillColor, '
      'outlineColor: $outlineColor, outlineThickness: $outlineThickness, '
      'rotation: $rotation, blur: $blur)';

  @override
  RectElement copyWith({
    int? blur,
    FfiColor? fillColor,
    double? height,
    FfiColor? outlineColor,
    int? outlineThickness,
    int? rotation,
    double? width,
    double? x,
    double? y,
  }) => .new(
    blur: blur ?? this.blur,
    fillColor: fillColor ?? this.fillColor,
    height: height ?? this.height,
    outlineColor: outlineColor ?? this.outlineColor,
    outlineThickness: outlineThickness ?? this.outlineThickness,
    rotation: rotation ?? this.rotation,
    width: width ?? this.width,
    x: x ?? this.x,
    y: y ?? this.y,
  );
}
