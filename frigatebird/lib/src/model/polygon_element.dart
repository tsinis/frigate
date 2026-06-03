part of 'draw_element.dart';

// No @pragma('vm:deeply-immutable') — Float64x2List is not a deeply-immutable type.
// PolygonElement extends DrawElement directly, bypassing ImmutableDrawElement.
final class PolygonElement extends DrawElement {
  // Not const: Float64x2List is a mutable typed-data buffer that cannot be constructed as a const.
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

  static final zero = PolygonElement(
    fillColor: .transparent,
    height: 0,
    outlineColor: .transparent,
    outlineThickness: 0,
    vertices: Float64x2List.fromList([Float64x2.zero(), Float64x2.zero(), Float64x2.zero()]),
    width: 0,
    x: 0,
    y: 0,
  );

  /// Derives the axis-aligned bounding box from a [Float64x2List] vertex buffer.
  static ({double height, double width, double x, double y}) boundingBoxOf(Float64x2List vertices) {
    final first = vertices.firstOrNull;
    if (first == null) return (height: 0, width: 0, x: 0, y: 0);

    double minX = first.x;
    double maxX = first.x;
    double minY = first.y;
    double maxY = first.y;

    for (int i = 1; i < vertices.length; i += 1) {
      final v = vertices[i];
      if (v.x < minX) minX = v.x;
      if (v.x > maxX) maxX = v.x;
      if (v.y < minY) minY = v.y;
      if (v.y > maxY) maxY = v.y;
    }

    return (height: maxY - minY, width: maxX - minX, x: minX, y: minY);
  }

  /// Creates a copy of this polygon with updated fields.
  ///
  /// If [vertices] is provided, the bounding box is recomputed unless x/y/width/height
  /// are explicitly overridden.
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
  }) {
    final computed = vertices == null ? null : boundingBoxOf(vertices);

    return PolygonElement(
      blur: blur ?? this.blur,
      fillColor: fillColor ?? this.fillColor,
      height: height ?? (computed == null ? this.height : computed.height),
      outlineColor: outlineColor ?? this.outlineColor,
      outlineThickness: outlineThickness ?? this.outlineThickness,
      rotation: rotation ?? this.rotation,
      vertices: vertices ?? this.vertices,
      width: width ?? (computed == null ? this.width : computed.width),
      x: x ?? (computed == null ? this.x : computed.x),
      y: y ?? (computed == null ? this.y : computed.y),
    );
  }

  @override
  String toString() =>
      'PolygonElement(x: $x, y: $y, width: $width, height: $height, '
      'vertices: ${vertices.length}, fillColor: $fillColor, '
      'outlineColor: $outlineColor, outlineThickness: $outlineThickness, '
      'rotation: $rotation, blur: $blur)';

  @override
  bool operator ==(Object other) =>
      // ignore: avoid-complex-conditions, many fields to compare for value equality.
      identical(this, other) ||
      other is PolygonElement &&
          other.x == x &&
          other.y == y &&
          other.width == width &&
          other.height == height &&
          other.rotation == rotation &&
          other.blur == blur &&
          other.fillColor == fillColor &&
          other.outlineColor == outlineColor &&
          other.outlineThickness == outlineThickness &&
          _hasSameVertices(other.vertices, vertices);

  @override
  int get hashCode => Object.hash(
    x,
    y,
    width,
    height,
    rotation,
    blur,
    fillColor,
    outlineColor,
    outlineThickness,
    vertices.length,
  );

  static bool _hasSameVertices(Float64x2List a, Float64x2List b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final (i, vertex) in a.indexed) {
      // ignore: avoid-unsafe-collection-methods, bounds guaranteed by length check above.
      if (vertex.x != b[i].x || vertex.y != b[i].y) return false;
    }

    return true;
  }
}
