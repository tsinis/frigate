part of 'draw_element.dart';

@pragma('vm:deeply-immutable')
final class OvalElement extends ImmutableDrawElement {
  const OvalElement({
    required super.height,
    required super.width,
    required super.x,
    required super.y,
    super.blur,
    super.rotation,
    super.fillColor = FfiColor.transparent,
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
  bool operator ==(Object other) =>
      // ignore: avoid-complex-conditions, many fields to compare for value equality.
      identical(this, other) ||
      other is OvalElement &&
          other.x == x &&
          other.y == y &&
          other.width == width &&
          other.height == height &&
          other.rotation == rotation &&
          other.blur == blur &&
          other.fillColor == fillColor &&
          other.outlineColor == outlineColor &&
          other.outlineThickness == outlineThickness;

  @override
  int get hashCode =>
      Object.hash(x, y, width, height, rotation, blur, fillColor, outlineColor, outlineThickness);

  @override
  String toString() =>
      'OvalElement(x: $x, y: $y, width: $width, height: $height, fillColor: $fillColor, '
      'outlineColor: $outlineColor, outlineThickness: $outlineThickness, '
      'rotation: $rotation, blur: $blur)';
}
