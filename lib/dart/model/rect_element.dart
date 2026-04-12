part of 'draw_element.dart';

@pragma('vm:deeply-immutable')
final class RectElement extends DrawElement {
  const RectElement({
    required this.height,
    required this.width,
    required super.x,
    required super.y,
    super.color,
    super.strokeWidth,
  });

  final double width;
  final double height;

  @override
  String toString() =>
      'RectElement(x: $x, y: $y, width: $width, height: $height, color: $color, '
      'strokeWidth: $strokeWidth)';

  @override
  RectElement copyWith({
    FfiColor? color,
    double? height,
    double? strokeWidth,
    double? width,
    double? x,
    double? y,
  }) => .new(
    color: color ?? this.color,
    height: height ?? this.height,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    width: width ?? this.width,
    x: x ?? this.x,
    y: y ?? this.y,
  );
}
