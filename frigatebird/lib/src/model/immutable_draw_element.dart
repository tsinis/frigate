part of 'draw_element.dart';

/// Subtypes of [DrawElement] whose fields are all deeply immutable scalars.
/// [RectElement], [OvalElement], and [TextElement] extend this.
/// [PolygonElement] does NOT — it holds a variable-length vertex collection.
@pragma('vm:deeply-immutable')
sealed class ImmutableDrawElement implements DrawElement {
  const ImmutableDrawElement({
    required this.height,
    required this.width,
    required this.x,
    required this.y,
    this.blur = 0,
    this.fillColor = FfiColor.black,
    this.outlineColor = FfiColor.black,
    this.outlineThickness = 2,
    this.rotation = 0,
  }) : assert(blur >= 0 && blur <= 255, 'blur must be in 0..255'),
       assert(
         outlineThickness >= 0 && outlineThickness <= 255,
         'outlineThickness must be in 0..255',
       );

  @override
  final double x;
  @override
  final double y;
  @override
  final double width;
  @override
  final double height;
  @override
  final int blur;
  @override
  final int rotation;
  @override
  final FfiColor fillColor;
  @override
  final FfiColor outlineColor;
  @override
  final int outlineThickness;
}
