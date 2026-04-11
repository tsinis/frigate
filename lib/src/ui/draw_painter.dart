import 'package:flutter/rendering.dart';

import '../model/draw_element.dart';
import '../model/handle_position.dart';

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
          final strokePaint = Paint()
            ..color = element.color.toColor()
            ..style = .stroke
            ..strokeWidth = element.strokeWidth;
          canvas.drawRect(element.rect, strokePaint);
      }
    }

    final index = selectedIndex;
    if (index == null || index < 0 || index >= elements.length) return;

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
    final half = element.strokeWidth / 2 + 4;
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
