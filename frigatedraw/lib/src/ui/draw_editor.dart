// Widget tree composes inline gesture / pointer / build callbacks where extraction would
// add named methods that don't get reused — the inline form keeps the hierarchy readable.
// ignore_for_file: prefer-extracting-callbacks, prefer-extracting-function-callbacks

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:frigatebird/frigatebird.dart';
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

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<DrawController>('controller', controller))
      ..add(DiagnosticsProperty<ImageProvider>('image', image))
      ..add(DoubleProperty('imageHeight', imageHeight))
      ..add(DoubleProperty('imageWidth', imageWidth));
  }
}

class _DrawEditorState extends State<DrawEditor> {
  /// Floor for rect width/height while the user is resizing via a handle. Below ~10 px the rect
  /// becomes impossible to grab again because the 8 handles start overlapping each other.
  static const _minRectSize = 10.0;

  static DrawElement _resizedShape({
    required Offset delta,
    required HandlePosition handle,
    required DrawElement shape,
  }) {
    final DrawElement(:height, :width, :x, :y) = shape;

    final newHeight = switch (handle) {
      .topLeft || .topCenter || .topRight => max(height - delta.dy, _minRectSize),
      .bottomLeft || .bottomCenter || .bottomRight => max(height + delta.dy, _minRectSize),
      .centerLeft || .centerRight => height,
    };

    final newWidth = switch (handle) {
      .topLeft || .centerLeft || .bottomLeft => max(width - delta.dx, _minRectSize),
      .topRight || .centerRight || .bottomRight => max(width + delta.dx, _minRectSize),
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

    return shape.copyWith(height: newHeight, width: newWidth, x: newX, y: newY);
  }

  final _transformController = TransformationController();

  bool _isDragging = false;
  HandlePosition? _activeHandle;
  DrawElement? _dragSnapshot;

  DrawController get _controller => widget.controller;

  void _handlePointerDown(PointerDownEvent event) {
    final point = _transformController.toScene(event.localPosition);

    final selected = _controller.selectedElement;
    if (selected != null) {
      final handle = switch (selected) {
        RectElement() || OvalElement() => DrawPainter.hitTestHandle(point, element: selected),
        TextElement() => null,
      };
      if (handle != null) {
        _startDrag(handle: handle);

        return;
      }
    }

    final allElements = _controller.elements;
    for (int i = allElements.length - 1; i >= 0; i -= 1) {
      final target = allElements.elementAtOrNull(i);
      if (target != null) {
        final isHit = switch (target) {
          RectElement() || OvalElement() => DrawPainter.isPointOnShape(point, element: target),
          TextElement() => false,
        };
        if (isHit) {
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
    if (index == null || selected == null) return;
    // TODO(tsinis): Enable TextElement movement once _paintElement supports text bounds/handles.
    // Also remember to wire up hitTestHandle/hasHandles to allow text dragging.
    final canMove = switch (selected) {
      RectElement() || OvalElement() => true,
      TextElement() => false,
    };
    if (!canMove) return;

    final scale = _transformController.value.getMaxScaleOnAxis();
    final delta = event.delta / scale;

    final updated = handle == null
        ? selected.copyWith(x: selected.x + delta.dx, y: selected.y + delta.dy)
        : _resizedShape(delta: delta, handle: handle, shape: selected);

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
    _resetDragState();
  }

  /// Pointer cancellation paths: OS-level gesture takeover (system back gesture, screenshot
  /// invocation), app suspension mid-drag, or losing the multitouch gesture-arena. Without this,
  /// `_isDragging` stays `true` forever, pan/zoom is permanently disabled, and `_dragSnapshot`
  /// pins a stale element reference. Mid-drag mutations are kept (user already saw them) but no
  /// command is committed, so the partial drag isn't pushed onto the undo stack.
  void _handlePointerCancel(PointerCancelEvent _) => _isDragging ? _resetDragState() : null;

  void _startDrag({HandlePosition? handle}) {
    setState(() {
      _isDragging = true;
      _activeHandle = handle;
      _dragSnapshot = _controller.selectedElement;
    });
  }

  void _resetDragState() {
    setState(() {
      _isDragging = false;
      _activeHandle = null;
      _dragSnapshot = null;
    });
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerCancel: _handlePointerCancel,
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
        height: widget.imageHeight,
        width: widget.imageWidth,
        child: ListenableBuilder(
          builder: (_, child) => CustomPaint(
            foregroundPainter: DrawPainter(
              _controller.elements,
              selectedIndex: _controller.selectedIndex,
            ),
            child: child,
          ),
          listenable: _controller,
          child: Image(
            fit: .fill,
            height: widget.imageHeight,
            image: widget.image,
            semanticLabel: 'Background Image', // TODO.
            width: widget.imageWidth,
          ),
        ),
      ),
    ),
  );
}
