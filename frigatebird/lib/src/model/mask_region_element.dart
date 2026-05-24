part of 'draw_element.dart';

@pragma('vm:deeply-immutable')
final class MaskRegionElement extends RectElement {
  const MaskRegionElement({
    required super.height,
    required super.width,
    required super.x,
    required super.y,
    super.blur = 10,
    super.rotation,
  }) : super(fillColor: .transparent, outlineColor: .transparent, outlineThickness: 0);

  @override
  MaskRegionElement copyWith({
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
    height: height ?? this.height,
    rotation: rotation ?? this.rotation,
    width: width ?? this.width,
    x: x ?? this.x,
    y: y ?? this.y,
  );

  @override
  String toString() =>
      'MaskRegionElement(x: $x, y: $y, width: $width, height: $height, blur: $blur, rotation: $rotation)';
}
