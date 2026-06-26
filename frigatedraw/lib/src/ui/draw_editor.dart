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
    this._enableRotation = true,
    this._fit = StackFit.loose,
    this._handleRadius = defaultHandleRadius,
    this._minShapeSize = defaultMinShapeSize,
    this._rotationKnobDistance = defaultRotationKnobDistance,
    this._rotationSnap = defaultRotationSnap,
    this._size,
    this._textDirection,
    super.alignment,
    super.boundaryMargin = const .all(.infinity),
    super.clipBehavior,
    super.interactionEndFrictionCoefficient,
    super.key,
    super.maxScale = defaultMaxScale,
    super.minScale = 1 / 2,
    super.onInteractionEnd,
    super.onInteractionStart,
    super.onInteractionUpdate,
    super.panAxis,
    super.scaleEnabled,
    super.scaleFactor,
    super.trackpadScrollCausesScale,
  }) : assert(_handleRadius > 0, 'handleRadius ($_handleRadius) must be positive.'),
       assert(_minShapeSize > 0, 'minShapeSize ($_minShapeSize) must be positive.'),
       super(child: const SizedBox.shrink(), constrained: false);

  /// The on-screen radius of the selection/resize handles, in logical pixels.
  ///
  /// `21.0` gives a 42 px diameter — a comfortable touch target. The handles
  /// keep this size at every zoom level and image size (see [_handleRadius] in
  /// the state), so they never scale into or out of usability.
  static const defaultHandleRadius = 21.0;

  /// The default minimum drawable shape size, in board pixels. Independent of
  /// [defaultHandleRadius]: handles are an on-screen size while this is a
  /// document-space size, so the two no longer share a scale.
  static const defaultMinShapeSize = 10.0;

  /// The default on-screen distance (logical pixels) from the shape's top-center
  /// handle center to the rotation knob center. Must exceed
  /// `2 × defaultHandleRadius` to avoid the knob and handle overlapping.
  static const defaultRotationKnobDistance = 56.0;

  /// The default rotation snap increment, in degrees. A rotation that lands
  /// within a few degrees of a multiple of this value is snapped to it; `0`
  /// disables snapping.
  static const defaultRotationSnap = 15;

  /// The default maximum zoom scale for the canvas.
  static const defaultMaxScale = 12.0;

  final DrawEditorBuilder? _builder;
  final DrawController? _controller;

  /// Whether elements can be rotated (two-finger gesture + desktop knob).
  // ignore: prefer-boolean-prefixes, reads naturally as the public `enableRotation` flag.
  final bool _enableRotation;

  /// The on-screen radius (in logical pixels) of the selection/resize handles.
  /// Held constant across zoom and image size by dividing out the view scale
  /// (see the `_handleRadius` getter in the state).
  ///
  /// Defaults to [defaultHandleRadius].
  final double _handleRadius;
  final File _image;
  final double _minShapeSize;

  /// On-screen gap (logical pixels) between the top-center handle and the
  /// rotation knob. Held constant across zoom like [_handleRadius].
  final double _rotationKnobDistance;

  /// Rotation snap increment in degrees; `0` disables snapping.
  final int _rotationSnap;

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
      ..add(DoubleProperty('_handleRadius', _handleRadius))
      ..add(DoubleProperty('_minShapeSize', _minShapeSize))
      ..add(FlagProperty('_enableRotation', ifTrue: 'rotation enabled', value: _enableRotation))
      ..add(DoubleProperty('_rotationKnobDistance', _rotationKnobDistance))
      ..add(IntProperty('_rotationSnap', _rotationSnap))
      ..add(EnumProperty<StackFit>('_fit', _fit))
      ..add(EnumProperty<TextDirection?>('_textDirection', _textDirection))
      ..add(DoubleProperty('_size.height', _size?.height))
      ..add(DoubleProperty('_size.width', _size?.width));
  }
}

class _DrawEditorState extends State<DrawEditor> {
  /// Guards against pan re-enabling from float jitter at exactly fit scale.
  static const _panScaleEpsilon = 1e-3;

  /// Max distance (degrees) from a snap multiple within which rotation snaps.
  static const _rotationSnapThreshold = 3;
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

  /// Live scene-space positions of every active pointer, keyed by pointer id.
  /// Insertion order is stable, so "the first two" stay consistent within a
  /// two-finger gesture.
  final _pointers = <int, Offset>{};

  /// True while dragging the rotation knob (single-finger rotate).
  bool _isRotating = false;

  /// True while a two-finger rotate + scale + move of the selected element is
  /// in progress (so the [InteractiveViewer] zoom is suppressed).
  bool _isTwoFingerTransform = false;

  // Baseline captured when a two-finger transform starts or re-baselines; the
  // per-frame transform is computed relative to these.
  Offset _gestureStartFocal = .zero;
  double _gestureStartAngle = 0;
  double _gestureStartDistance = 0;
  DrawElement? _transformStartElement;

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
  double get _viewScale {
    final storage = _transform.value.storage;
    final scaleXComponent = storage.firstOrNull ?? 0;
    final rotateYComponent = storage.elementAtOrNull(1) ?? 0;
    final skewZComponent = storage.elementAtOrNull(2) ?? 0;
    final scale = sqrt(
      scaleXComponent * scaleXComponent +
          rotateYComponent * rotateYComponent +
          skewZComponent * skewZComponent,
    );

    return scale < 0.01 ? 1.0 : scale;
  }

  /// The handle radius expressed in board pixels. Because the painter is the
  /// [InteractiveViewer]'s child, board pixels are multiplied by the view scale
  /// on screen — so dividing the desired on-screen radius by [_viewScale] keeps
  /// handles a constant size at any zoom level or image size. Mirrors the
  /// `tolerance: _closeTolerance / _viewScale` treatment of the polygon close
  /// zone below.
  double get _handleRadius => widget._handleRadius / _viewScale;

  /// Rotation knob radius in board pixels — same on-screen size as the handles.
  double get _rotationKnobRadius => widget._handleRadius / _viewScale;

  /// Rotation knob distance in board pixels, held constant on screen.
  double get _rotationKnobDistance => widget._rotationKnobDistance / _viewScale;

  /// Handle border stroke width in board pixels — `2.0` on-screen at any zoom.
  double get _handleBorderWidth => 2 / _viewScale;

  /// Whether the currently selected element can be rotated/dragged as a shape.
  bool get _isSelectionRotatable {
    final selected = _draw.selectedElement;

    return widget._enableRotation && selected != null && selected is! TextElement;
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

  /// When the background tool is armed via `selectTool(.background)` (which has no image size),
  /// the treatment slot starts empty. Once the board size is known, lazily instantiate a
  /// full-image treatment (post-frame, so it never calls `notifyListeners` during build).
  void _ensureBackgroundSized() {
    if (!_draw.isBackgroundMode || _draw.backgroundTreatment != null) return;
    final board = _boardSize;
    if (board == null || board.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_draw.isBackgroundMode || _draw.backgroundTreatment != null) return;
      _draw.enterBackgroundMode(board);
    });
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
    final point = _transform.toScene(event.localPosition);
    _trackPointer(event.pointer, point);
    if (_pointerCount > 1) {
      _dragStartMatrix = null;
      _maybeStartTwoFingerTransform(); // Upgrade an in-progress shape drag to rotate+scale+move.
    }
    if (_activePointerId != null) return;

    final pointerId = event.pointer;

    // In background mode only the crop handles are interactive; anything else falls through to
    // pan/zoom (no shape creation/selection).
    if (_draw.isBackgroundMode) return _didHandleBackgroundGesture(point, pointerId);
    if (_didHandlePolygonTool(point, pointerId)) return;
    if (_didHandleCreationTool(point, pointerId)) return;
    if (_didHandleRotationKnob(point, pointerId)) return;
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

  /// Background-mode pointer-down: claims the pointer when it lands on a crop handle (resize) or
  /// inside the crop body (move), so a press fully outside stays available for pan/zoom.
  void _didHandleBackgroundGesture(Offset point, int pointerId) {
    final background = _draw.backgroundTreatment;
    if (background == null) return;

    final handle = background.hitTestInsetHandle(point, _handleRadius, _handleRadius);
    if (handle == null && !background.isPointOnShape(point)) return;

    if (_pointerCount == 1) _dragStartMatrix = _transform.value;
    _activePointerId = pointerId;
    _startDrag(handle: handle, snapshot: background);
  }

  /// Moves (body drag) or resizes (handle drag) the crop rect, clamped to the image bounds.
  void _dragBackground(PointerMoveEvent event) {
    final background = _draw.backgroundTreatment;
    if (background == null) return;
    final handle = _activeHandle;
    final updated = _resizeOrMove(event.localDelta / _viewScale, background, handle: handle);
    if (updated is! BackgroundElement) return;
    _draw.updateBackgroundTreatment(_clampToBoard(updated, isMove: handle == null));
  }

  /// Clamps a crop rect to the image bounds. A body move ([isMove]) slides the rect back inside
  /// while preserving its size; a handle resize clamps each edge but never collapses the rect below
  /// [DrawEditor._minShapeSize] (a zero/negative crop would fail the Rust export with `invalidArg`).
  BackgroundElement _clampToBoard(BackgroundElement element, {required bool isMove}) {
    final board = _boardSize;
    if (board == null || board.isEmpty) return element;

    if (isMove) {
      final maxX = (board.width - element.width).clamp(0.0, board.width);
      final maxY = (board.height - element.height).clamp(0.0, board.height);

      return element.copyWith(x: element.x.clamp(0.0, maxX), y: element.y.clamp(0.0, maxY));
    }

    final minWidth = widget._minShapeSize.clamp(0.0, board.width);
    final minHeight = widget._minShapeSize.clamp(0.0, board.height);
    final left = element.x.clamp(0.0, (board.width - minWidth).clamp(0.0, board.width));
    final top = element.y.clamp(0.0, (board.height - minHeight).clamp(0.0, board.height));
    final right = (element.x + element.width).clamp(left + minWidth, board.width);
    final bottom = (element.y + element.height).clamp(top + minHeight, board.height);

    return element.copyWith(height: bottom - top, width: right - left, x: left, y: top);
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
    for (int i = allElements.length - 1; !i.isNegative; i -= 1) {
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

  bool _didHandleRotationKnob(Offset point, int pointerId) {
    if (!_isSelectionRotatable) return false;
    final selected = _draw.selectedElement;
    if (selected == null) return false;
    if (!selected.isPointOnRotationKnob(_rotationKnobDistance, _rotationKnobRadius, point)) {
      return false;
    }

    if (_pointerCount == 1) _dragStartMatrix = _transform.value;
    _activePointerId = pointerId;
    _isRotating = true;
    _startDrag();

    return true;
  }

  /// When a second finger lands during a shape drag, switch from a single-finger
  /// move/resize to a two-finger rotate + uniform-scale + move anchored to the
  /// gesture's focal point.
  void _maybeStartTwoFingerTransform() {
    if (!_isSelectionRotatable || !_isDragging.value || _pointers.length < 2) return;
    _isRotating = false;
    _activeHandle = null;
    _isTwoFingerTransform = true;
    _resetTransformBaseline();
  }

  /// Captures the focal point, angle and distance of the first two pointers plus
  /// the element snapshot, so per-frame deltas are measured from a stable base.
  void _resetTransformBaseline() {
    final points = _pointers.values.toList(growable: false);
    final first = points.firstOrNull;
    final second = points.elementAtOrNull(1);
    if (first == null || second == null) return;
    _gestureStartFocal = (first + second) / 2;
    _gestureStartAngle = atan2(second.dy - first.dy, second.dx - first.dx);
    _gestureStartDistance = (second - first).distance;
    _transformStartElement = _draw.selectedElement;
  }

  void _applyTwoFingerTransform() {
    final index = _draw.selectedIndex;
    final startElement = _transformStartElement;
    final points = _pointers.values.toList(growable: false);
    final first = points.firstOrNull;
    final second = points.elementAtOrNull(1);
    if (index == null || startElement == null || first == null || second == null) return;

    final focal = (first + second) / 2;
    final distance = (second - first).distance;
    final rotationDelta = atan2(second.dy - first.dy, second.dx - first.dx) - _gestureStartAngle;
    final scaleFactor = _gestureStartDistance == 0 ? 1.0 : distance / _gestureStartDistance;
    final translation = focal - _gestureStartFocal;

    final transformed = startElement.transformedBy(
      (x: _gestureStartFocal.dx, y: _gestureStartFocal.dy),
      rotationDelta,
      minSize: widget._minShapeSize,
      scaleFactor: scaleFactor,
      translation: (x: translation.dx, y: translation.dy),
    );
    final snapped = _snapDegrees(transformed.rotation);
    _draw.updateElement(
      snapped == transformed.rotation ? transformed : transformed.copyWith(rotation: snapped),
      index,
    );
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_pointers.containsKey(event.pointer)) {
      _trackPointer(event.pointer, _transform.toScene(event.localPosition));
    }

    if (_isTwoFingerTransform) return _applyTwoFingerTransform();
    if (_activePointerId != null && event.pointer != _activePointerId) return;

    if (_draw.isBackgroundMode && _isDragging.value) return _dragBackground(event);

    if (_isRotating) {
      final rotateIndex = _draw.selectedIndex;
      final rotateTarget = _draw.selectedElement;
      if (rotateIndex == null || rotateTarget == null) return;
      final scene = _transform.toScene(event.localPosition);
      final degrees = _snapDegrees(rotateTarget.angleToPoint((x: scene.dx, y: scene.dy)));

      return _draw.updateElement(rotateTarget.copyWith(rotation: degrees), rotateIndex);
    }

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

    if (_isDragging.value) _dragSelectedShape(event);
  }

  /// Moves or (handle-)resizes the selected shape for a single-finger drag.
  void _dragSelectedShape(PointerMoveEvent event) {
    final index = _draw.selectedIndex;
    final selected = _draw.selectedElement;
    if (index == null || selected == null) return;
    // TODO(tsinis): Enable TextElement movement once _paintElement supports text bounds/handles.
    final canMove = switch (selected) {
      RectElement() || OvalElement() || PolygonElement() || MaskRegionElement() => true,
      // BackgroundElement is never a list selection — it is edited via the background-mode path.
      TextElement() || BackgroundElement() => false,
    };
    if (!canMove) return;
    _draw.updateElement(
      _resizeOrMove(event.localDelta / _viewScale, selected, handle: _activeHandle),
      index,
    );
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
    _untrackPointer(event.pointer);
    _pointerCount = max(0, _pointerCount - 1);
    if (_pointerCount == 0) {
      _dragStartMatrix = null;
      _clearPointers();
    }

    if (_isTwoFingerTransform && _pointerCount >= 1) return _downgradeToSingleFinger();

    if (_activePointerId != null && event.pointer != _activePointerId) return;

    if (_draw.isBackgroundMode && _isDragging.value) {
      final snapshot = _dragSnapshot;
      final current = _draw.backgroundTreatment;
      if (snapshot is BackgroundElement && current != null) {
        _draw.commitBackgroundTreatment(after: current, before: snapshot);
      }

      return _resetDragState();
    }

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
    _untrackPointer(event.pointer);
    _pointerCount = max(0, _pointerCount - 1);
    if (_pointerCount == 0) {
      _dragStartMatrix = null;
      _clearPointers();
    }

    if (_isTwoFingerTransform && _pointerCount >= 1) return _downgradeToSingleFinger();
    if (_activePointerId != null && event.pointer != _activePointerId) return;
    if (_draw.isBackgroundMode && _isDragging.value) return _resetDragState();
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

  void _startDrag({HandlePosition? handle, DrawElement? snapshot}) {
    _activeHandle = handle;
    _dragSnapshot = snapshot ?? _draw.selectedElement;
    _isDragging.value = true;
  }

  /// Applies [delta] to [element]: moves it when [handle] is null, or resizes/rotates it when a
  /// specific handle is given. Used by both shape drags and background crop drags.
  DrawElement _resizeOrMove(Offset delta, DrawElement element, {HandlePosition? handle}) =>
      handle == null
      ? element.moved(delta.dx, delta.dy)
      : element.rotatedResized(
          dx: delta.dx,
          dy: delta.dy,
          handle: handle,
          minSize: widget._minShapeSize,
        );

  // `_pointers` is a private live buffer; in-place mutation is intentional.
  void _trackPointer(int pointer, Offset scene) {
    // ignore: avoid-collection-mutating-methods, intentional live-buffer write.
    _pointers[pointer] = scene;
  }

  void _untrackPointer(int pointer) {
    // ignore: avoid-collection-mutating-methods,avoid-ignoring-return-values, drop the lifted pointer.
    _pointers.remove(pointer);
  }

  void _clearPointers() {
    // ignore: avoid-collection-mutating-methods, reset the live buffer once all fingers are up.
    _pointers.clear();
  }

  /// Ends a two-finger transform when a finger lifts, handing control to the
  /// remaining pointer as a plain single-finger move (the snapshot from drag
  /// start is preserved for one commit; the next move re-reads the live delta).
  void _downgradeToSingleFinger() {
    _isTwoFingerTransform = false;
    _activeHandle = null;
    _activePointerId = _pointers.keys.firstOrNull;
    if (_pointerCount == 1) _dragStartMatrix = _transform.value;
  }

  /// Snaps [degrees] to the nearest snap-increment multiple when it lands within
  /// [_rotationSnapThreshold]; otherwise leaves it free. `0` disables snapping.
  int _snapDegrees(int degrees) {
    final snap = widget._rotationSnap;
    if (snap <= 0) return degrees;
    final nearest = (degrees / snap).round() * snap;
    if ((degrees - nearest).abs() > _rotationSnapThreshold) return degrees;
    final normalized = nearest % 360;

    return normalized < 0 ? normalized + 360 : normalized;
  }

  void _resetDragState() {
    _activeHandle = null;
    _dragSnapshot = null;
    _isDragging.value = false;
    _isRotating = false;
    _isTwoFingerTransform = false;
    _transformStartElement = null;
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
      _ensureBackgroundSized();

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
                // Suppress canvas zoom while dragging a shape so a second finger
                // rotates/scales the element instead of the board. Flipping with
                // `isDragging` (a notifier) means scale is already off before the
                // second finger lands — no gesture-arena race.
                scaleEnabled: widget.scaleEnabled && !isDragging,
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
                      backgroundTreatment: _draw.backgroundTreatment,
                      creationTemplate: _draw.creationTemplate,
                      cursorPosition: _draw.cursorPosition,
                      handleBorderWidth: _handleBorderWidth,
                      handleRadius: _handleRadius,
                      outlineStrokeWidth: _outlineStrokeWidth,
                      pendingVertices: _draw.pendingVertices,
                      rotationKnobDistance: _rotationKnobDistance,
                      rotationKnobRadius: _rotationKnobRadius,
                      selectedIndex: _draw.selectedIndex,
                      shouldShowBackgroundHandles: _draw.isBackgroundMode,
                      shouldShowRotationKnob: _isSelectionRotatable,
                      tolerance: _closeTolerance / _viewScale,
                    ),
                    size: info.size,
                    willChange: _isDragging.value || _isCreating,
                    child: image,
                  ),
                  if (widget._builder case final builder? when info != null)
                    SizedBox.fromSize(size: info.size, child: builder(_draw, info, _transform)),
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
