import 'package:flutter/rendering.dart';

import 'package:frigatebird/frigatebird.dart';
import '../helpers/draw_element_extension.dart';
import '../helpers/rect_element_extension.dart';

class DrawPainter extends CustomPainter {
  const DrawPainter(this.elements, {this.selectedIndex});

  static const handleRadius = 6.0;

  final List<DrawElement> elements;
  final int? selectedIndex;

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
  bool shouldRepaint(covariant DrawPainter oldDelegate) => true;

  static HandlePosition? hitTestHandle(Offset point, {required RectElement element}) {
    for (final handle in HandlePosition.values) {
      final center = _handleCenter(element: element, handle: handle);
      if ((point - center).distance <= handleRadius) return handle;
    }

    return null;
  }

  static bool isPointOnRect(Offset point, {required RectElement element}) {
    final rect = element.rect;
    final half = element.outlineThickness / 2 + 4;
    final outer = rect.inflate(half);
    final inner = rect.deflate(half);

    return outer.contains(point) && !inner.contains(point);
  }

  static Offset _handleCenter({required RectElement element, required HandlePosition handle}) {
    final Rect(:bottom, :bottomLeft, :bottomRight, :left, :right, :top, :topLeft, :topRight) =
        element.rect;
    final Offset(dx: midX, dy: midY) = element.rect.center;

    return switch (handle) {
      .topLeft => topLeft,
      .topCenter => Offset(midX, top),
      .topRight => topRight,
      .centerLeft => Offset(left, midY),
      .centerRight => Offset(right, midY),
      .bottomLeft => bottomLeft,
      .bottomCenter => Offset(midX, bottom),
      .bottomRight => bottomRight,
    };
  }

  static void _paintHandle(Canvas canvas, Offset center) {
    final fill = Paint()..color = const Color(0xFF000000);
    final border = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = .stroke
      ..strokeWidth = 2;

    canvas
      ..drawCircle(center, handleRadius, fill)
      ..drawCircle(center, handleRadius, border);
  }
}
