part of 'draw_element.dart';

@pragma('vm:deeply-immutable')
final class OvalElement extends DrawElement {
  const OvalElement({
    required super.height,
    required super.width,
    required super.x,
    required super.y,
    super.blur,
    super.rotation,
    super.fillColor,
    super.outlineColor,
    super.outlineThickness,
  });

  @override
  OvalElement copyWith({
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

  @override
  String toString() =>
      'OvalElement(x: $x, y: $y, width: $width, height: $height, fillColor: $fillColor, '
      'outlineColor: $outlineColor, outlineThickness: $outlineThickness, '
      'rotation: $rotation, blur: $blur)';
}
