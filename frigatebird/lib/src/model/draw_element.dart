import 'ffi_color.dart';

part 'rect_element.dart';
part 'text_element.dart';

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
    this.rotation = 0,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final int rotation;
  final FfiColor fillColor;
  final int blur;

  DrawElement copyWith({
    int? blur,
    FfiColor? fillColor,
    double? height,
    int? rotation,
    double? width,
    double? x,
    double? y,
  });
}
