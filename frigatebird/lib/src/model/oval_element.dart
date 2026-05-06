part of 'draw_element.dart';

@pragma('vm:deeply-immutable')
final class OvalElement extends DrawElement {
  const OvalElement({
    required super.height,
    required super.width,
    required super.x,
    required super.y,
    int blur = 0,
    super.rotation,
    super.fillColor = FfiColor.transparent,
    this.outlineColor = FfiColor.black,
    int outlineThickness = 2,
  }) : blur = blur < 0
           ? 0
           : blur > 255
           ? 255
           : blur,
       outlineThickness = outlineThickness < 0
           ? 0
           : outlineThickness > 255
           ? 255
           : outlineThickness,
       super(
         blur: blur < 0
             ? 0
             : blur > 255
             ? 255
             : blur,
       ),
       assert(
         outlineThickness >= 0 && outlineThickness <= 255,
         'outlineThickness must be in 0..255',
       ),
       assert(blur >= 0 && blur <= 255, 'blur must be in 0..255');

  final FfiColor outlineColor;
  final int outlineThickness;

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
