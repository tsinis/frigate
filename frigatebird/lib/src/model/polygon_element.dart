part of 'draw_element.dart';

// No @pragma('vm:deeply-immutable') — Float64x2List is not a deeply-immutable type.
// PolygonElement extends DrawElement directly, bypassing ImmutableDrawElement.
final class PolygonElement extends DrawElement {
  PolygonElement({
    required super.height,
    required this.vertices,
    required super.width,
    required super.x,
    required super.y,
    super.blur,
    super.fillColor,
    super.outlineColor,
    super.outlineThickness,
    super.rotation,
  }) : assert(vertices.length >= 3, 'PolygonElement requires at least 3 vertices');

  /// Vertex coordinates as a flat [x0, y0, x1, y1, ...] buffer.
  /// Uses [Float64x2List] for SIMD-aligned storage and near-zero-cost FFI copy.
  /// Each [Float64x2] holds one vertex: lane 0 = x, lane 1 = y.
  ///
  /// Not deeply immutable — [Float64x2List] is a mutable typed-data buffer.
  /// [PolygonElement] therefore extends [DrawElement] directly, not [ImmutableDrawElement].
  final Float64x2List vertices;

  /// Derives the axis-aligned bounding box from a [Float64x2List] vertex buffer.
  static ({double height, double width, double x, double y}) boundingBoxOf(Float64x2List vertices) {
    final first = vertices.firstOrNull;
    if (first == null) return (height: 0, width: 0, x: 0, y: 0);

    double minX = first.x;
    double maxX = first.x;
    double minY = first.y;
    double maxY = first.y;

    for (final v in vertices.skip(1)) {
      if (v.x < minX) minX = v.x;
      if (v.x > maxX) maxX = v.x;
      if (v.y < minY) minY = v.y;
      if (v.y > maxY) maxY = v.y;
    }

    return (
      height: (maxY - minY).clamp(1.0, double.infinity),
      width: (maxX - minX).clamp(1.0, double.infinity),
      x: minX,
      y: minY,
    );
  }

  @override
  PolygonElement copyWith({
    int? blur,
    FfiColor? fillColor,
    double? height,
    FfiColor? outlineColor,
    int? outlineThickness,
    int? rotation,
    Float64x2List? vertices,
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
    vertices: vertices ?? this.vertices,
    width: width ?? this.width,
    x: x ?? this.x,
    y: y ?? this.y,
  );

  @override
  String toString() =>
      'PolygonElement(x: $x, y: $y, width: $width, height: $height, '
      'vertices: ${vertices.length}, fillColor: $fillColor, '
      'outlineColor: $outlineColor, outlineThickness: $outlineThickness, '
      'rotation: $rotation, blur: $blur)';
}
