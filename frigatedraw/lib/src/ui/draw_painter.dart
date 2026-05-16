import 'package:flutter/rendering.dart';

import 'package:frigatebird/frigatebird.dart';
import '../helpers/draw_element_extension.dart';

class DrawPainter extends CustomPainter {
  const DrawPainter(this.elements, {this.selectedIndex});

  static const handleRadius = 6.0;

  final List<DrawElement> elements;
  final int? selectedIndex;

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

  @override
  void paint(Canvas canvas, Size size) {
    for (final element in elements) {
      _paintElement(canvas, element);
    }

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

  void _paintElement(Canvas canvas, DrawElement element) {
    switch (element) {
      case RectElement():
        _paintRect(canvas, element);

      case OvalElement():
        _paintOval(canvas, element);

      case TextElement():
        // TODO(tsinis): render TextElement in the preview painter.
        break;
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
  bool shouldRepaint(covariant DrawPainter oldDelegate) =>
      !identical(oldDelegate.elements, elements) || oldDelegate.selectedIndex != selectedIndex;

  static HandlePosition? hitTestHandle(Offset point, {required DrawElement element}) {
    if (element.width <= 0 || element.height <= 0) return null;

    for (final handle in HandlePosition.values) {
      final center = _handleCenter(element: element, handle: handle);
      if ((point - center).distance <= handleRadius) return handle;
    }

    return null;
  }

  static bool isPointOnShape(Offset point, {required DrawElement element}) {
    if (element.width <= 0 || element.height <= 0) return false;

    final rect = element.rect;
    final half = element.outlineThickness.toDouble() / 2 + _hitSlop;
    final outer = rect.inflate(half);

    return switch (element) {
      OvalElement() => _isPointInEllipse(point, outer),
      RectElement() || TextElement() => outer.contains(point),
    };
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
