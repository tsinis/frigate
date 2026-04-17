import 'package:flutter/rendering.dart';

import 'package:frigatebird/frigatebird.dart';
import '../helpers/draw_element_extension.dart';
import '../helpers/rect_element_extension.dart';

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
      // ignore: prefer-correct-switch-length, it's TODO!
      switch (element) {
        case RectElement():
          // TODO(tsinis): render fill color too.
          final strokePaint = Paint()
            ..color = element.uiOutlineColor
            ..style = .stroke
            ..strokeWidth = element.outlineThickness.toDouble();
          canvas.drawRect(element.rect, strokePaint);

        case TextElement():
          // TODO(tsinis): render TextElement in the preview painter.
          break;
      }
    }

    final index = selectedIndex;
    if (index == null || index.isNegative || index >= elements.length) return;

    final selected = elements.elementAtOrNull(index);
    if (selected case RectElement()) {
      for (final handle in HandlePosition.values) {
        _paintHandle(canvas, _handleCenter(element: selected, handle: handle));
      }
    }
  }

  @override
  bool shouldRepaint(covariant DrawPainter oldDelegate) =>
      !identical(oldDelegate.elements, elements) || oldDelegate.selectedIndex != selectedIndex;

  static HandlePosition? hitTestHandle(Offset point, {required RectElement element}) {
    for (final handle in HandlePosition.values) {
      final center = _handleCenter(element: element, handle: handle);
      if ((point - center).distance <= handleRadius) return handle;
    }

    return null;
  }

  static bool isPointOnRect(Offset point, {required RectElement element}) {
    final rect = element.rect;
    final half = element.outlineThickness / 2 + _hitSlop;
    final outer = rect.inflate(half);
    final inner = rect.deflate(half);

    return outer.contains(point) && !inner.contains(point);
  }

  static Offset _handleCenter({required RectElement element, required HandlePosition handle}) {
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
