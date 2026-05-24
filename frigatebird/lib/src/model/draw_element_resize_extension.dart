// ignore_for_file: avoid-long-functions
import 'dart:math' show max;
import 'dart:typed_data' show Float64x2, Float64x2List;

import 'draw_element.dart';
import 'handle_position.dart';

/// Pure Dart extensions to move and resize [DrawElement] shapes.
extension DrawElementResizeExtension on DrawElement {
  /// Moves the shape by [dx] and [dy] offsets in document space.
  DrawElement moved(double dx, double dy) {
    final self = this;
    if (self is PolygonElement) {
      final newVerts = Float64x2List(self.vertices.length);
      for (int index = 0; index < self.vertices.length; index += 1) {
        final v = self.vertices[index];
        newVerts[index] = Float64x2(v.x + dx, v.y + dy);
      }

      return self.copyWith(vertices: newVerts, x: self.x + dx, y: self.y + dy);
    }

    return copyWith(x: x + dx, y: y + dy);
  }

  /// Resizes the shape from a given [handle] drag by [dx] and [dy] offsets.
  DrawElement resized({
    required double dx,
    required double dy,
    required HandlePosition handle,
    double minSize = 10.0,
  }) {
    final newHeight = switch (handle) {
      .topLeft || .topCenter || .topRight => max(height - dy, minSize),
      .bottomLeft || .bottomCenter || .bottomRight => max(height + dy, minSize),
      .centerLeft || .centerRight => height,
    };

    final newWidth = switch (handle) {
      .topLeft || .centerLeft || .bottomLeft => max(width - dx, minSize),
      .topRight || .centerRight || .bottomRight => max(width + dx, minSize),
      .topCenter || .bottomCenter => width,
    };

    final appliedHeightDelta = newHeight - height;
    final appliedWidthDelta = newWidth - width;

    final newX = switch (handle) {
      .topLeft || .centerLeft || .bottomLeft => x - appliedWidthDelta,
      .topCenter || .topRight || .centerRight || .bottomCenter || .bottomRight => x,
    };

    final newY = switch (handle) {
      .topLeft || .topCenter || .topRight => y - appliedHeightDelta,
      .centerLeft || .centerRight || .bottomLeft || .bottomCenter || .bottomRight => y,
    };

    final self = this;
    if (self is PolygonElement) {
      final horizontalScale = width == 0.0 ? 1.0 : newWidth / width;
      final verticalScale = height == 0.0 ? 1.0 : newHeight / height;

      final newVerts = Float64x2List(self.vertices.length);
      for (int index = 0; index < self.vertices.length; index += 1) {
        final v = self.vertices[index];
        newVerts[index] = Float64x2(
          newX + (v.x - x) * horizontalScale,
          newY + (v.y - y) * verticalScale,
        );
      }

      return self.copyWith(
        height: newHeight,
        vertices: newVerts,
        width: newWidth,
        x: newX,
        y: newY,
      );
    }

    return copyWith(height: newHeight, width: newWidth, x: newX, y: newY);
  }
}
