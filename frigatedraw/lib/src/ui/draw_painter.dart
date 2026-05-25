// ignore_for_file: prefer-moving-to-variable, avoid-long-functions, avoid-explicit-type-declaration, use-existing-destructuring, prefer-class-destructuring, avoid-long-files, prefer-shorthands-with-enums, format-comment
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
    this.creationTemplate,
    this.cursorPosition,
    this.pendingVertices,
    this.selectedIndex,
    this.tolerance = 20.0,
  });

  static const double handleRadius = DrawElementExtension.handleRadius;

  final List<DrawElement> elements;
  final int? selectedIndex;
  final List<Float64x2>? pendingVertices;
  final Offset? cursorPosition;
  final DrawTool? activeTool;
  final double tolerance;
  final DrawElement? creationTemplate;
  final ui.Image? backgroundImage;

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
      _paintElement(canvas, size, element);
    }

    _paintPolygonPreview(canvas);

    final index = selectedIndex;
    if (index == null || index.isNegative || index >= elements.length) return;

    final selected = elements.elementAtOrNull(index);
    if (selected == null) return;

    if (selected is! TextElement && selected.width > 0 && selected.height > 0) {
      // Draw straight thin lines between holders (4 pixels hardcoded, inverted to background)
      final bounds = selected.rect.inflate(8);
      canvas
        ..saveLayer(bounds, Paint()..blendMode = .difference)
        ..drawRect(
          selected.rect,
          Paint()
            ..color = const Color(0xFFFFFFFF)
            ..style = .stroke
            ..strokeWidth = 4,
        )
        ..restore();

      for (final handle in HandlePosition.values) {
        _paintHandle(canvas, selected.handleCenter(handle));
      }
    }
  }

  void _paintPolygonPreview(Canvas canvas) {
    final pending = pendingVertices;
    if (activeTool != .polygon || pending == null || pending.isEmpty) return;

    final template = creationTemplate;
    final bool isBlur = template != null && template.blur > 0;

    _paintOpenPath(canvas, pending, template, isBlur: isBlur);
    if (cursorPosition == null) {
      _paintClosingLine(canvas, pending, template, isBlur: isBlur);
    } else {
      _paintCursorLine(canvas, cursorPosition, pending, template, isBlur: isBlur);
    }
    _paintVertexHandles(canvas, pending);
    _paintCloseZone(canvas, pending, tolerance);
  }

  static void _paintOpenPath(
    Canvas canvas,
    List<Float64x2> pending,
    DrawElement? template, {
    required bool isBlur,
  }) {
    if (pending.length < 2) return;

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

    final bounds = path.getBounds().inflate(8);
    canvas
      ..saveLayer(bounds, Paint()..blendMode = .difference)
      ..drawPath(
        path,
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = .stroke
          ..strokeWidth = 4.0
          ..isAntiAlias = true,
      )
      ..restore()
      ..drawPath(
        path,
        Paint()
          ..color = color
          ..style = .stroke
          ..strokeWidth = thickness
          ..isAntiAlias = true,
      );
  }

  static void _paintCursorLine(
    Canvas canvas,
    Offset? cursor,
    List<Float64x2> pending,
    DrawElement? template, {
    required bool isBlur,
  }) {
    if (cursor == null || pending.isEmpty) return;
    final lastVertex = pending.lastOrNull;
    if (lastVertex == null) return;

    final origin = Offset(lastVertex.x, lastVertex.y);
    final color = isBlur
        ? const Color(0xFFFFFFFF)
        : (template?.uiOutlineColor ?? const Color(0xFF000000));
    final thickness = template?.outlineThickness.toDouble() ?? 2.0;

    final bounds = Rect.fromPoints(origin, cursor).inflate(8);
    canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.difference);
    _drawDashedLine(
      canvas,
      origin,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = .stroke
        ..strokeWidth = 4.0
        ..isAntiAlias = true,
      cursor,
    );
    canvas.restore();

    _drawDashedLine(
      canvas,
      origin,
      Paint()
        ..color = isBlur ? color : color.withValues(alpha: 0.5)
        ..style = .stroke
        ..strokeWidth = thickness
        ..isAntiAlias = true,
      cursor,
    );
  }

  static void _paintClosingLine(
    Canvas canvas,
    List<Float64x2> pending,
    DrawElement? template, {
    required bool isBlur,
  }) {
    if (pending.length < 2) return;

    final firstVertex = pending.firstOrNull;
    final lastVertex = pending.lastOrNull;
    if (firstVertex == null || lastVertex == null) return;

    final origin = Offset(firstVertex.x, firstVertex.y);
    final target = Offset(lastVertex.x, lastVertex.y);
    final color = isBlur
        ? const Color(0xFFFFFFFF)
        : (template?.uiOutlineColor ?? const Color(0xFF000000));
    final thickness = template?.outlineThickness.toDouble() ?? 2.0;

    final bounds = Rect.fromPoints(origin, target).inflate(8);
    canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.difference);
    _drawDashedLine(
      canvas,
      origin,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = .stroke
        ..strokeWidth = 4.0
        ..isAntiAlias = true,
      target,
    );
    canvas.restore();

    _drawDashedLine(
      canvas,
      origin,
      Paint()
        ..color = isBlur ? color : color.withValues(alpha: 0.5)
        ..style = .stroke
        ..strokeWidth = thickness
        ..isAntiAlias = true,
      target,
    );
  }

  static void _paintVertexHandles(Canvas canvas, List<Float64x2> pending) {
    final paint = Paint()..color = const Color(0xFF000000);
    for (final vertex in pending) {
      canvas.drawCircle(Offset(vertex.x, vertex.y), 4, paint);
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
        Paint()
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.15)
          ..style = .fill,
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

    final double padding = blurSigma * 3.0;
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
          ..blendMode = BlendMode.srcIn
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: blurSigma,
            sigmaY: blurSigma,
            tileMode: ui.TileMode.clamp,
          ),
      )
      ..restore();
  }

  void _paintElement(Canvas canvas, Size canvasSize, DrawElement element) => switch (element) {
    RectElement() => _paintRect(backgroundImage, canvas, canvasSize, element),
    MaskRegionElement() => _paintRect(backgroundImage, canvas, canvasSize, element),
    OvalElement() => _paintOval(backgroundImage, canvas, canvasSize, element),
    PolygonElement() => _paintPolygon(backgroundImage, canvas, canvasSize, element),
    TextElement() => null, // TODO(tsinis): render TextElement in the preview painter.
  };

  static void _paintPolygon(
    ui.Image? bgImage,
    Canvas canvas,
    Size canvasSize,
    PolygonElement element,
  ) {
    if (element.vertices.length < 3) return;
    final path = DrawElementExtension.getPathForPolygon(element);

    final bool shouldShowBlurPreview = element.blur > 0 && element.uiFillColor.a < 1.0;

    if (shouldShowBlurPreview) {
      if (bgImage == null) {
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0x44FFFFFF)
            ..style = .fill
            ..isAntiAlias = true,
        );
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

    final bool shouldDrawHelperOutline =
        shouldShowBlurPreview && (element.outlineThickness == 0 || element.uiOutlineColor.a == 0);

    if (shouldDrawHelperOutline) {
      _drawDashedPath(
        canvas,
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = .stroke
          ..strokeWidth = 1.5
          ..isAntiAlias = true,
        path,
      );
    }

    if (element.uiFillColor.a > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..color = element.uiFillColor
          ..style = .fill
          ..isAntiAlias = true,
      );
    }

    if (element.outlineThickness > 0 && element.uiOutlineColor.a > 0) {
      final bounds = path.getBounds().inflate(8);
      canvas
        ..saveLayer(bounds, Paint()..blendMode = .difference)
        ..drawPath(
          path,
          Paint()
            ..color = const Color(0xFFFFFFFF)
            ..style = .stroke
            ..strokeWidth = 4.0
            ..isAntiAlias = true,
        )
        ..restore()
        ..drawPath(
          path,
          Paint()
            ..color = element.uiOutlineColor
            ..style = .stroke
            ..strokeWidth = element.outlineThickness.toDouble()
            ..isAntiAlias = true,
        );
    }
  }

  static void _paintRect(
    ui.Image? bgImage,
    Canvas canvas,
    Size canvasSize,
    ImmutableDrawElement element,
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
      MaskRegionElement() || OvalElement() || TextElement() => 0,
    };
    final isRounded = cornerRadius > 0;
    final bool shouldShowBlurPreview = element.blur > 0 && uiFillColor.a < 1.0;

    if (shouldShowBlurPreview) {
      if (bgImage == null) {
        final fillPaint = Paint()
          ..color = const Color(0x44FFFFFF)
          ..style = .fill
          ..isAntiAlias = isRounded;
        if (isRounded) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              rect,
              .circular(cornerRadius.toDouble().clamp(0.0, rect.shortestSide / 2)),
            ),
            fillPaint,
          );
        } else {
          canvas.drawRect(rect, fillPaint);
        }
      } else {
        final path = Path();
        if (isRounded) {
          path.addRRect(
            RRect.fromRectAndRadius(
              rect,
              .circular(cornerRadius.toDouble().clamp(0.0, rect.shortestSide / 2)),
            ),
          );
        } else {
          path.addRect(rect);
        }
        _applyBlur(
          bgImage: bgImage,
          blurSigma: element.blur / 3.0,
          canvas: canvas,
          canvasSize: canvasSize,
          clipPath: path,
        );
      }
    }

    final bool shouldDrawHelperOutline =
        shouldShowBlurPreview && (outlineThickness == 0 || uiOutlineColor.a == 0);

    if (shouldDrawHelperOutline) {
      final strokePaint = Paint()
        ..color = const Color(0x88FFFFFF)
        ..style = .stroke
        ..strokeWidth = 1.5
        ..isAntiAlias = isRounded;
      final path = Path();
      if (isRounded) {
        path.addRRect(
          RRect.fromRectAndRadius(
            rect,
            .circular(cornerRadius.toDouble().clamp(0.0, rect.shortestSide / 2)),
          ),
        );
      } else {
        path.addRect(rect);
      }
      _drawDashedPath(canvas, strokePaint, path);
    }

    if (uiFillColor.a > 0) {
      final fillPaint = Paint()
        ..color = uiFillColor
        ..style = .fill
        ..isAntiAlias = isRounded;
      if (isRounded) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            rect,
            .circular(cornerRadius.toDouble().clamp(0.0, rect.shortestSide / 2)),
          ),
          fillPaint,
        );
      } else {
        canvas.drawRect(rect, fillPaint);
      }
    }

    if (outlineThickness > 0 && uiOutlineColor.a > 0) {
      final strokePaint = Paint()
        ..color = uiOutlineColor
        ..style = .stroke
        ..strokeWidth = outlineThickness.toDouble()
        ..isAntiAlias = isRounded;
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
    }
  }

  static void _paintOval(ui.Image? bgImage, Canvas canvas, Size canvasSize, OvalElement element) {
    final OvalElement(:height, :outlineThickness, :rect, :uiFillColor, :uiOutlineColor, :width) =
        element;
    if (width <= 0 || height <= 0) return;

    final bool shouldShowBlurPreview = element.blur > 0 && uiFillColor.a < 1.0;

    if (shouldShowBlurPreview) {
      if (bgImage == null) {
        canvas.drawOval(
          rect,
          Paint()
            ..color = const Color(0x44FFFFFF)
            ..style = .fill
            ..isAntiAlias = true,
        );
      } else {
        final path = Path()..addOval(rect);
        _applyBlur(
          bgImage: bgImage,
          blurSigma: element.blur / 3.0,
          canvas: canvas,
          canvasSize: canvasSize,
          clipPath: path,
        );
      }
    }

    final bool shouldDrawHelperOutline =
        shouldShowBlurPreview && (outlineThickness == 0 || uiOutlineColor.a == 0);

    if (shouldDrawHelperOutline) {
      final path = Path()..addOval(rect);
      _drawDashedPath(
        canvas,
        Paint()
          ..color = const Color(0x88FFFFFF)
          ..style = .stroke
          ..strokeWidth = 1.5
          ..isAntiAlias = true,
        path,
      );
    }

    if (uiFillColor.a > 0) {
      canvas.drawOval(
        rect,
        Paint()
          ..color = uiFillColor
          ..style = .fill
          ..isAntiAlias = true,
      );
    }

    if (outlineThickness > 0 && uiOutlineColor.a > 0) {
      canvas.drawOval(
        rect,
        Paint()
          ..color = uiOutlineColor
          ..style = .stroke
          ..strokeWidth = outlineThickness.toDouble()
          ..isAntiAlias = true,
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

    return false;
  }

  @override
  bool hitTest(Offset position) {
    final index = selectedIndex;
    if (index != null && index >= 0 && index < elements.length) {
      final select = elements.elementAtOrNull(index);
      if (select != null && select.hitTestHandle(position) != null) return true;
    }

    for (int i = elements.length - 1; i >= 0; i -= 1) {
      final target = elements.elementAtOrNull(i);
      final isHit = target?.isPointOnShape(position) ?? false;
      if (isHit) return true;
    }

    return false;
  }

  static void _paintHandle(Canvas canvas, Offset center) {
    canvas
      ..drawCircle(center, handleRadius, _handleFillPaint)
      ..drawCircle(center, handleRadius, _handleBorderPaint);
  }
}
