import 'dart:math' show atan2, cos, pi, sin;
import 'dart:typed_data' show Float64x2, Float64x2List;

import 'draw_element.dart';
import 'draw_element_resize_extension.dart';
import 'handle_position.dart';

/// A 2D point in document space, returned by the rotation helpers so callers
/// (`frigatedraw`) can wrap it into an `Offset` without this package touching
/// `dart:ui`.
typedef DrawPoint = ({double x, double y});

/// Pure-Dart rotation geometry for [DrawElement]s — no Flutter, no `dart:ui`.
///
/// Rotation is stored as **int degrees** in [DrawElement.rotation]; positive
/// degrees rotate **clockwise** on screen (the y-down convention shared with
/// the Rust renderer). The pivot is always the center of the un-rotated
/// axis-aligned bounding box, `(x + width / 2, y + height / 2)`, matching
/// `tiny_skia`'s `pre_rotate` about the same center on the backend.
///
/// Everything here is expressed with `double`/[DrawPoint] so it is unit-testable
/// without a Flutter SDK; `frigatedraw` wraps the results into `Offset`/`Path`.
extension DrawElementRotationExtension on DrawElement {
  /// [rotation] (degrees) expressed in radians.
  double get rotationRadians => rotation * (pi / 180);

  /// X of the rotation pivot (un-rotated bounding-box center).
  double get centerX => x + width / 2;

  /// Y of the rotation pivot (un-rotated bounding-box center).
  double get centerY => y + height / 2;

  /// Rotates [point] about the element center by [rotation] (clockwise for
  /// positive degrees). This maps an un-rotated point to where it appears once
  /// the element is rendered with `canvas.rotate(rotationRadians)`.
  DrawPoint rotatePoint(DrawPoint point) {
    final rad = rotationRadians;
    if (rad == 0) return point;
    final cosR = cos(rad);
    final sinR = sin(rad);
    final dx = point.x - centerX;
    final dy = point.y - centerY;

    return (x: centerX + dx * cosR - dy * sinR, y: centerY + dx * sinR + dy * cosR);
  }

  /// Inverse of [rotatePoint]: maps a screen-space [point] back into the
  /// element's un-rotated local frame, so axis-aligned tests can be reused.
  DrawPoint inverseRotatePoint(DrawPoint point) {
    final rad = rotationRadians;
    if (rad == 0) return point;
    final cosR = cos(rad);
    final sinR = sin(rad);
    final dx = point.x - centerX;
    final dy = point.y - centerY;

    return (x: centerX + dx * cosR + dy * sinR, y: centerY - dx * sinR + dy * cosR);
  }

  /// Rotation-aware center of [handle], following the element as it rotates.
  DrawPoint handleCenterFor(HandlePosition handle) => rotatePoint(_axisAlignedHandle(handle));

  /// Returns the [HandlePosition] within [radius] of [point], or `null`.
  ///
  /// The point is mapped into the local frame once, then compared against the
  /// un-rotated handle centers — cheaper than rotating eight handles.
  HandlePosition? handleHitTest(DrawPoint point, double radius) {
    if (width <= 0 || height <= 0) return null;
    final (x: posX, y: posY) = inverseRotatePoint(point);

    for (final handle in HandlePosition.values) {
      final (x: keyX, y: keyY) = _axisAlignedHandle(handle);
      final dx = posX - keyX;
      final dy = posY - keyY;
      if (dx * dx + dy * dy <= radius * radius) return handle;
    }

    return null;
  }

  /// Center of the rotation knob, [knobDistance] above top-center in local
  /// space, then rotated with the element.
  DrawPoint rotationKnobCenter(double knobDistance) =>
      rotatePoint((x: x + width / 2, y: y - knobDistance));

  /// Whether [point] is within [knobRadius] of the rotation knob placed
  /// [knobDistance] above the shape.
  bool isPointOnKnob(double knobDistance, double knobRadius, DrawPoint point) {
    if (width <= 0 || height <= 0) return false;
    final (x: knobX, y: knobY) = rotationKnobCenter(knobDistance);
    final dx = point.x - knobX;
    final dy = point.y - knobY;

    return dx * dx + dy * dy <= knobRadius * knobRadius;
  }

  /// Whether [point] lies on the (possibly rotated) shape, with [slop] of extra
  /// hit tolerance added to the outline. Rotation-aware: the point is
  /// inverse-rotated, then tested against the un-rotated geometry.
  bool isPointInside(DrawPoint point, {double slop = 0}) {
    if (width <= 0 || height <= 0) return false;
    final (x: posX, y: posY) = inverseRotatePoint(point);
    final half = outlineThickness / 2 + slop;
    final isOutside =
        posX < x - half || posX > x + width + half || posY < y - half || posY > y + height + half;

    final self = this;
    final isInShape = switch (self) {
      OvalElement() => _isInEllipse(posX, posY, slop),
      PolygonElement() => _RotationMath.isInPolygon(posX, posY, self.vertices),
      RectElement() || TextElement() || MaskRegionElement() => true,
    };

    return !isOutside && isInShape;
  }

  /// Applies a similarity transform (rotate + uniform scale + translate) about
  /// [pivot], so the element tracks a two-finger gesture anchored to the
  /// gesture focal point. [rotationDeltaRad] is added to [rotation],
  /// [scaleFactor] scales the size, and [translation] shifts the focal point.
  DrawElement transformedBy(
    DrawPoint pivot,
    double rotationDeltaRad, {
    double minSize = 10.0,
    double scaleFactor = 1,
    DrawPoint translation = (x: 0, y: 0),
  }) {
    final clampedScale = _clampScaleToMinSize(minSize, scaleFactor);
    final cosD = cos(rotationDeltaRad);
    final sinD = sin(rotationDeltaRad);
    final dx = centerX - pivot.x;
    final dy = centerY - pivot.y;
    final newCenter = (
      x: pivot.x + (dx * cosD - dy * sinD) * clampedScale + translation.x,
      y: pivot.y + (dx * sinD + dy * cosD) * clampedScale + translation.y,
    );
    final newRotation = _RotationMath.normalizeDegrees(
      rotation + (rotationDeltaRad * 180 / pi).round(),
    );

    final self = this;
    if (self is PolygonElement) {
      final scaled = _RotationMath.scaleVertices(
        clampedScale,
        self.vertices,
        newCenter: newCenter,
        oldCenter: (x: centerX, y: centerY),
      );

      return self.copyWith(rotation: newRotation, vertices: scaled);
    }

    final newWidth = width * clampedScale;
    final newHeight = height * clampedScale;

    return copyWith(
      height: newHeight,
      rotation: newRotation,
      width: newWidth,
      x: newCenter.x - newWidth / 2,
      y: newCenter.y - newHeight / 2,
    );
  }

  /// Rotation-aware resize: projects the screen-space drag `(dx, dy)` into the
  /// element's local axes, resizes there, and repositions so the corner
  /// opposite [handle] stays pinned in screen space. Collapses to the plain
  /// [DrawElementResizeExtension.resized] behavior when [rotation] is zero.
  DrawElement rotatedResized({
    required double dx,
    required double dy,
    required HandlePosition handle,
    double minSize = 10.0,
  }) {
    final rad = rotationRadians;
    if (rad == 0) return resized(dx: dx, dy: dy, handle: handle, minSize: minSize);

    final cosR = cos(rad);
    final sinR = sin(rad);
    final sized = resized(
      dx: dx * cosR + dy * sinR,
      dy: -dx * sinR + dy * cosR,
      handle: handle,
      minSize: minSize,
    );
    final DrawElement(height: newHeight, width: newWidth, x: boxX, y: boxY) = sized;
    final (x: ctrX, y: ctrY) = _pinnedCenter(cosR, handle, newHeight, newWidth, sinR);
    final newX = ctrX - newWidth / 2;
    final newY = ctrY - newHeight / 2;

    if (sized is PolygonElement) {
      final shifted = _RotationMath.shiftVertices(newX - boxX, newY - boxY, sized.vertices);

      return sized.copyWith(vertices: shifted);
    }

    return sized.copyWith(x: newX, y: newY);
  }

  /// Angle in degrees (0..359) from the element center to [point], offset so
  /// that a point directly above the center reads as 0° — the value the desktop
  /// rotation knob writes back to [rotation].
  int angleToPoint(DrawPoint point) => _RotationMath.normalizeDegrees(
    (atan2(point.y - centerY, point.x - centerX) * 180 / pi).round() + 90,
  );

  DrawPoint _axisAlignedHandle(HandlePosition handle) => switch (handle) {
    .topLeft => (x: x, y: y),
    .topCenter => (x: x + width / 2, y: y),
    .topRight => (x: x + width, y: y),
    .centerLeft => (x: x, y: y + height / 2),
    .centerRight => (x: x + width, y: y + height / 2),
    .bottomLeft => (x: x, y: y + height),
    .bottomCenter => (x: x + width / 2, y: y + height),
    .bottomRight => (x: x + width, y: y + height),
  };

  /// Raises [scaleFactor] to the smallest value that keeps both the width and
  /// the height at or above [minSize], so a two-finger pinch can't collapse the
  /// shape. Zero-size dimensions impose no lower bound.
  double _clampScaleToMinSize(double minSize, double scaleFactor) {
    final widthLimit = width > 0 ? minSize / width : 0.0;
    final heightLimit = height > 0 ? minSize / height : 0.0;
    final limit = widthLimit > heightLimit ? widthLimit : heightLimit;

    return scaleFactor > limit ? scaleFactor : limit;
  }

  bool _isInEllipse(double posX, double posY, double slop) {
    final axisA = width / 2 + outlineThickness / 2 + slop;
    final axisB = height / 2 + outlineThickness / 2 + slop;
    if (axisA <= 0 || axisB <= 0) return false;
    final diffX = posX - centerX;
    final diffY = posY - centerY;

    return (diffX * diffX) / (axisA * axisA) + (diffY * diffY) / (axisB * axisB) <= 1.0;
  }

  DrawPoint _pinnedCenter(
    double cosR,
    HandlePosition handle,
    double newHeight,
    double newWidth,
    double sinR,
  ) {
    final old = _RotationMath.anchorOffset(height, width, handle);
    final anchor = (
      x: centerX + (old.x * cosR - old.y * sinR),
      y: centerY + (old.x * sinR + old.y * cosR),
    );
    final fresh = _RotationMath.anchorOffset(newHeight, newWidth, handle);

    return (
      x: anchor.x - (fresh.x * cosR - fresh.y * sinR),
      y: anchor.y - (fresh.x * sinR + fresh.y * cosR),
    );
  }
}

/// Stateless rotation math shared by [DrawElementRotationExtension] but
/// independent of any element instance.
sealed class _RotationMath {
  /// Offset of the corner opposite [handle] from the box center, for a box of
  /// the given [boxWidth] and [boxHeight].
  static DrawPoint anchorOffset(double boxHeight, double boxWidth, HandlePosition handle) =>
      switch (handle) {
        .topLeft => (x: boxWidth / 2, y: boxHeight / 2),
        .topRight => (x: -boxWidth / 2, y: boxHeight / 2),
        .bottomLeft => (x: boxWidth / 2, y: -boxHeight / 2),
        .bottomRight => (x: -boxWidth / 2, y: -boxHeight / 2),
        .topCenter => (x: 0, y: boxHeight / 2),
        .bottomCenter => (x: 0, y: -boxHeight / 2),
        .centerLeft => (x: boxWidth / 2, y: 0),
        .centerRight => (x: -boxWidth / 2, y: 0),
      };

  /// Even-odd ray-cast point-in-polygon over a [Float64x2List] vertex buffer.
  static bool isInPolygon(double posX, double posY, Float64x2List vertices) {
    final count = vertices.length;
    if (count < 3) return false;

    bool isInside = false;
    int previous = count - 1;
    for (int current = 0; current < count; current += 1) {
      // ignore: avoid-unsafe-collection-methods, indices are bounded by count.
      final tip = vertices[current];
      // ignore: avoid-unsafe-collection-methods, indices are bounded by count.
      final tail = vertices[previous];
      final isCrossing =
          (tip.y > posY) != (tail.y > posY) &&
          posX < (tail.x - tip.x) * (posY - tip.y) / (tail.y - tip.y) + tip.x;
      if (isCrossing) isInside = !isInside;
      previous = current;
    }

    return isInside;
  }

  /// Scales [source] about [oldCenter] by [scale] and re-centers on [newCenter].
  static Float64x2List scaleVertices(
    double scale,
    Float64x2List source, {
    required DrawPoint newCenter,
    required DrawPoint oldCenter,
  }) {
    final result = Float64x2List(source.length);
    for (final (index, vertex) in source.indexed) {
      result[index] = Float64x2(
        newCenter.x + (vertex.x - oldCenter.x) * scale,
        newCenter.y + (vertex.y - oldCenter.y) * scale,
      );
    }

    return result;
  }

  /// Translates every vertex of [source] by `(dx, dy)`.
  static Float64x2List shiftVertices(double dx, double dy, Float64x2List source) {
    final result = Float64x2List(source.length);
    for (final (index, vertex) in source.indexed) {
      result[index] = Float64x2(vertex.x + dx, vertex.y + dy);
    }

    return result;
  }

  /// Wraps [degrees] into the `0..359` range.
  static int normalizeDegrees(int degrees) => ((degrees % 360) + 360) % 360;
}
