import 'dart:ui' show Color, Offset, Path, Rect;

import 'package:frigatebird/frigatebird.dart';

import '../ui/draw_tool.dart';

extension DrawElementExtension on DrawElement {
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

  /// Rotation-aware screen-space center of [handle]. Delegates the geometry to
  /// `frigatebird`'s [DrawElementRotationExtension.handleCenterFor] and wraps
  /// the result into an [Offset].
  Offset handleCenter(HandlePosition handle) {
    final center = handleCenterFor(handle);

    return Offset(center.x, center.y);
  }

  /// Screen-space center of the rotation knob, [knobDistance] above the shape.
  Offset rotationKnobOffset(double knobDistance) {
    final knob = rotationKnobCenter(knobDistance);

    return Offset(knob.x, knob.y);
  }

  HandlePosition? hitTestHandle(Offset point, [double customHandleRadius = 12]) =>
      handleHitTest((x: point.dx, y: point.dy), customHandleRadius);

  bool isPointOnRotationKnob(double knobDistance, double knobRadius, Offset point) =>
      isPointOnKnob(knobDistance, knobRadius, (x: point.dx, y: point.dy));

  bool isPointOnShape(Offset point) => isPointInside((x: point.dx, y: point.dy), slop: _hitSlop);
}
