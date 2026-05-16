// Widget tree composes inline gesture / pointer / build callbacks where extraction would
// add named methods that don't get reused — the inline form keeps the hierarchy readable.
// ignore_for_file: prefer-extracting-callbacks, prefer-extracting-function-callbacks

import 'dart:io' show File;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:frigatebird/frigatebird.dart';
import '../helpers/draw_element_extension.dart';
import 'draw_controller.dart';
import 'draw_painter.dart';
import 'ffi_image_file.dart';

class DrawEditor extends StatefulWidget {
  const DrawEditor(this.image, {required this.controller, super.key, this.size});

  final DrawController controller;
  final File image;
  final Size? size;

  @override
  State<DrawEditor> createState() => _DrawEditorState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<DrawController>('controller', controller))
      ..add(StringProperty('image', image.path))
      ..add(DoubleProperty('size.height', size?.height))
      ..add(DoubleProperty('size.width', size?.width));
  }
}

class _DrawEditorState extends State<DrawEditor> {
  /// Floor for rect width/height while the user is resizing via a handle. Below ~10 px the rect
  /// becomes impossible to grab again because the 8 handles start overlapping each other.
  static const _minSize = 10.0;

  static DrawElement _resizedShape({
    required Offset delta,
    required HandlePosition handle,
    required DrawElement shape,
  }) {
    final DrawElement(:height, :width, :x, :y) = shape;

    final newHeight = switch (handle) {
      .topLeft || .topCenter || .topRight => max(height - delta.dy, _minSize),
      .bottomLeft || .bottomCenter || .bottomRight => max(height + delta.dy, _minSize),
      .centerLeft || .centerRight => height,
    };

    final newWidth = switch (handle) {
      .topLeft || .centerLeft || .bottomLeft => max(width - delta.dx, _minSize),
      .topRight || .centerRight || .bottomRight => max(width + delta.dx, _minSize),
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
  final _isDragging = ValueNotifier<bool>(false);

  bool _isCreating = false;
  HandlePosition? _activeHandle;
  DrawElement? _dragSnapshot;
  Offset? _creationStartPoint;

  DrawController get _controller => widget.controller;

  void _handlePointerDown(PointerDownEvent event) {
    final point = _transformController.toScene(event.localPosition);
    final template = _controller.creationTemplate;

    if (template != null) {
      _isCreating = true;
      _creationStartPoint = point;
      _controller.selectedIndex = null;

      final element = template.copyWith(height: 0, width: 0, x: point.dx, y: point.dy);
      _controller.addElement(element);

      return;
    }

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
    final start = _creationStartPoint;
    if (_isCreating && start != null) {
      final current = _controller.elements.lastOrNull;
      if (current == null) return;

      final currentPoint = _transformController.toScene(event.localPosition);
      final index = _controller.elements.length - 1;

      _controller.updateElement(current.copyWithDrag(start, currentPoint), index);

      return;
    }
    if (!_isDragging.value) return;

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
    if (_isCreating) {
      final current = _controller.elements.lastOrNull;
      if (current == null) return;
      _controller.removeLastElement(); // Remove the preview.
      // If it's too small, just drop it. We consider < 10px as an accidental press.
      if (current.width >= _minSize && current.height >= _minSize) _controller.commitAdd(current);
      _isCreating = false;
      _creationStartPoint = null;
      _controller.creationTemplate = null;

      return;
    }

    if (!_isDragging.value) return;
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
  void _handlePointerCancel(PointerCancelEvent _) {
    if (_isCreating) {
      _controller.removeLastElement();
      _isCreating = false;
      _creationStartPoint = null;
      _controller.creationTemplate = null;
    } else if (_isDragging.value) {
      _resetDragState();
    }
  }

  void _startDrag({HandlePosition? handle}) {
    _activeHandle = handle;
    _dragSnapshot = _controller.selectedElement;
    _isDragging.value = true;
  }

  void _resetDragState() {
    _activeHandle = null;
    _dragSnapshot = null;
    _isDragging.value = false;
  }

  @override
  void dispose() {
    _isDragging.dispose();
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerCancel: _handlePointerCancel,
    onPointerDown: _handlePointerDown,
    onPointerMove: _handlePointerMove,
    onPointerUp: _handlePointerUp,
    child: ValueListenableBuilder(
      builder: (_, isDragging, child) => ListenableBuilder(
        builder: (_, _) {
          final isInteracting = isDragging || _isCreating || _controller.creationTemplate != null;

          return InteractiveViewer(
            boundaryMargin: const .all(.infinity),
            constrained: false,
            maxScale: 5,
            minScale: 0.5,
            panEnabled: !isInteracting,
            scaleEnabled: !isInteracting,
            transformationController: _transformController,
            child: child ?? const SizedBox.shrink(),
          );
        },
        listenable: _controller,
      ),
      valueListenable: _isDragging,
      child: FfiImageFile(
        widget.image,
        builder: (_, image) => ListenableBuilder(
          builder: (_, child) => GestureDetector(
            // Absorb scale/pan gestures that start on an element so the
            // InteractiveViewer doesn't try to pan the canvas while we drag.
            onScaleStart: (_) {},
            onScaleUpdate: (_) {},
            child: CustomPaint(
              foregroundPainter: DrawPainter(
                _controller.elements,
                selectedIndex: _controller.selectedIndex,
              ),
              willChange: _isDragging.value || _isCreating,
              child: child,
            ),
          ),
          listenable: Listenable.merge([_controller, _isDragging]),
          child: image,
        ),
        fit: .fill,
        size: widget.size,
      ),
    ),
  );
}
