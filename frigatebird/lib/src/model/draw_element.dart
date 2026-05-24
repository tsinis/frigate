import 'dart:typed_data';

import 'ffi_color.dart';

part 'rect_element.dart';
part 'text_element.dart';
part 'oval_element.dart';
part 'immutable_draw_element.dart';
part 'polygon_element.dart';
part 'mask_region_element.dart';

/// Base for all drawable elements.
///
/// Coordinates and sizes are in **document-space pixels**.
sealed class DrawElement {
  const DrawElement({
    required this.height,
    required this.width,
    required this.x,
    required this.y,
    this.blur = 0,
    this.fillColor = FfiColor.black,
    this.outlineColor = FfiColor.black,
    this.outlineThickness = 2,
    this.rotation = 0,
  }) : assert(blur >= 0 && blur <= 255, 'blur must be in 0..255'),
       assert(
         outlineThickness >= 0 && outlineThickness <= 255,
         'outlineThickness must be in 0..255',
       );

  final double x;
  final double y;
  final double width;
  final double height;
  final int blur;
  final int rotation;
  final FfiColor fillColor;
  final FfiColor outlineColor;
  final int outlineThickness;

  DrawElement copyWith({
    int? blur,
    FfiColor? fillColor,
    double? height,
    FfiColor? outlineColor,
    int? outlineThickness,
    int? rotation,
    double? width,
    double? x,
    double? y,
  });
}
