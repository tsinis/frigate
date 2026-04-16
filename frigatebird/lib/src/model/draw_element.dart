import 'ffi_color.dart';

part 'rect_element.dart';

/// Base for all drawable shapes sent across the FFI boundary.
///
/// Subclass for each shape type (rect, circle, polygon, etc.).
@pragma('vm:deeply-immutable')
sealed class DrawElement {
  const DrawElement({
    required this.x,
    required this.y,
    this.color = const FfiColor.from(),
    this.strokeWidth = 2.0,
  });

  final double x;
  final double y;
  final double strokeWidth;
  final FfiColor color;

  DrawElement copyWith({FfiColor? color, double? strokeWidth, double? x, double? y});
}
