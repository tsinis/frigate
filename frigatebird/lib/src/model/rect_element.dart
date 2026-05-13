part of 'draw_element.dart';

@pragma('vm:deeply-immutable')
final class RectElement extends DrawElement {
  const RectElement({
    required super.height,
    required super.width,
    required super.x,
    required super.y,
    super.blur,
    super.rotation,
    super.fillColor,
    super.outlineColor,
    super.outlineThickness,
    this.cornerRadius = 0,
  }) : assert(cornerRadius >= 0 && cornerRadius <= 65535, 'cornerRadius must be in 0..65535');

  final int cornerRadius;

  @override
  RectElement copyWith({
    int? blur,
    int? cornerRadius,
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
    cornerRadius: cornerRadius ?? this.cornerRadius,
    fillColor: fillColor ?? this.fillColor,
    height: height ?? this.height,
    outlineColor: outlineColor ?? this.outlineColor,
    outlineThickness: outlineThickness ?? this.outlineThickness,
    rotation: rotation ?? this.rotation,
    width: width ?? this.width,
    x: x ?? this.x,
    y: y ?? this.y,
  );

  @override
  String toString() =>
      'RectElement(x: $x, y: $y, width: $width, height: $height, fillColor: $fillColor, '
      'outlineColor: $outlineColor, outlineThickness: $outlineThickness, '
      'rotation: $rotation, blur: $blur, cornerRadius: $cornerRadius)';
}
