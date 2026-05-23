import 'dart:typed_data' show Float64x2;
import 'package:flutter/rendering.dart';
import 'package:frigatebird/frigatebird.dart';

import '../helpers/draw_element_extension.dart';
import 'draw_tool.dart';

class DrawPainter extends CustomPainter {
  const DrawPainter(
    this.elements, {
    this.activeTool,
    this.creationTemplate,
    this.cursorPosition,
    this.pendingVertices,
    this.selectedIndex,
    this.tolerance = 20.0,
  });

  static const handleRadius = 6.0;

  final List<DrawElement> elements;
  final int? selectedIndex;
  final List<Float64x2>? pendingVertices;
  final Offset? cursorPosition;
  final DrawTool? activeTool;
  final double tolerance;
  final DrawElement? creationTemplate;

  /// Hit-test slop around a rect outline: how far inside/outside a tap still counts as "on the
  /// rect." Keeps finger/mouse imprecision from making selection feel flaky at thin strokes.
  static const _hitSlop = 4.0;

  // Paint instances live at class scope so we don't rebuild them per handle, per frame.
  // Colors and stroke are constant, nothing to parameterize.
  static final _handleFillPaint = Paint()..color = const Color(0xFF000000);
  static final _handleBorderPaint = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..style = .stroke
    ..strokeWidth = 2;

  static final _polygonPathCache = Expando<Path>();

  static Path _getPathForPolygon(PolygonElement element) {
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
      // ignore: avoid-collection-mutating-methods, Expando operates as a lookup map, not an in-place collection mutation.
      _polygonPathCache[element.vertices] = path;

      return path;
    }

    return cached;
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final element in elements) {
      _paintElement(canvas, element);
    }

    _paintPolygonPreview(canvas);

    final index = selectedIndex;
    if (index == null || index.isNegative || index >= elements.length) return;

    final selected = elements.elementAtOrNull(index);
    if (selected == null) return;

    if (selected is! TextElement && selected.width > 0 && selected.height > 0) {
      for (final handle in HandlePosition.values) {
        _paintHandle(canvas, _handleCenter(element: selected, handle: handle));
      }
    }
  }

  Color get _previewOutlineColor {
    final template = creationTemplate;

    return template == null ? const Color(0xFF000000) : template.uiOutlineColor;
  }

  double get _previewOutlineThickness {
    final template = creationTemplate;

    return template == null ? 2.0 : template.outlineThickness.toDouble();
  }

  void _paintPolygonPreview(Canvas canvas) {
    final pending = pendingVertices;
    if (activeTool != .polygon || pending == null || pending.isEmpty) return;

    final color = _previewOutlineColor;
    final thickness = _previewOutlineThickness;

    _paintOpenPath(canvas, color, pending, thickness);
    if (cursorPosition == null) {
      _paintClosingLine(canvas, color, pending, thickness);
    } else {
      _paintCursorLine(canvas, color, cursorPosition, pending, thickness);
    }
    _paintVertexHandles(canvas, pending);
    _paintCloseZone(canvas, color, pending, tolerance);
  }

  static void _paintOpenPath(
    Canvas canvas,
    Color color,
    List<Float64x2> pending,
    double thickness,
  ) {
    final first = pending.firstOrNull;
    if (first == null) return;

    final path = Path()..moveTo(first.x, first.y);
    for (int i = 1; i < pending.length; i += 1) {
      path.lineTo(pending[i].x, pending[i].y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = .stroke
        ..strokeWidth = thickness,
    );
  }

  static void _paintCursorLine(
    Canvas canvas,
    Color color,
    Offset? cursor,
    List<Float64x2> pending,
    double thickness,
  ) {
    if (cursor == null || pending.isEmpty) return;
    final lastVertex = pending.lastOrNull;
    if (lastVertex == null) return;

    _drawDashedLine(
      canvas,
      Offset(lastVertex.x, lastVertex.y),
      Paint()
        ..color = color.withValues(alpha: 0.5)
        ..style = .stroke
        ..strokeWidth = thickness,
      cursor,
    );
  }

  static void _paintClosingLine(
    Canvas canvas,
    Color color,
    List<Float64x2> pending,
    double thickness,
  ) {
    if (pending.length < 2) return;

    final firstVertex = pending.firstOrNull;
    final lastVertex = pending.lastOrNull;
    if (firstVertex == null || lastVertex == null) return;

    _drawDashedLine(
      canvas,
      Offset(firstVertex.x, firstVertex.y),
      Paint()
        ..color = color.withValues(alpha: 0.5)
        ..style = .stroke
        ..strokeWidth = thickness,
      Offset(lastVertex.x, lastVertex.y),
    );
  }

  static void _paintVertexHandles(Canvas canvas, List<Float64x2> pending) {
    final paint = Paint()..color = const Color(0xFF000000);
    for (final vertex in pending) {
      canvas.drawCircle(Offset(vertex.x, vertex.y), 4, paint);
    }
  }

  static void _paintCloseZone(
    Canvas canvas,
    Color color,
    List<Float64x2> pending,
    double zoneRadius,
  ) {
    final firstVertex = pending.firstOrNull;
    if (firstVertex == null) return;

    canvas.drawCircle(
      Offset(firstVertex.x, firstVertex.y),
      zoneRadius,
      Paint()
        ..color = color.withValues(alpha: 0.5)
        ..style = .fill,
    );
  }

  static void _drawDashedLine(Canvas canvas, Offset origin, Paint paint, Offset target) {
    const dashWidth = 4.0;
    const dashSpace = 4.0;
    final Offset(dx: origX, dy: origY) = origin;
    final Offset(dx: destX, dy: destY) = target;
    final diffX = destX - origX;
    final diffY = destY - origY;
    final distance = Offset(diffX, diffY).distance;
    if (distance == 0) return;

    final count = (distance / (dashWidth + dashSpace)).floor();
    final incX = diffX / distance;
    final incY = diffY / distance;

    for (int i = 0; i < count; i += 1) {
      final dashX = origX + incX * i * (dashWidth + dashSpace);
      final dashY = origY + incY * i * (dashWidth + dashSpace);
      canvas.drawLine(
        Offset(dashX, dashY),
        Offset(dashX + incX * dashWidth, dashY + incY * dashWidth),
        paint,
      );
    }
  }

  void _paintElement(Canvas canvas, DrawElement element) => switch (element) {
    RectElement() => _paintRect(canvas, element),
    OvalElement() => _paintOval(canvas, element),
    PolygonElement() => _paintPolygon(canvas, element),
    TextElement() => {}, // TODO(tsinis): render TextElement in the preview painter.
  };

  static void _paintPolygon(Canvas canvas, PolygonElement element) {
    if (element.vertices.length < 3) return;
    final path = _getPathForPolygon(element);

    if (element.uiFillColor.a > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..color = element.uiFillColor
          ..style = .fill
          ..isAntiAlias = true,
      );
    }

    if (element.outlineThickness > 0 && element.uiOutlineColor.a > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..color = element.uiOutlineColor
          ..style = .stroke
          ..strokeWidth = element.outlineThickness.toDouble()
          ..isAntiAlias = true,
      );
    }
  }

  static void _paintRect(Canvas canvas, RectElement element) {
    final RectElement(
      :cornerRadius,
      :height,
      :outlineThickness,
      :rect,
      :uiFillColor,
      :uiOutlineColor,
      :width,
    ) = element;
    // Mirror Rust's short-circuit on non-positive dims; otherwise Flutter would render
    // a flipped rect from a negative-width Rect — a real preview-vs-export divergence.
    if (width <= 0 || height <= 0) return;

    final isRounded = cornerRadius > 0;

    if (uiFillColor.a > 0) {
      final fillPaint = Paint()
        ..color = uiFillColor
        ..style = .fill
        ..isAntiAlias = isRounded;
      if (isRounded) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            rect,
            .circular(cornerRadius.toDouble().clamp(0.0, rect.shortestSide / 2)),
          ),
          fillPaint,
        );
      } else {
        canvas.drawRect(rect, fillPaint);
      }
    }

    if (outlineThickness > 0 && uiOutlineColor.a > 0) {
      final strokePaint = Paint()
        ..color = uiOutlineColor
        ..style = .stroke
        ..strokeWidth = outlineThickness.toDouble()
        ..isAntiAlias = isRounded;
      if (isRounded) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            rect,
            .circular(cornerRadius.toDouble().clamp(0.0, rect.shortestSide / 2)),
          ),
          strokePaint,
        );
      } else {
        canvas.drawRect(rect, strokePaint);
      }
    }
  }

  static void _paintOval(Canvas canvas, OvalElement element) {
    final OvalElement(:height, :outlineThickness, :rect, :uiFillColor, :uiOutlineColor, :width) =
        element;
    if (width <= 0 || height <= 0) return;

    if (uiFillColor.a > 0) {
      canvas.drawOval(
        rect,
        Paint()
          ..color = uiFillColor
          ..style = .fill
          ..isAntiAlias = true,
      );
    }

    if (outlineThickness > 0 && uiOutlineColor.a > 0) {
      canvas.drawOval(
        rect,
        Paint()
          ..color = uiOutlineColor
          ..style = .stroke
          ..strokeWidth = outlineThickness.toDouble()
          ..isAntiAlias = true,
      );
    }
  }

  @override
  bool shouldRepaint(covariant DrawPainter oldDelegate) {
    final DrawPainter(
      activeTool: oldActiveTool,
      creationTemplate: oldCreationTemplate,
      cursorPosition: oldCursorPosition,
      elements: oldElements,
      pendingVertices: oldPendingVertices,
      selectedIndex: oldSelectedIndex,
      tolerance: oldTolerance,
    ) = oldDelegate;

    final isSame =
        identical(oldElements, elements) &&
        oldSelectedIndex == selectedIndex &&
        identical(oldPendingVertices, pendingVertices) &&
        oldCursorPosition == cursorPosition &&
        oldActiveTool == activeTool &&
        identical(oldCreationTemplate, creationTemplate) &&
        oldTolerance == tolerance;

    return !isSame;
  }

  @override
  bool hitTest(Offset position) {
    final index = selectedIndex;
    if (index != null && index >= 0 && index < elements.length) {
      final select = elements.elementAtOrNull(index);
      if (select is! TextElement && hitTestHandle(position, element: select) != null) return true;
    }

    for (int i = elements.length - 1; i >= 0; i -= 1) {
      final target = elements.elementAtOrNull(i);
      final isHit = switch (target) {
        RectElement() || OvalElement() => isPointOnShape(position, element: target),
        PolygonElement() => isPointOnShape(position, element: target),
        _ => false, // ignore: avoid-wildcard-cases-with-sealed-classes, covers text and null.
      };
      if (isHit) return true;
    }

    return false;
  }

  static HandlePosition? hitTestHandle(Offset point, {DrawElement? element}) {
    if (element == null || element.width <= 0 || element.height <= 0) return null;

    for (final handle in HandlePosition.values) {
      final center = _handleCenter(element: element, handle: handle);
      if ((point - center).distance <= handleRadius) return handle;
    }

    return null;
  }

  static bool isPointOnShape(Offset point, {DrawElement? element}) {
    if (element == null || element.width <= 0 || element.height <= 0) return false;

    final rect = element.rect;
    final half = element.outlineThickness.toDouble() / 2 + _hitSlop;
    final outer = rect.inflate(half);

    if (!outer.contains(point)) return false;

    return switch (element) {
      OvalElement() => _isPointInEllipse(point, outer),
      PolygonElement() => _isPointInPolygon(element, point),
      RectElement() || TextElement() => true,
    };
  }

  static bool _isPointInPolygon(PolygonElement element, Offset point) {
    if (element.vertices.length < 3) {
      return false;
    }

    final path = _getPathForPolygon(element);

    return path.contains(point);
  }

  /// Simple ellipse hit test: (x-h)^2/a^2 + (y-k)^2/b^2 <= 1.
  static bool _isPointInEllipse(Offset point, Rect rect) {
    final axisA = rect.width / 2;
    final axisB = rect.height / 2;
    if (axisA <= 0 || axisB <= 0) return false;

    final diffX = point.dx - rect.center.dx;
    final diffY = point.dy - rect.center.dy;

    return (diffX * diffX) / (axisA * axisA) + (diffY * diffY) / (axisB * axisB) <= 1.0;
  }

  static Offset _handleCenter({required DrawElement element, required HandlePosition handle}) {
    final Rect(
      :bottomCenter,
      :bottomLeft,
      :bottomRight,
      :centerLeft,
      :centerRight,
      :topCenter,
      :topLeft,
      :topRight,
    ) = element.rect;

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

  static void _paintHandle(Canvas canvas, Offset center) {
    canvas
      ..drawCircle(center, handleRadius, _handleFillPaint)
      ..drawCircle(center, handleRadius, _handleBorderPaint);
  }
}
