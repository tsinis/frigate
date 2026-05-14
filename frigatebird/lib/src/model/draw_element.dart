import 'ffi_color.dart';

part 'rect_element.dart';
part 'text_element.dart';
part 'oval_element.dart';

/// Base for all drawable elements.
///
/// Coordinates and sizes are in **document-space pixels**.
@pragma('vm:deeply-immutable')
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
