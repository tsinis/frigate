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
    // is the opposite: fill color IS the text color, so the base default of opaque-black fits.
    super.fillColor = FfiColor.transparent,
    // Black outline by default — a rectangle is useless without a visible outline.
    super.outlineColor = FfiColor.black,
    super.outlineThickness = 2,
    super.rotation,
    int cornerRadius = 0,
  }) : assert(
         cornerRadius >= 0,
         'cornerRadius must be non-negative; negative values silently wrap to a huge u32 on '
         'the FFI wire (Dart Uint32 marshaling) and Rust would render them as a pill while '
         'the Flutter preview would draw sharp corners — preview-vs-export divergence.',
       ),
       super(shapeParam: cornerRadius);

  /// Corner radius in pixels. Sharp corners when 0; clamped to `min(width, height) / 2` at
  /// render time on both the preview and the Rust export.
  // ignore: match-getter-setter-field-names, typed alias over the internal shape-param slot.
  int get cornerRadius => shapeParam;

  @override
  FfiElementType get elementType => .rectangle;

  @override
  String toString() =>
      'RectElement(x: $x, y: $y, width: $width, height: $height, fillColor: $fillColor, '
      'outlineColor: $outlineColor, outlineThickness: $outlineThickness, '
      'rotation: $rotation, blur: $blur, cornerRadius: $cornerRadius)';

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
}
