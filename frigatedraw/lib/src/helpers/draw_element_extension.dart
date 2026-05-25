import 'dart:ui' show Color, Offset, Path, Rect;

import 'package:frigatebird/frigatebird.dart';

import '../ui/draw_tool.dart';

extension DrawElementExtension on DrawElement {
  static const handleRadius = 6.0;
  static const _hitSlop = 4.0;
  static final _polygonPathCache = Expando<Path>();

  static Path getPathForPolygon(PolygonElement element) {
    final cached = _polygonPathCache[element.vertices];
    if (cached == null) {
      final path = Path();
      final first = element.vertices.firstOrNull;
      if (first == null) return path;

      path.moveTo(first.x, first.y);
      for (int index = 1; index < element.vertices.length; index += 1) {
        path.lineTo(element.vertices[index].x, element.vertices[index].y);
      }
      path.close();
      // Expando operates as a lookup map, not an in-place collection mutation.
      // ignore: avoid-collection-mutating-methods,
      _polygonPathCache[element.vertices] = path;

      return path;
    }

    return cached;
  }

  /// Converts to `dart:ui` [Rect] for rendering only.
  @pragma('dart2js:tryInline')
  @pragma('vm:prefer-inline')
  Rect get rect => .fromLTWH(x, y, width, height);

  /// Converts fill color to `dart:ui` [Color] for rendering only.
  @pragma('dart2js:tryInline')
  @pragma('vm:prefer-inline')
  Color get uiFillColor => .new(fillColor.argb);

  /// Converts outline color to `dart:ui` [Color] for rendering only.
  @pragma('dart2js:tryInline')
  @pragma('vm:prefer-inline')
  Color get uiOutlineColor => .new(outlineColor.argb);

  @pragma('dart2js:tryInline')
  @pragma('vm:prefer-inline')
  DrawElement copyWithDrag({required Offset a, required Offset b}) {
    final Rect(:height, :left, :top, :width) = .fromPoints(a, b);

    return copyWith(height: height, width: width, x: left, y: top);
  }

  DrawTool get tool => switch (this) {
    TextElement() => .text,
    RectElement() => .rectangle,
    OvalElement() => .oval,
    PolygonElement() => .polygon,
    MaskRegionElement() => .rectangle,
  };

  Offset handleCenter(HandlePosition handle) {
    final Rect(
      :bottomCenter,
      :bottomLeft,
      :bottomRight,
      :centerLeft,
      :centerRight,
      :topCenter,
      :topLeft,
      :topRight,
    ) = rect;

    return switch (handle) {
      .topLeft => topLeft,
      .topCenter => topCenter,
      .topRight => topRight,
      .centerLeft => centerLeft,
      .centerRight => centerRight,
      .bottomLeft => bottomLeft,
      .bottomCenter => bottomCenter,
      .bottomRight => bottomRight,
    };
  }

  HandlePosition? hitTestHandle(Offset point) {
    if (width <= 0 || height <= 0) return null;

    final self = this;
    switch (self) {
      case TextElement():
        return null;

      case RectElement():
      case OvalElement():
      case PolygonElement():
      case MaskRegionElement():
        for (final handle in HandlePosition.values) {
          final center = handleCenter(handle);
          if ((point - center).distance <= handleRadius) return handle;
        }

        return null;
    }
  }

  bool isPointOnShape(Offset point) {
    if (width <= 0 || height <= 0) return false;

    final half = outlineThickness.toDouble() / 2 + _hitSlop;
    final outer = rect.inflate(half);

    if (!outer.contains(point)) return false;

    final self = this;

    return switch (self) {
      OvalElement() => _isPointInEllipse(outer, point),
      PolygonElement() => _isPointInPolygon(point, self),
      RectElement() || TextElement() || MaskRegionElement() => true,
    };
  }

  bool _isPointInPolygon(Offset point, PolygonElement poly) {
    if (poly.vertices.length < 3) return false;

    final path = getPathForPolygon(poly);

    return path.contains(point);
  }

  bool _isPointInEllipse(Rect outerRect, Offset point) {
    final axisA = outerRect.width / 2;
    final axisB = outerRect.height / 2;
    if (axisA <= 0 || axisB <= 0) return false;

    final diffX = point.dx - outerRect.center.dx;
    final diffY = point.dy - outerRect.center.dy;

    return (diffX * diffX) / (axisA * axisA) + (diffY * diffY) / (axisB * axisB) <= 1.0;
  }
}
