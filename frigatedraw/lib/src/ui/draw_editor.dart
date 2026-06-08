// ignore_for_file: prefer-extracting-function-callbacks,prefer-class-destructuring,avoid-long-files

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

/// Signature for the optional overlay builder in [DrawEditor].
typedef DrawEditorBuilder =
    Widget Function(DrawController draw, ImageInformation info, TransformationController transform);

class DrawEditor extends InteractiveViewer {
  DrawEditor(
    this._image, {
    this._builder,
    this._controller,
    this._fit = StackFit.loose,
    this._minShapeSize = 10.0,
    this._size,
    this._textDirection,
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

  final DrawEditorBuilder? _builder;
  final DrawController? _controller;
  final File _image;
  final double _minShapeSize;
  final Size? _size;

  /// The text direction with which to resolve [alignment].
  ///
  /// Defaults to the ambient [Directionality].
  final TextDirection? _textDirection;

  /// How to size the non-positioned children in the stack.
  ///
  /// The constraints passed into the [Stack] from its parent are either
  /// loosened ([StackFit.loose]) or tightened to their biggest size
  /// ([StackFit.expand]).
  final StackFit _fit;

  @override
  State<DrawEditor> createState() => _DrawEditorState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<DrawController?>('_controller', _controller))
      ..add(ObjectFlagProperty<DrawEditorBuilder?>.has('_builder', _builder))
      ..add(StringProperty('_image', _image.path))
      ..add(DoubleProperty('_minShapeSize', _minShapeSize))
      ..add(EnumProperty<StackFit>('_fit', _fit))
      ..add(EnumProperty<TextDirection?>('_textDirection', _textDirection))
      ..add(DoubleProperty('_size.height', _size?.height))
      ..add(DoubleProperty('_size.width', _size?.width));
  }
}

class _DrawEditorState extends State<DrawEditor> {
  /// Guards against pan re-enabling from float jitter at exactly fit scale.
  static const _panScaleEpsilon = 1e-3;
  final _transform = TransformationController();

  final _isDragging = ValueNotifier<bool>(false);

  /// True only when zoomed in past the initial fit scale. Gates `panEnabled`;
  /// derived in [_onTransformationChanged] so it flips on threshold crossings
  /// instead of rebuilding the viewer on every transform tick.
  final _canPan = ValueNotifier<bool>(false);
  double _closeTolerance = 0;

  bool _isCreating = false;
  HandlePosition? _activeHandle;
  DrawElement? _dragSnapshot;
  Offset? _creationStartPoint;
  DrawElement? _previewElement;
  int? _previewIndex;

  /// Tracks the number of active pointers to distinguish between 1-finger dragging
  /// and multi-finger pinch-zooming.
  int _pointerCount = 0;

  Matrix4? _dragStartMatrix; // Stores the matrix at the exact moment a drag starts.
  int? _activePointerId; // The ID of the pointer currently owning the drag/creation interaction.
  Size? _boardSize;
  bool _didApplyInitialFit = false;

  /// The scale applied by [_applyInitialFitIfReady] to fit the image to the
  /// viewport. Pan is only allowed once the user pinches in past this scale,
  /// so an accidental one-finger drag while reaching for a tool/slider can't
  /// shift the full-image view. Null until the initial fit is applied.
  double? _fitScale;

  // ignore: avoid-late-keyword, it's needed because of the widget access.
  late DrawController _draw = widget._controller ?? DrawController();

  /// InteractiveViewer produces a pure 2D scale+translate matrix; the Z axis
  /// is always 1. getMaxScaleOnAxis() returns max(scaleXY, Z=1), so it always
  /// returns ≥ 1 and is wrong whenever the fit scale is < 1 (zoomed-out).
  /// Reading storage[0] gives the actual XY scale directly.
  double get _viewScale => _transform.value.storage.firstOrNull ?? 1;

  double get _handleRadius {
    final board = _boardSize;
    if (board == null || board.isEmpty) return 12;
    final maxDim = board.width > board.height ? board.width : board.height;

    return (maxDim / 800.0).clamp(1.0, double.infinity) * 12.0;
  }

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
    _closeTolerance = widget._minShapeSize * 2;
    _transform.addListener(_onTransformationChanged);
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
      _fitScale = scale;

      _transform.value = Matrix4.identity()
        ..setEntry(0, 0, scale)
        ..setEntry(1, 1, scale)
        ..setEntry(0, 3, (width - board.width * scale) / 2)
        ..setEntry(1, 3, (height - board.height * scale) / 2);
    });
  }

  void _onTransformationChanged() {
    final startMatrix = _dragStartMatrix;
    if ((startMatrix != null && _pointerCount == 1 && (_isDragging.value || _isCreating)) &&
        (_transform.value != startMatrix)) {
      _transform.value = startMatrix;
    }
    final fit = _fitScale;
    _canPan.value = fit != null && _viewScale > fit + _panScaleEpsilon;
  }

  void _handlePointerDown(PointerDownEvent event) {
    _pointerCount += 1; // If a 2nd finger lands, we are likely zooming, so stop locking the board.
    if (_pointerCount > 1) _dragStartMatrix = null;
    if (_activePointerId != null) return;

    final point = _transform.toScene(event.localPosition);
    final pointerId = event.pointer;

    if (_didHandlePolygonTool(point, pointerId)) return;
    if (_didHandleCreationTool(point, pointerId)) return;
    if (_didHandleSelectedHandleInteraction(point, pointerId)) return;
    if (_didHandleElementSelection(point, pointerId)) return;

    _draw.selectedIndex = null;
  }

  bool _didHandlePolygonTool(Offset point, int pointerId) {
    if (_draw.activeTool != .polygon) return false;

    _draw.updateCursorPosition(point);
    _activePointerId = pointerId;

    return true;
  }

  void _didHandlePolygonUp(Offset point) {
    final pending = _draw.pendingVertices;
    if (pending.length >= 3) {
      final first = Offset(pending.first.x, pending.first.y);
      final distance = (point - first).distance;
      if (distance < _closeTolerance / _viewScale) {
        final template = _draw.creationTemplate;
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
            _draw.commitAdd(element);
          }
          _draw.creationTemplate = null;
          _previewIndex = null;
        }

        return _draw.updateCursorPosition(null);
      }
    }
    _draw
      ..addPendingVertex(point)
      ..updateCursorPosition(null);
  }

  bool _didHandleCreationTool(Offset point, int pointerId) {
    final template = _draw.creationTemplate;
    if (template == null) return false;

    _isCreating = true;
    _creationStartPoint = point;
    _draw.selectedIndex = null;
    _activePointerId = pointerId;

    if (_pointerCount == 1) _dragStartMatrix = _transform.value;
    final element = template.copyWith(height: 0, width: 0, x: point.dx, y: point.dy);
    _draw.addElement(element);
    _previewIndex = _draw.elements.length - 1;
    _previewElement = element;

    return true;
  }

  bool _didHandleSelectedHandleInteraction(Offset point, int pointerId) {
    final selected = _draw.selectedElement;
    if (selected == null) return false;

    final handle = selected.hitTestHandle(point, _handleRadius);
    if (handle == null) return false;

    if (_pointerCount == 1) _dragStartMatrix = _transform.value;
    _activePointerId = pointerId;
    _startDrag(handle: handle);

    return true;
  }

  bool _didHandleElementSelection(Offset point, int pointerId) {
    final allElements = _draw.elements;
    for (int i = allElements.length - 1; i >= 0; i -= 1) {
      final target = allElements.elementAtOrNull(i);
      if (target != null && target.isPointOnShape(point)) {
        if (_pointerCount == 1) _dragStartMatrix = _transform.value;
        _activePointerId = pointerId;
        _draw.selectedIndex = i;
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
      final current = pIndex == null ? null : _draw.elements.elementAtOrNull(pIndex);
      if (current == null || pIndex == null) return _abortCreation();

      final currentPoint = _transform.toScene(event.localPosition);
      final updated = current.copyWithDrag(a: currentPoint, b: start);
      _draw.updateElement(updated, pIndex);
      _previewElement = updated;

      return;
    }

    if (_draw.activeTool == .polygon) {
      return _draw.updateCursorPosition(_transform.toScene(event.localPosition));
    }

    if (!_isDragging.value) return;

    final index = _draw.selectedIndex;
    final selected = _draw.selectedElement;
    final handle = _activeHandle;
    if (index == null || selected == null) return;
    // TODO(tsinis): Enable TextElement movement once _paintElement supports text bounds/handles.
    final canMove = switch (selected) {
      RectElement() || OvalElement() || PolygonElement() || MaskRegionElement() => true,
      TextElement() => false,
    };
    if (!canMove) return;

    final delta = event.delta / _viewScale;

    final updated = handle == null
        ? selected.moved(delta.dx, delta.dy)
        : selected.resized(dx: delta.dx, dy: delta.dy, handle: handle);

    _draw.updateElement(updated, index);
  }

  void _abortCreation() {
    _isCreating = false;
    _creationStartPoint = null;
    _previewIndex = null;
    _previewElement = null;
    _draw.creationTemplate = null;
    _dragStartMatrix = null;
    _activePointerId = null;
  }

  void _handlePointerUp(PointerUpEvent event) {
    _pointerCount = max(0, _pointerCount - 1);
    if (_pointerCount == 0) _dragStartMatrix = null;
    if (_activePointerId != null && event.pointer != _activePointerId) return;
    if (_draw.activeTool == .polygon) {
      final point = _transform.toScene(event.localPosition);
      _didHandlePolygonUp(point);

      return _activePointerId = null;
    }

    final pIndex = _resolvePreviewIndex;
    if (_isCreating) {
      final current = pIndex == null ? null : _draw.elements.elementAtOrNull(pIndex);
      if (current == null || pIndex == null) return _abortCreation();

      // If it's too small, just drop it. We consider < 10px as an accidental press.
      if (current.width >= widget._minShapeSize && current.height >= widget._minShapeSize) {
        _draw.replacePreviewAndCommit(current, pIndex);
      } else {
        _draw.dropElementAt(pIndex);
      }

      return _abortCreation();
    }

    if (!_isDragging.value) return;
    final index = _draw.selectedIndex;
    final snapshot = _dragSnapshot;
    final current = _draw.selectedElement;
    if (index != null && snapshot != null && current != null) {
      _draw.commitCommand(index, after: current, before: snapshot);
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
    if (_draw.activeTool == .polygon) {
      _draw.updateCursorPosition(null);

      return _activePointerId = null;
    }

    final pIndex = _resolvePreviewIndex;
    if (_isCreating) {
      if (pIndex != null) _draw.dropElementAt(pIndex);
      _abortCreation();
    } else if (_isDragging.value) {
      _resetDragState();
    }
  }

  void _startDrag({HandlePosition? handle}) {
    _activeHandle = handle;
    _dragSnapshot = _draw.selectedElement;
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
    if (widget._controller != oldWidget._controller) {
      if (oldWidget._controller == null) _draw.dispose();
      _draw = widget._controller ?? DrawController();
    }
    if (widget._minShapeSize != oldWidget._minShapeSize) _closeTolerance = widget._minShapeSize * 2;
    if (oldWidget._image.path == widget._image.path && oldWidget._size == widget._size) return;
    _boardSize = widget._size;
    _didApplyInitialFit = false;
    _fitScale = null;
    _canPan.value = false;
  }

  @override
  void dispose() {
    // Detach the listener before disposing the notifiers it touches, so a
    // stray transform tick can never write to a disposed _canPan/_isDragging.
    _transform.removeListener(_onTransformationChanged);
    _canPan.dispose();
    _isDragging.dispose();
    _transform.dispose();
    // ignore: avoid-disposing-late-fields, it is assigned immediately.
    if (!identical(_draw, widget._controller)) _draw.dispose();
    super.dispose();
  }

  int? get _resolvePreviewIndex {
    final idx = _previewIndex;
    final token = _previewElement;
    if (idx != null) {
      final atIdx = _draw.elements.elementAtOrNull(idx);
      if (token != null && identical(atIdx, token)) return idx;
    }
    if (token == null) return null;
    final resolved = _draw.elements.indexWhere((e) => identical(e, token));

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
              final isInteracting = isDragging || _isCreating || _draw.creationTemplate != null;

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
                panEnabled: !isInteracting && _canPan.value,
                scaleEnabled: widget.scaleEnabled,
                scaleFactor: widget.scaleFactor,
                trackpadScrollCausesScale: widget.trackpadScrollCausesScale,
                transformationController: _transform,
                child: child ?? const SizedBox.shrink(),
              );
            },
            listenable: Listenable.merge([_draw, _canPan]),
          ),
          valueListenable: _isDragging,
          child: FfiImageFile(
            widget._image,
            builder: (displayImage, info, uiImage) => ListenableBuilder(
              builder: (_, image) => Stack(
                alignment: widget.alignment ?? .topStart,
                clipBehavior: widget.clipBehavior,
                fit: widget._fit,
                textDirection: widget._textDirection,
                children: [
                  CustomPaint(
                    foregroundPainter: DrawPainter(
                      _draw.elements,
                      activeTool: _draw.activeTool,
                      backgroundImage: uiImage,
                      creationTemplate: _draw.creationTemplate,
                      cursorPosition: _draw.cursorPosition,
                      handleRadius: _handleRadius,
                      outlineStrokeWidth: _outlineStrokeWidth,
                      pendingVertices: _draw.pendingVertices,
                      selectedIndex: _draw.selectedIndex,
                      tolerance: _closeTolerance / _viewScale,
                    ),
                    size: info.size,
                    willChange: _isDragging.value || _isCreating,
                    child: image,
                  ),
                  if (info != null) ?widget._builder?.call(_draw, info, _transform),
                ],
              ),
              listenable: Listenable.merge([_draw, _isDragging, _transform]),
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
