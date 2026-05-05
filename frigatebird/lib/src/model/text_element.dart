part of 'draw_element.dart';

@pragma('vm:deeply-immutable')
final class TextElement extends DrawElement {
  const TextElement({
    required this.text,
    required super.x,
    required super.y,
    super.blur, // TODO: No [blur] for the text!
    super.fillColor,
    super.rotation,
    this.fontId = 0,
    double fontSize = defaultFontSize,
  }) : super(height: fontSize, width: 0);

  static const defaultFontSize = 24.0;

  final String text;
  final int fontId;

  // The getter name `fontSize` matches the public API; the backing field is `height`,
  // inherited from [DrawElement] which reuses height for font size in text elements.
  // ignore: match-getter-setter-field-names
  double get fontSize => height;

  @override
  TextElement copyWith({
    int? blur,
    FfiColor? fillColor,
    int? fontId,
    double? fontSize,
    double? height,
    int? rotation,
    String? text,
    double? width,
    double? x,
    double? y,
  }) => .new(
    blur: blur ?? this.blur,
    fillColor: fillColor ?? this.fillColor,
    fontId: fontId ?? this.fontId,
    fontSize: fontSize ?? height ?? this.fontSize,
    rotation: rotation ?? this.rotation,
    text: text ?? this.text,
    x: x ?? this.x,
    y: y ?? this.y,
  );

  @override
  String toString() =>
      'TextElement(x: $x, y: $y, text: "$text", fontSize: $fontSize, '
      'fillColor: $fillColor, rotation: $rotation, blur: $blur, fontId: $fontId)';
}
