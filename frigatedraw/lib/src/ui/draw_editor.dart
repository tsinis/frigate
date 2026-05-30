// ignore_for_file: prefer-extracting-function-callbacks, prefer-class-destructuring

import 'dart:io' show File;
import 'dart:math';
import 'dart:typed_data' show Float64x2List;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:frigatebird/frigatebird.dart';
import '../helpers/draw_element_extension.dart';
import '../helpers/image_information_extension.dart';
import 'draw_controller.dart';
import 'draw_painter.dart';
import 'ffi_image_file.dart';

class DrawEditor extends InteractiveViewer {
  DrawEditor(
    this._image, {
    required this._controller,
    this._minShapeSize = 10.0,
    this._size,
    super.alignment,
    super.boundaryMargin = const .all(.infinity),
    super.clipBehavior,
    super.interactionEndFrictionCoefficient,
    super.key,
    super.maxScale = 5,
    super.minScale = 1 / 2,
    super.onInteractionEnd,
    super.onInteractionStart,
    super.onInteractionUpdate,
    super.panAxis,
    super.scaleEnabled,
    super.scaleFactor,
    super.trackpadScrollCausesScale,
  }) : super(child: const SizedBox.shrink(), constrained: false);

  final DrawController _controller;
  final File _image;
  final Size? _size;
  final double _minShapeSize;

  @override
  State<DrawEditor> createState() => _DrawEditorState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<DrawController>('_controller', _controller))
      ..add(StringProperty('_image', _image.path))
      ..add(DoubleProperty('_size.height', _size?.height))
      ..add(DoubleProperty('_size.width', _size?.width));
  }
}

class _DrawEditorState extends State<DrawEditor> {
  final _transformController = TransformationController();
  final _isDragging = ValueNotifier<bool>(false);

  // ignore: avoid-explicit-type-declaration, avoid-late-keyword, it's safe for an unboxed value.
  late final double _closeTolerance = widget._minShapeSize * 2;

  bool _isCreating = false;
  HandlePosition? _activeHandle;
  DrawElement? _dragSnapshot;
  Offset? _creationStartPoint;
  DrawElement? _previewElement;
  int? _previewIndex;

  /// Tracks the number of active pointers to distinguish between 1-finger dragging
  /// and multi-finger pinch-zooming.
  int _pointerCount = 0;

  /// Stores the matrix at the exact moment a drag starts, used to block the 1-frame
  /// jitter in InteractiveViewer.
  Matrix4? _dragStartMatrix;

  /// The ID of the pointer currently owning the drag/creation interaction.
  int? _activePointerId;
  Size? _boardSize;
  bool _didApplyInitialFit = false;

  DrawController get _controller => widget._controller;

  // InteractiveViewer produces a pure 2D scale+translate matrix; the Z axis
  // is always 1. getMaxScaleOnAxis() returns max(scaleXY, Z=1), so it always
  // returns ≥ 1 and is wrong whenever the fit scale is < 1 (zoomed-out).
  // Reading storage[0] gives the actual XY scale directly.
  double get _viewScale => _transformController.value.storage.firstOrNull ?? 1;

  // Handles are designed at 12px for 800×600 images. Scale proportionally
  // so they remain visually consistent at any resolution. Never shrink below
  // the reference size (800px max-dimension = scale ≥ 1).
  double get _handleRadius {
    final board = _boardSize;
    if (board == null || board.isEmpty) return 12;
    final maxDim = board.width > board.height ? board.width : board.height;

    return (maxDim / 800.0).clamp(1.0, double.infinity) * 12.0;
  }

  // White XOR outline (selection box, polygon preview paths). Uses half the
  // handle scale rate: handles use maxDim/800, outline uses maxDim/1600.
  // At 4K (3840px): handles scale 4.8×, outline scales 2.4×.
  double get _outlineStrokeWidth {
    final board = _boardSize;
    if (board == null || board.isEmpty) return 4;
    final maxDim = board.width > board.height ? board.width : board.height;

    return (maxDim / 1600.0).clamp(1.0, double.infinity) * 4.0;
  }

  @override
  void initState() {
    super.initState();
    _boardSize = widget._size;
    _transformController.addListener(_onTransformationChanged);
  }

  void _handleImageInfo(ImageInformation info) {
    if (_boardSize != info.size) setState(() => _boardSize = info.size);
  }

  void _applyInitialFitIfReady(Size viewport) {
    if (_didApplyInitialFit) return;
    final board = _boardSize;
    if (board == null || board.isEmpty || viewport.isInfinite || viewport.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didApplyInitialFit) return;
      _didApplyInitialFit = true;
      final width = viewport.width;
      final height = viewport.height;
      final scale = min(1, min(width / board.width, height / board.height)).toDouble();

      _transformController.value = Matrix4.identity()
        ..setEntry(0, 0, scale)
        ..setEntry(1, 1, scale)
        ..setEntry(0, 3, (width - board.width * scale) / 2)
        ..setEntry(1, 3, (height - board.height * scale) / 2);
    });
  }

  /// Synchronously snaps the matrix back to its starting value if we are dragging
  /// an element with a single finger. This prevents the "panning jitter" that occurs
  /// between the `onPointerDown` event and the subsequent UI rebuild.
  void _onTransformationChanged() {
    final startMatrix = _dragStartMatrix;
    if ((startMatrix != null && _pointerCount == 1 && (_isDragging.value || _isCreating)) &&
        (_transformController.value != startMatrix)) {
      _transformController.value = startMatrix;
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    _pointerCount += 1;
    // If a second finger lands, we are likely zooming, so stop locking the board.
    if (_pointerCount > 1) _dragStartMatrix = null;
    if (_activePointerId != null) return;

    final point = _transformController.toScene(event.localPosition);
    final pointerId = event.pointer;

    if (_didHandlePolygonTool(point, pointerId)) return;
    if (_didHandleCreationTool(point, pointerId)) return;
    if (_didHandleSelectedHandleInteraction(point, pointerId)) return;
    if (_didHandleElementSelection(point, pointerId)) return;

    _controller.selectedIndex = null;
  }

  bool _didHandlePolygonTool(Offset point, int pointerId) {
    if (_controller.activeTool != .polygon) return false;

    _controller.updateCursorPosition(point);
    _activePointerId = pointerId;

    return true;
  }

  void _didHandlePolygonUp(Offset point) {
    final pending = _controller.pendingVertices;
    if (pending.length >= 3) {
      final first = Offset(pending.first.x, pending.first.y);
      final distance = (point - first).distance;
      if (distance < _closeTolerance / _viewScale) {
        final template = _controller.creationTemplate;
        if (template is PolygonElement) {
          final vertices = Float64x2List.fromList(pending);
          final box = PolygonElement.boundingBoxOf(vertices);
          if (box.width > 0.0 && box.height > 0.0) {
            final element = template.copyWith(
              height: box.height,
              vertices: vertices,
              width: box.width,
              x: box.x,
              y: box.y,
            );
            _controller.commitAdd(element);
          }
          _controller.creationTemplate = null;
          _previewIndex = null;
        }

        return _controller.updateCursorPosition(null);
      }
    }
    _controller
      ..addPendingVertex(point)
      ..updateCursorPosition(null);
  }

  bool _didHandleCreationTool(Offset point, int pointerId) {
    final template = _controller.creationTemplate;
    if (template == null) return false;

    _isCreating = true;
    _creationStartPoint = point;
    _controller.selectedIndex = null;
    _activePointerId = pointerId;

    if (_pointerCount == 1) _dragStartMatrix = _transformController.value;
    final element = template.copyWith(height: 0, width: 0, x: point.dx, y: point.dy);
    _controller.addElement(element);
    _previewIndex = _controller.elements.length - 1;
    _previewElement = element;

    return true;
  }

  bool _didHandleSelectedHandleInteraction(Offset point, int pointerId) {
    final selected = _controller.selectedElement;
    if (selected == null) return false;

    final handle = selected.hitTestHandle(point, _handleRadius);
    if (handle == null) return false;

    if (_pointerCount == 1) _dragStartMatrix = _transformController.value;
    _activePointerId = pointerId;
    _startDrag(handle: handle);

    return true;
  }

  bool _didHandleElementSelection(Offset point, int pointerId) {
    final allElements = _controller.elements;
    for (int i = allElements.length - 1; i >= 0; i -= 1) {
      final target = allElements.elementAtOrNull(i);
      if (target != null && target.isPointOnShape(point)) {
        if (_pointerCount == 1) _dragStartMatrix = _transformController.value;
        _activePointerId = pointerId;
        _controller.selectedIndex = i;
        _startDrag();

        return true;
      }
    }

    return false;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_activePointerId != null && event.pointer != _activePointerId) return;

    final start = _creationStartPoint;
    final pIndex = _resolvePreviewIndex;

    if (_isCreating && start != null) {
      final current = pIndex == null ? null : _controller.elements.elementAtOrNull(pIndex);
      if (current == null || pIndex == null) return _abortCreation();

      final currentPoint = _transformController.toScene(event.localPosition);
      final updated = current.copyWithDrag(a: currentPoint, b: start);
      _controller.updateElement(updated, pIndex);
      _previewElement = updated;

      return;
    }

    if (_controller.activeTool == .polygon) {
      return _controller.updateCursorPosition(_transformController.toScene(event.localPosition));
    }

    if (!_isDragging.value) return;

    final index = _controller.selectedIndex;
    final selected = _controller.selectedElement;
    final handle = _activeHandle;
    if (index == null || selected == null) return;
    // TODO(tsinis): Enable TextElement movement once _paintElement supports text bounds/handles.
    // Also remember to wire up hitTestHandle/hasHandles to allow text dragging.
    final canMove = switch (selected) {
      RectElement() || OvalElement() || PolygonElement() || MaskRegionElement() => true,
      TextElement() => false,
    };
    if (!canMove) return;

    final delta = event.delta / _viewScale;

    final updated = handle == null
        ? selected.moved(delta.dx, delta.dy)
        : selected.resized(dx: delta.dx, dy: delta.dy, handle: handle);

    _controller.updateElement(updated, index);
  }

  void _abortCreation() {
    _isCreating = false;
    _creationStartPoint = null;
    _previewIndex = null;
    _previewElement = null;
    _controller.creationTemplate = null;
    _dragStartMatrix = null;
    _activePointerId = null;
  }

  void _handlePointerUp(PointerUpEvent event) {
    _pointerCount = max(0, _pointerCount - 1);
    if (_pointerCount == 0) _dragStartMatrix = null;
    if (_activePointerId != null && event.pointer != _activePointerId) return;
    if (_controller.activeTool == .polygon) {
      final point = _transformController.toScene(event.localPosition);
      _didHandlePolygonUp(point);

      return _activePointerId = null;
    }

    final pIndex = _resolvePreviewIndex;
    if (_isCreating) {
      final current = pIndex == null ? null : _controller.elements.elementAtOrNull(pIndex);
      if (current == null || pIndex == null) return _abortCreation();

      // If it's too small, just drop it. We consider < 10px as an accidental press.
      if (current.width >= widget._minShapeSize && current.height >= widget._minShapeSize) {
        _controller.replacePreviewAndCommit(current, pIndex);
      } else {
        _controller.dropElementAt(pIndex);
      }

      return _abortCreation();
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
  void _handlePointerCancel(PointerCancelEvent event) {
    _pointerCount = max(0, _pointerCount - 1);
    if (_pointerCount == 0) _dragStartMatrix = null;
    if (_activePointerId != null && event.pointer != _activePointerId) return;
    if (_controller.activeTool == .polygon) {
      _controller.updateCursorPosition(null);

      return _activePointerId = null;
    }

    final pIndex = _resolvePreviewIndex;
    if (_isCreating) {
      if (pIndex != null) _controller.dropElementAt(pIndex);
      _abortCreation();
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
    _dragStartMatrix = null;
    _activePointerId = null;
  }

  @override
  void didUpdateWidget(DrawEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget._image.path == widget._image.path && oldWidget._size == widget._size) return;
    _boardSize = widget._size;
    _didApplyInitialFit = false;
  }

  @override
  void dispose() {
    _isDragging.dispose();
    _transformController
      ..removeListener(_onTransformationChanged)
      ..dispose();
    super.dispose();
  }

  int? get _resolvePreviewIndex {
    final idx = _previewIndex;
    final token = _previewElement;
    if (idx != null) {
      final atIdx = _controller.elements.elementAtOrNull(idx);
      if (token != null && identical(atIdx, token)) return idx;
    }
    if (token == null) return null;
    final resolved = _controller.elements.indexWhere((e) => identical(e, token));

    return resolved.isNegative ? null : resolved;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    // ignore: avoid-long-functions, TODO(tsinis): Refactor it later.
    builder: (_, constraints) {
      _applyInitialFitIfReady(constraints.biggest);

      return Listener(
        onPointerCancel: _handlePointerCancel,
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: _handlePointerUp,
        child: ValueListenableBuilder(
          builder: (_, isDragging, child) => ListenableBuilder(
            builder: (_, _) {
              final isInteracting =
                  isDragging || _isCreating || _controller.creationTemplate != null;

              return InteractiveViewer(
                alignment: widget.alignment,
                boundaryMargin: widget.boundaryMargin,
                clipBehavior: widget.clipBehavior,
                constrained: widget.constrained,
                interactionEndFrictionCoefficient: widget.interactionEndFrictionCoefficient,
                maxScale: widget.maxScale,
                minScale: widget.minScale,
                onInteractionEnd: widget.onInteractionEnd,
                onInteractionStart: widget.onInteractionStart,
                onInteractionUpdate: widget.onInteractionUpdate,
                panAxis: widget.panAxis,
                panEnabled: !isInteracting,
                scaleEnabled: widget.scaleEnabled,
                scaleFactor: widget.scaleFactor,
                trackpadScrollCausesScale: widget.trackpadScrollCausesScale,
                transformationController: _transformController,
                child: child ?? const SizedBox.shrink(),
              );
            },
            listenable: _controller,
          ),
          valueListenable: _isDragging,
          child: FfiImageFile(
            widget._image,
            builder: (displayImage, info, uiImage) => ListenableBuilder(
              builder: (_, child) => CustomPaint(
                foregroundPainter: DrawPainter(
                  _controller.elements,
                  activeTool: _controller.activeTool,
                  backgroundImage: uiImage,
                  creationTemplate: _controller.creationTemplate,
                  cursorPosition: _controller.cursorPosition,
                  handleRadius: _handleRadius,
                  outlineStrokeWidth: _outlineStrokeWidth,
                  pendingVertices: _controller.pendingVertices,
                  selectedIndex: _controller.selectedIndex,
                  tolerance: _closeTolerance / _viewScale,
                ),
                size: info.size,
                willChange: _isDragging.value || _isCreating,
                child: child,
              ),
              listenable: Listenable.merge([_controller, _isDragging, _transformController]),
              child: displayImage,
            ),
            fit: .fill,
            onInfo: _handleImageInfo,
            size: _boardSize,
          ),
        ),
      );
    },
  );
}
