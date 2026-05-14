part of 'draw_element.dart';

@pragma('vm:deeply-immutable')
final class TextElement extends DrawElement {
  const TextElement({
    required this.text,
    required super.x,
    required super.y,
    super.blur, // Is in the wire struct (TextPayload.blur) but not yet applied at render time.
    super.fillColor,
    super.outlineColor,
    super.outlineThickness,
    super.rotation,
    super.height = defaultFontSize, // A.K.A fontSize.
    this.fontId = 0,
  }) : super(width: 0);

  static const defaultFontSize = 24.0;

  final String text;
  final int fontId;

  /// The getter name [fontSize] matches the public API; the backing field is [height],
  /// inherited from [DrawElement] which reuses height for font size in text elements.
  // ignore: match-getter-setter-field-names, see dartdoc comment.
  double get fontSize => height;

  @override
  TextElement copyWith({
    int? blur,
    FfiColor? fillColor,
    int? fontId,
    double? height, // A.K.A fontSize.
    FfiColor? outlineColor,
    int? outlineThickness,
    int? rotation,
    String? text,
    double? width, // Ignored right now since TextElement computes width dynamically.
    double? x,
    double? y,
  }) => .new(
    blur: blur ?? this.blur,
    fillColor: fillColor ?? this.fillColor,
    fontId: fontId ?? this.fontId,
    height: height ?? this.height,
    outlineColor: outlineColor ?? this.outlineColor,
    outlineThickness: outlineThickness ?? this.outlineThickness,
    rotation: rotation ?? this.rotation,
    text: text ?? this.text,
    x: x ?? this.x,
    y: y ?? this.y,
  );

  @override
  String toString() =>
      'TextElement(x: $x, y: $y, text: "$text", height: $height, '
      'fillColor: $fillColor, rotation: $rotation, blur: $blur, fontId: $fontId)';
}
