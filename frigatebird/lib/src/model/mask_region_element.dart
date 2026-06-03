part of 'draw_element.dart';

@pragma('vm:deeply-immutable')
final class MaskRegionElement extends ImmutableDrawElement {
  const MaskRegionElement({
    required super.height,
    required super.width,
    required super.x,
    required super.y,
    super.rotation,
    super.blur = DrawConstants.defaultBlurRadius,
    super.fillColor = .transparent,
  }) : super(outlineColor: .transparent, outlineThickness: 0);

  static const zero = MaskRegionElement(blur: 0, height: 0, width: 0, x: 0, y: 0);

  @override
  MaskRegionElement copyWith({
    int? blur,
    FfiColor? fillColor,
    double? height,
    FfiColor? outlineColor,
    int? outlineThickness,
    int? rotation,
    double? width,
    double? x,
    double? y,
  }) {
    assert(
      outlineColor == null || outlineColor == .transparent,
      'MaskRegionElement outlineColor must be transparent',
    );
    assert(
      outlineThickness == null || outlineThickness == 0,
      'MaskRegionElement outlineThickness must be 0',
    );

    return .new(
      blur: blur ?? this.blur,
      fillColor: fillColor ?? this.fillColor,
      height: height ?? this.height,
      rotation: rotation ?? this.rotation,
      width: width ?? this.width,
      x: x ?? this.x,
      y: y ?? this.y,
    );
  }

  @override
  bool operator ==(Object other) =>
      // ignore: avoid-complex-conditions, a lot of properties to compare.
      identical(this, other) ||
      other is MaskRegionElement &&
          other.x == x &&
          other.y == y &&
          other.width == width &&
          other.height == height &&
          other.rotation == rotation &&
          other.blur == blur &&
          other.fillColor == fillColor;

  @override
  int get hashCode => Object.hash(x, y, width, height, rotation, blur, fillColor);

  @override
  String toString() =>
      'MaskRegionElement(x: $x, y: $y, width: $width, height: $height, blur: $blur, '
      'rotation: $rotation, fillColor: $fillColor)';
}
