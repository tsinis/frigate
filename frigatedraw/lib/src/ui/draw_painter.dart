// ignore_for_file: avoid-long-files, avoid-long-functions, prefer-class-destructuring, use-existing-destructuring, prefer-moving-to-variable

import 'dart:typed_data' show Float64x2;
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:frigatebird/frigatebird.dart';

import '../helpers/draw_element_extension.dart';
import 'draw_tool.dart';

class DrawPainter extends CustomPainter {
  const DrawPainter(
    this.elements, {
    this.activeTool,
    this.backgroundImage,
    this.backgroundTreatment,
    this.creationTemplate,
    this.cursorPosition,
    this.handleBorderWidth = 2.0,
    this.handleRadius = 12.0,
    this.outlineStrokeWidth = 4.0,
    this.pendingVertices,
    this.rotationKnobDistance = 32.0,
    this.rotationKnobRadius = 12.0,
    this.selectedIndex,
    this.shouldShowBackgroundHandles = false,
    this.shouldShowRotationKnob = false,
    this.tolerance = 20.0,
  });

  final DrawTool? activeTool;
  final ui.Image? backgroundImage;

  /// The single image-wide background treatment (full-image blur + tint, with the crop region
  /// dimmed by [_cropDimColor]). Drawn under the shapes; `null` = no treatment.
  final BackgroundElement? backgroundTreatment;
  final DrawElement? creationTemplate;
  final Offset? cursorPosition;
  final List<DrawElement> elements;

  /// Border stroke width (in board pixels) of the selection handles and knob
  /// stem. Passed pre-divided by the view scale from `DrawEditor` so the stroke
  /// stays a constant 2 logical pixels on screen at any zoom level.
  final double handleBorderWidth;
  final double handleRadius;
  final double outlineStrokeWidth;
  final List<Float64x2>? pendingVertices;

  /// Gap (in board pixels) between the shape's top-center handle and the
  /// rotation knob drawn above it.
  final double rotationKnobDistance;

  /// Radius (in board pixels) of the rotation knob.
  final double rotationKnobRadius;
  final int? selectedIndex;

  /// Whether the background tool is armed: draws the crop resize handles (no rotation knob)
  /// around [backgroundTreatment].
  final bool shouldShowBackgroundHandles;

  /// Whether to draw the rotation knob + stem for the selected element.
  final bool shouldShowRotationKnob;
  final double tolerance;

  /// Black fill for selection handles.
  static final _handleFillPaint = Paint()..color = const Color(0xFF000000);

  /// White fill for the rotation knob (inverted vs handles).
  static final _knobFillPaint = Paint()..color = const Color(0xFFFFFFFF);

  /// `Colors.black54` — dims the area outside the crop region so a smaller background rect reads
  /// as a crop (distinct from an ordinary blur/tint rectangle).
  static const _cropDimColor = Color(0x8A000000);

  @override
  void paint(Canvas canvas, Size size) {
    final background = backgroundTreatment;
    // Background treatment renders UNDER the shapes: blur the whole image, then tint it.
    if (background != null) _paintBackgroundTreatment(canvas, size, background);

    for (final element in elements) {
      _paintElement(canvas, size, element, outlineStrokeWidth);
    }

    _paintPolygonPreview(canvas, outlineStrokeWidth);

    // Crop dimming + crop handles render ON TOP of everything else.
    if (background != null) _paintBackgroundOverlay(canvas, size, background);

    final index = selectedIndex;
    if (index == null || index.isNegative || index >= elements.length) return;

    final selected = elements.elementAtOrNull(index);
    if (selected == null) return;

    if (selected is! TextElement && selected.width > 0 && selected.height > 0) {
      final stroke = outlineStrokeWidth;
      final bounds = selected.rect.inflate(stroke * 2);
      _withRotation(
        canvas,
        selected,
        // ignore: avoid-returning-cascades, we want to return the canvas for the cascade.
        () => canvas
          ..saveLayer(bounds, Paint()..blendMode = .difference)
          ..drawRect(
            selected.rect,
            Paint()
              ..color = const Color(0xFFFFFFFF)
              ..style = .stroke
              ..strokeWidth = stroke,
          )
          ..restore(),
      );

      final handleBorderPaint = Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = .stroke
        ..strokeWidth = handleBorderWidth;
      for (final handle in HandlePosition.values) {
        _paintHandle(canvas, handleBorderPaint, selected.handleCenter(handle), handleRadius);
      }

      if (shouldShowRotationKnob) {
        _paintRotationKnob(
          canvas,
          selected,
          borderWidth: handleBorderWidth,
          distance: rotationKnobDistance,
          radius: rotationKnobRadius,
        );
      }
    }
  }

  void _paintPolygonPreview(Canvas canvas, double outlineStroke) {
    final pending = pendingVertices;
    if (activeTool != .polygon || pending == null || pending.isEmpty) return;

    final template = creationTemplate;

    _paintOpenPath(canvas, pending, template, outlineStroke: outlineStroke);
    if (cursorPosition == null) {
      _paintClosingLine(canvas, pending, template, outlineStroke: outlineStroke);
    } else {
      _paintCursorLine(canvas, cursorPosition, pending, template, outlineStroke: outlineStroke);
    }
    _paintVertexHandles(canvas, pending, handleRadius / 3);
    _paintCloseZone(canvas, pending, tolerance);
  }

  static void _paintOpenPath(
    Canvas canvas,
    List<Float64x2> pending,
    DrawElement? template, {
    required double outlineStroke,
  }) {
    if (pending.length < 2) return;

    final isBlur = template != null && template.blur > 0;
    final color = isBlur
        ? const Color(0xFFFFFFFF)
        : (template?.uiOutlineColor ?? const Color(0xFF000000));
    final thickness = template?.outlineThickness.toDouble() ?? 2.0;

    final path = Path();
    final first = pending.firstOrNull;
    if (first == null) return;
    path.moveTo(first.x, first.y);
    for (int i = 1; i < pending.length; i += 1) {
      final v = pending[i];
      path.lineTo(v.x, v.y);
    }

    final bounds = path.getBounds().inflate(outlineStroke * 2);
    canvas
      ..saveLayer(bounds, Paint()..blendMode = .difference)
      ..drawPath(
        path,
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = .stroke
          ..strokeWidth = outlineStroke,
      )
      ..restore()
      ..drawPath(
        path,
        Paint()
          ..color = color
          ..style = .stroke
          ..strokeWidth = thickness,
      );
  }

  static void _paintCursorLine(
    Canvas canvas,
    Offset? cursor,
    List<Float64x2> pending,
    DrawElement? template, {
    required double outlineStroke,
  }) {
    if (cursor == null || pending.isEmpty) return;
    final lastVertex = pending.lastOrNull;
    if (lastVertex == null) return;

    final origin = Offset(lastVertex.x, lastVertex.y);
    final isBlur = template != null && template.blur > 0;
    final color = isBlur
        ? const Color(0xFFFFFFFF)
        : (template?.uiOutlineColor ?? const Color(0xFF000000));
    final thickness = template?.outlineThickness.toDouble() ?? 2.0;

    final bounds = Rect.fromPoints(origin, cursor).inflate(outlineStroke * 2);
    canvas.saveLayer(bounds, Paint()..blendMode = .difference);
    _drawDashedLine(
      canvas,
      origin,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = .stroke
        ..strokeWidth = outlineStroke,
      cursor,
    );
    canvas.restore();

    _drawDashedLine(
      canvas,
      origin,
      Paint()
        ..color = isBlur ? color : color.withValues(alpha: 0.5)
        ..style = .stroke
        ..strokeWidth = thickness,
      cursor,
    );
  }

  static void _paintClosingLine(
    Canvas canvas,
    List<Float64x2> pending,
    DrawElement? template, {
    required double outlineStroke,
  }) {
    if (pending.length < 2) return;

    final firstVertex = pending.firstOrNull;
    final lastVertex = pending.lastOrNull;
    if (firstVertex == null || lastVertex == null) return;

    final origin = Offset(firstVertex.x, firstVertex.y);
    final target = Offset(lastVertex.x, lastVertex.y);
    final isBlur = template != null && template.blur > 0;
    final color = isBlur
        ? const Color(0xFFFFFFFF)
        : (template?.uiOutlineColor ?? const Color(0xFF000000));
    final thickness = template?.outlineThickness.toDouble() ?? 2.0;

    final bounds = Rect.fromPoints(origin, target).inflate(outlineStroke * 2);
    canvas.saveLayer(bounds, Paint()..blendMode = .difference);
    _drawDashedLine(
      canvas,
      origin,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = .stroke
        ..strokeWidth = outlineStroke,
      target,
    );
    canvas.restore();

    _drawDashedLine(
      canvas,
      origin,
      Paint()
        ..color = isBlur ? color : color.withValues(alpha: 0.5)
        ..style = .stroke
        ..strokeWidth = thickness,
      target,
    );
  }

  static void _paintVertexHandles(Canvas canvas, List<Float64x2> pending, double vertexRadius) {
    final paint = Paint()..color = const Color(0xFF000000);
    for (final vertex in pending) {
      canvas.drawCircle(Offset(vertex.x, vertex.y), vertexRadius, paint);
    }
  }

  static void _paintCloseZone(Canvas canvas, List<Float64x2> pending, double zoneRadius) {
    final firstVertex = pending.firstOrNull;
    if (firstVertex == null) return;

    final center = Offset(firstVertex.x, firstVertex.y);
    final bounds = Rect.fromCircle(center: center, radius: zoneRadius).inflate(8);

    canvas
      ..saveLayer(bounds, Paint()..blendMode = .difference)
      ..drawCircle(
        center,
        zoneRadius,
        Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.15),
      )
      ..drawCircle(
        center,
        zoneRadius,
        Paint()
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.4)
          ..style = .stroke
          ..strokeWidth = 1.5,
      )
      ..restore();
  }

  static void _drawDashedLine(Canvas canvas, Offset origin, Paint paint, Offset target) {
    const dashWidth = 4.0;
    const dashSpace = 4.0;
    final Offset(dx: origX, dy: origY) = origin;
    final Offset(dx: destX, dy: destY) = target;
    final diffX = destX - origX;
    final diffY = destY - origY;
    final distance = Offset(diffX, diffY).distance;
    if (distance == 0) return;

    final count = (distance / (dashWidth + dashSpace)).floor();
    final incX = diffX / distance;
    final incY = diffY / distance;

    for (int i = 0; i < count; i += 1) {
      final dashX = origX + incX * i * (dashWidth + dashSpace);
      final dashY = origY + incY * i * (dashWidth + dashSpace);
      canvas.drawLine(
        Offset(dashX, dashY),
        Offset(dashX + incX * dashWidth, dashY + incY * dashWidth),
        paint,
      );
    }
  }

  static void _drawDashedPath(Canvas canvas, Paint paint, Path path) {
    const dashWidth = 4.0;
    const dashSpace = 4.0;
    final dashedPath = Path();
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + dashWidth).clamp(0.0, metric.length);
        dashedPath.addPath(metric.extractPath(distance, end), .zero);
        distance += dashWidth + dashSpace;
      }
    }
    canvas.drawPath(dashedPath, paint);
  }

  /// Renders the background treatment that sits UNDER the shapes: a full-image GPU blur (reusing
  /// [_applyBlur] with a full-canvas clip) followed by the tint fill.
  // ignore: parameters-ordering, canvas must be first by Flutter convention.
  void _paintBackgroundTreatment(Canvas canvas, Size canvasSize, BackgroundElement background) {
    final image = backgroundImage;
    if (background.blur > 0 && image != null) {
      _applyBlur(
        bgImage: image,
        blurSigma: background.blur / 3.0,
        canvas: canvas,
        canvasSize: canvasSize,
        clipPath: Path()..addRect(Offset.zero & canvasSize),
      );
    }

    final tint = background.uiFillColor;
    if (tint.a > 0) canvas.drawRect(Offset.zero & canvasSize, Paint()..color = tint);
  }

  /// Renders the crop affordance ON TOP of everything: dims the area outside the crop rect with
  /// [_cropDimColor], and (when armed) draws the 8 resize handles — never a rotation knob.
  // ignore: parameters-ordering, canvas must be first by Flutter convention.
  void _paintBackgroundOverlay(Canvas canvas, Size canvasSize, BackgroundElement background) {
    final cropRect = background.rect;
    final fullRect = Offset.zero & canvasSize;
    final isFullCover =
        cropRect.left <= fullRect.left &&
        cropRect.top <= fullRect.top &&
        cropRect.right >= fullRect.right &&
        cropRect.bottom >= fullRect.bottom;
    if (!isFullCover) {
      final dimPath = Path()
        ..fillType = .evenOdd
        ..addRect(fullRect)
        ..addRect(cropRect);
      canvas.drawPath(dimPath, Paint()..color = _cropDimColor);
    }

    if (shouldShowBackgroundHandles) {
      final handlePaint = Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = .stroke
        ..strokeWidth = handleBorderWidth;
      for (final handle in HandlePosition.values) {
        _paintHandle(canvas, handlePaint, background.handleCenter(handle), handleRadius);
      }
    }
  }

  static void _applyBlur({
    required ui.Image bgImage,
    required double blurSigma,
    required Canvas canvas,
    required Size canvasSize,
    required Path clipPath,
  }) {
    if (blurSigma <= 0) return;

    final fullRect = Offset.zero & canvasSize;
    final bounds = clipPath.getBounds().intersect(fullRect);
    if (bounds.isEmpty || bounds.width <= 0 || bounds.height <= 0) return;

    final padding = blurSigma * 3.0;
    final paddedBounds = Rect.fromLTRB(
      (bounds.left - padding).clamp(0.0, canvasSize.width),
      (bounds.top - padding).clamp(0.0, canvasSize.height),
      (bounds.right + padding).clamp(0.0, canvasSize.width),
      (bounds.bottom + padding).clamp(0.0, canvasSize.height),
    );

    final scaleX = bgImage.width / canvasSize.width;
    final scaleY = bgImage.height / canvasSize.height; // ignore: avoid-similar-names, it's math.

    final srcRect = Rect.fromLTRB(
      paddedBounds.left * scaleX,
      paddedBounds.top * scaleY,
      paddedBounds.right * scaleX,
      paddedBounds.bottom * scaleY,
    );

    canvas
      ..saveLayer(paddedBounds, Paint())
      ..drawPath(clipPath, Paint()..color = const Color(0xFFFFFFFF))
      ..drawImageRect(
        bgImage,
        srcRect,
        paddedBounds,
        Paint()
          ..blendMode = .srcIn
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: blurSigma,
            sigmaY: blurSigma,
            tileMode: ui.TileMode.clamp,
          ),
      )
      ..restore();
  }

  void _paintElement(
    Canvas canvas,
    Size canvasSize,
    DrawElement element,
    double outlineStroke,
  ) => switch (element) {
    RectElement() => _paintRect(backgroundImage, canvas, canvasSize, element, outlineStroke),
    MaskRegionElement() => _paintRect(backgroundImage, canvas, canvasSize, element, outlineStroke),
    OvalElement() => _paintOval(backgroundImage, canvas, canvasSize, element, outlineStroke),
    PolygonElement() => _paintPolygon(backgroundImage, canvas, canvasSize, element, outlineStroke),
    // TextElement: TODO(tsinis): render in the preview painter.
    // BackgroundElement: never in the element list — rendered by the dedicated background pass in
    // `paint()` (full-image blur/tint + crop affordance), not here.
    TextElement() || BackgroundElement() => null,
  };

  static void _paintPolygon(
    ui.Image? bgImage,
    Canvas canvas,
    Size canvasSize,
    PolygonElement element,
    double outlineStroke,
  ) {
    if (element.vertices.length < 3) return;
    final path = _rotatedPath(element, DrawElementExtension.getPathForPolygon(element));

    final shouldShowBlurPreview = element.blur > 0 && element.uiFillColor.a < 1.0;

    if (shouldShowBlurPreview) {
      if (bgImage == null) {
        canvas.drawPath(path, Paint()..color = const Color(0x44FFFFFF));
      } else {
        _applyBlur(
          bgImage: bgImage,
          blurSigma: element.blur / 3.0,
          canvas: canvas,
          canvasSize: canvasSize,
          clipPath: path,
        );
      }
    }

    final shouldDrawHelperOutline =
        shouldShowBlurPreview && (element.outlineThickness == 0 || element.uiOutlineColor.a == 0);

    if (shouldDrawHelperOutline) {
      _drawDashedPath(
        canvas,
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = .stroke
          ..strokeWidth = 1.5,
        path,
      );
    }

    if (element.uiFillColor.a > 0) canvas.drawPath(path, Paint()..color = element.uiFillColor);

    if (element.outlineThickness > 0 && element.uiOutlineColor.a > 0) {
      final bounds = path.getBounds().inflate(outlineStroke * 2);
      canvas
        ..saveLayer(bounds, Paint()..blendMode = .difference)
        ..drawPath(
          path,
          Paint()
            ..color = const Color(0xFFFFFFFF)
            ..style = .stroke
            ..strokeWidth = outlineStroke,
        )
        ..restore()
        ..drawPath(
          path,
          Paint()
            ..color = element.uiOutlineColor
            ..style = .stroke
            ..strokeWidth = element.outlineThickness.toDouble(),
        );
    }
  }

  static void _paintRect(
    ui.Image? bgImage,
    Canvas canvas,
    Size canvasSize,
    ImmutableDrawElement element,
    double outlineStroke,
  ) {
    final width = element.width;
    final height = element.height;
    if (width <= 0 || height <= 0) return;

    final rect = element.rect;
    final uiFillColor = element.uiFillColor;
    final uiOutlineColor = element.uiOutlineColor;
    final outlineThickness = element.outlineThickness;

    final cornerRadius = switch (element) {
      RectElement(cornerRadius: final rectCornerRadius) => rectCornerRadius,
      MaskRegionElement() || OvalElement() || TextElement() || BackgroundElement() => 0,
    };
    final isRounded = cornerRadius > 0;
    final shouldShowBlurPreview = element.blur > 0 && uiFillColor.a < 1.0;

    if (shouldShowBlurPreview) {
      if (bgImage == null) {
        final fillPaint = Paint()
          ..color = const Color(0x44FFFFFF)
          ..isAntiAlias = isRounded;
        _withRotation(
          canvas,
          element,
          () => isRounded
              ? canvas.drawRRect(
                  RRect.fromRectAndRadius(
                    rect,
                    .circular(cornerRadius.toDouble().clamp(0.0, rect.shortestSide / 2)),
                  ),
                  fillPaint,
                )
              : canvas.drawRect(rect, fillPaint),
        );
      } else {
        final basePath = Path();
        if (isRounded) {
          basePath.addRRect(
            RRect.fromRectAndRadius(
              rect,
              .circular(cornerRadius.toDouble().clamp(0.0, rect.shortestSide / 2)),
            ),
          );
        } else {
          basePath.addRect(rect);
        }
        _applyBlur(
          bgImage: bgImage,
          blurSigma: element.blur / 3.0,
          canvas: canvas,
          canvasSize: canvasSize,
          clipPath: _rotatedPath(element, basePath),
        );
      }
    }

    final shouldDrawHelperOutline =
        shouldShowBlurPreview && (outlineThickness == 0 || uiOutlineColor.a == 0);

    if (shouldDrawHelperOutline) {
      final strokePaint = Paint()
        ..color = const Color(0x88FFFFFF)
        ..style = .stroke
        ..strokeWidth = 1.5
        ..isAntiAlias = isRounded;
      final basePath = Path();
      if (isRounded) {
        basePath.addRRect(
          RRect.fromRectAndRadius(
            rect,
            .circular(cornerRadius.toDouble().clamp(0.0, rect.shortestSide / 2)),
          ),
        );
      } else {
        basePath.addRect(rect);
      }
      _drawDashedPath(canvas, strokePaint, _rotatedPath(element, basePath));
    }

    if (uiFillColor.a > 0) {
      final fillPaint = Paint()
        ..color = uiFillColor
        ..isAntiAlias = isRounded;
      _withRotation(
        canvas,
        element,
        () => isRounded
            ? canvas.drawRRect(
                RRect.fromRectAndRadius(
                  rect,
                  .circular(cornerRadius.toDouble().clamp(0.0, rect.shortestSide / 2)),
                ),
                fillPaint,
              )
            : canvas.drawRect(rect, fillPaint),
      );
    }

    if (outlineThickness > 0 && uiOutlineColor.a > 0) {
      final bounds = rect.inflate(outlineStroke * 2);
      final diffPaint = Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = .stroke
        ..strokeWidth = outlineStroke
        ..isAntiAlias = isRounded;
      final strokePaint = Paint()
        ..color = uiOutlineColor
        ..style = .stroke
        ..strokeWidth = outlineThickness.toDouble()
        ..isAntiAlias = isRounded;

      // ignore: prefer-extracting-function-callbacks, it's the only place.
      _withRotation(canvas, element, () {
        canvas.saveLayer(bounds, Paint()..blendMode = .difference);
        if (isRounded) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              rect,
              .circular(cornerRadius.toDouble().clamp(0.0, rect.shortestSide / 2)),
            ),
            diffPaint,
          );
        } else {
          canvas.drawRect(rect, diffPaint);
        }
        canvas.restore();

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
      });
    }
  }

  static void _paintOval(
    ui.Image? bgImage,
    Canvas canvas,
    Size canvasSize,
    OvalElement element,
    double outlineStroke,
  ) {
    final OvalElement(:height, :outlineThickness, :rect, :uiFillColor, :uiOutlineColor, :width) =
        element;
    if (width <= 0 || height <= 0) return;

    final shouldShowBlurPreview = element.blur > 0 && uiFillColor.a < 1.0;

    if (shouldShowBlurPreview) {
      if (bgImage == null) {
        _withRotation(
          canvas,
          element,
          () => canvas.drawOval(rect, Paint()..color = const Color(0x44FFFFFF)),
        );
      } else {
        final path = Path()..addOval(rect);
        _applyBlur(
          bgImage: bgImage,
          blurSigma: element.blur / 3.0,
          canvas: canvas,
          canvasSize: canvasSize,
          clipPath: _rotatedPath(element, path),
        );
      }
    }

    final shouldDrawHelperOutline =
        shouldShowBlurPreview && (outlineThickness == 0 || uiOutlineColor.a == 0);

    if (shouldDrawHelperOutline) {
      final path = Path()..addOval(rect);
      _drawDashedPath(
        canvas,
        Paint()
          ..color = const Color(0x88FFFFFF)
          ..style = .stroke
          ..strokeWidth = 1.5,
        _rotatedPath(element, path),
      );
    }

    if (uiFillColor.a > 0) {
      _withRotation(canvas, element, () => canvas.drawOval(rect, Paint()..color = uiFillColor));
    }

    if (outlineThickness > 0 && uiOutlineColor.a > 0) {
      final bounds = rect.inflate(outlineStroke * 2);
      _withRotation(
        canvas,
        element,
        // ignore: avoid-returning-cascades, it's a cascade for the canvas.
        () => canvas
          ..saveLayer(bounds, Paint()..blendMode = .difference)
          ..drawOval(
            rect,
            Paint()
              ..color = const Color(0xFFFFFFFF)
              ..style = .stroke
              ..strokeWidth = outlineStroke,
          )
          ..restore()
          ..drawOval(
            rect,
            Paint()
              ..color = uiOutlineColor
              ..style = .stroke
              ..strokeWidth = outlineThickness.toDouble(),
          ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant DrawPainter oldDelegate) {
    if (!identical(oldDelegate.elements, elements)) return true;
    if (oldDelegate.selectedIndex != selectedIndex) return true;
    if (!identical(oldDelegate.pendingVertices, pendingVertices)) return true;
    if (oldDelegate.cursorPosition != cursorPosition) return true;
    if (oldDelegate.activeTool != activeTool) return true;
    if (!identical(oldDelegate.creationTemplate, creationTemplate)) return true;
    if (oldDelegate.tolerance != tolerance) return true;
    if (oldDelegate.backgroundImage != backgroundImage) return true;
    if (oldDelegate.backgroundTreatment != backgroundTreatment) return true;
    if (oldDelegate.shouldShowBackgroundHandles != shouldShowBackgroundHandles) return true;
    if (oldDelegate.handleBorderWidth != handleBorderWidth) return true;
    if (oldDelegate.handleRadius != handleRadius) return true;
    if (oldDelegate.outlineStrokeWidth != outlineStrokeWidth) return true;
    if (oldDelegate.shouldShowRotationKnob != shouldShowRotationKnob) return true;
    if (oldDelegate.rotationKnobRadius != rotationKnobRadius) return true;
    if (oldDelegate.rotationKnobDistance != rotationKnobDistance) return true;

    return false;
  }

  @override
  bool hitTest(Offset position) {
    final index = selectedIndex;
    if (index != null && index >= 0 && index < elements.length) {
      final select = elements.elementAtOrNull(index);
      if (select != null && select.hitTestHandle(position, handleRadius) != null) return true;
    }

    for (int i = elements.length - 1; i >= 0; i -= 1) {
      final target = elements.elementAtOrNull(i);
      final isHit = target?.isPointOnShape(position) ?? false;
      if (isHit) return true;
    }

    return false;
  }

  // ignore: parameters-ordering, canvas must be first by Flutter convention.
  static void _paintHandle(Canvas canvas, Paint borderPaint, Offset center, double radius) {
    canvas
      ..drawCircle(center, radius, _handleFillPaint)
      ..drawCircle(center, radius, borderPaint);
  }

  /// Runs [render] with the canvas rotated about [element]'s center, matching the
  /// backend's pivot. A no-op fast path when the element is un-rotated keeps the
  /// un-rotated render byte-identical (and the primitive-type tests green).
  static void _withRotation(Canvas canvas, DrawElement element, VoidCallback render) {
    if (element.rotation == 0) return render();

    canvas
      ..save()
      ..translate(element.centerX, element.centerY)
      ..rotate(element.rotationRadians)
      ..translate(-element.centerX, -element.centerY);
    render();
    canvas.restore();
  }

  /// Returns [path] rotated about [element]'s center. Used for the blur clip so
  /// the background is sampled axis-aligned (rotating the canvas would spin the
  /// sampled pixels, not just the clip region).
  static Path _rotatedPath(DrawElement element, Path path) {
    if (element.rotation == 0) return path;
    final matrix = Matrix4.identity()
      ..translateByDouble(element.centerX, element.centerY, 0, 1)
      ..rotateZ(element.rotationRadians)
      ..translateByDouble(-element.centerX, -element.centerY, 0, 1);

    return path.transform(matrix.storage);
  }

  /// Draws the rotation knob (and the stem connecting it to the top-center
  /// handle), following the element's rotation. [radius] and [distance] are in
  /// board pixels. The knob is inverted vs the resize handles: white fill with
  /// a black border so it is visually distinct.
  static void _paintRotationKnob(
    Canvas canvas,
    DrawElement element, {
    required double borderWidth,
    required double distance,
    required double radius,
  }) {
    final stem = element.handleCenter(.topCenter);
    final knob = element.rotationKnobOffset(distance);
    canvas
      ..drawLine(
        stem,
        knob,
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = .stroke
          ..strokeWidth = borderWidth,
      )
      ..drawCircle(knob, radius, _knobFillPaint)
      ..drawCircle(
        knob,
        radius,
        Paint()
          ..color = const Color(0xFF000000)
          ..style = .stroke
          ..strokeWidth = borderWidth,
      );
  }
}
