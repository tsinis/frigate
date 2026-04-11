// ignore_for_file: prefer-extracting-callbacks
// ignore_for_file: prefer-extracting-function-callbacks

import 'dart:math';

import 'package:flutter/widgets.dart';

import '../frigate_draw_dart.dart';
import 'draw_controller.dart';
import 'draw_painter.dart';

class DrawEditor extends StatefulWidget {
  const DrawEditor({
    required this.controller,
    required this.image,
    required this.imageHeight,
    required this.imageWidth,
    super.key,
  });

  final DrawController controller;
  final ImageProvider image;
  final double imageHeight;
  final double imageWidth;

  @override
  State<DrawEditor> createState() => _DrawEditorState();
}

class _DrawEditorState extends State<DrawEditor> {
  static RectElement _resizedRect({
    required Offset delta,
    required HandlePosition handle,
    required RectElement rect,
  }) {
    const minSize = 10.0;
    final RectElement(:height, :width, :x, :y) = rect;

    return switch (handle) {
      .topLeft => rect.copyWith(
        height: max(height - delta.dy, minSize),
        width: max(width - delta.dx, minSize),
        x: x + delta.dx,
        y: y + delta.dy,
      ),
      .topCenter => rect.copyWith(height: max(height - delta.dy, minSize), y: y + delta.dy),
      .topRight => rect.copyWith(
        height: max(height - delta.dy, minSize),
        width: max(width + delta.dx, minSize),
        y: y + delta.dy,
      ),
      .centerLeft => rect.copyWith(width: max(width - delta.dx, minSize), x: x + delta.dx),
      .centerRight => rect.copyWith(width: max(width + delta.dx, minSize)),
      .bottomLeft => rect.copyWith(
        height: max(height + delta.dy, minSize),
        width: max(width - delta.dx, minSize),
        x: x + delta.dx,
      ),
      .bottomCenter => rect.copyWith(height: max(height + delta.dy, minSize)),
      .bottomRight => rect.copyWith(
        height: max(height + delta.dy, minSize),
        width: max(width + delta.dx, minSize),
      ),
    };
  }

  final _transformController = TransformationController();

  bool _isDragging = false;
  HandlePosition? _activeHandle;
  DrawElement? _dragSnapshot;

  DrawController get _controller => widget.controller;

  void _handlePointerDown(PointerDownEvent event) {
    final point = _transformController.toScene(event.localPosition);

    final selected = _controller.selectedElement;
    if (selected case RectElement()) {
      final handle = DrawPainter.hitTestHandle(point, element: selected);
      if (handle != null) {
        _startDrag(handle: handle);

        return;
      }
    }

    final allElements = _controller.elements;
    for (int i = allElements.length - 1; i >= 0; i -= 1) {
      if (allElements.elementAtOrNull(i) case final RectElement target) {
        if (DrawPainter.isPointOnRect(point, element: target)) {
          _controller.selectedIndex = i;
          _startDrag();

          return;
        }
      }
    }

    _controller.selectedIndex = null;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_isDragging) return;

    final index = _controller.selectedIndex;
    final selected = _controller.selectedElement;
    final handle = _activeHandle;
    if (index == null || selected is! RectElement) return;

    final scale = _transformController.value.getMaxScaleOnAxis();
    final delta = event.delta / scale;

    final updated = handle == null
        ? selected.copyWith(x: selected.x + delta.dx, y: selected.y + delta.dy)
        : _resizedRect(delta: delta, handle: handle, rect: selected);

    _controller.updateElement(updated, index);
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (!_isDragging) return;
    final index = _controller.selectedIndex;
    final snapshot = _dragSnapshot;
    final current = _controller.selectedElement;
    if (index != null && snapshot != null && current != null) {
      _controller.commitCommand(index, after: current, before: snapshot);
    }
    setState(() {
      _isDragging = false;
      _activeHandle = null;
      _dragSnapshot = null;
    });
  }

  void _startDrag({HandlePosition? handle}) {
    setState(() {
      _isDragging = true;
      _activeHandle = handle;
      _dragSnapshot = _controller.selectedElement;
    });
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _handlePointerDown,
    onPointerMove: _handlePointerMove,
    onPointerUp: _handlePointerUp,
    child: InteractiveViewer(
      boundaryMargin: const .all(.infinity),
      maxScale: 5,
      minScale: 0.9,
      panEnabled: !_isDragging,
      scaleEnabled: !_isDragging,
      transformationController: _transformController,
      child: SizedBox(
        width: widget.imageWidth,
        height: widget.imageHeight,
        child: ListenableBuilder(
          listenable: _controller,
          builder: (_, child) => CustomPaint(
            foregroundPainter: DrawPainter(
              _controller.elements,
              selectedIndex: _controller.selectedIndex,
            ),
            child: child,
          ),
          child: Image(
            image: widget.image,
            semanticLabel: 'Background Image', // TODO!
            width: widget.imageWidth,
            height: widget.imageHeight,
            fit: .fill,
          ),
        ),
      ),
    ),
  );
}
