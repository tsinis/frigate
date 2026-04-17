part of 'draw_element.dart';

/// A text overlay drawn onto the image.
///
/// Text-specific surface: [text], [fontSize], `fillColor`, [rotation]. The base `width`/`height`
/// fields are reused — `height` is the font em-box (== [fontSize]) and `width` is fixed at 0
/// because our current text renderer does not wrap inside a bounded box. Outline / blur inherit
/// from [DrawElement] but default to off; the current text renderer ignores them (they will be
/// wired up when the unified styling layer lands).
@pragma('vm:deeply-immutable')
final class TextElement extends DrawElement {
  const TextElement({
    required this.text,
    required super.x,
    required super.y,
    super.fillColor,
    double fontSize = defaultFontSize,
    super.rotation,
  }) : super(height: fontSize, width: 0);

  /// Default font size in pixels. Chosen to render legibly on a typical phone/desktop screen
  /// without feeling over-sized.
  static const defaultFontSize = 24.0;

  final String text;

  /// Alias over inherited [height] — text uses the base `height` field as its em-box height;
  /// `fontSize` is the name callers expect for that concept.
  // ignore: match-getter-setter-field-names, intentional alias: fontSize -> height.
  double get fontSize => height;

  @override
  FfiElementType get elementType => .text;

  @override
  String toString() =>
      'TextElement(x: $x, y: $y, text: "$text", fontSize: $fontSize, '
      'fillColor: $fillColor, rotation: $rotation)';

  @override
  TextElement copyWith({
    int? blur,
    FfiColor? fillColor,
    double? fontSize,
    FfiColor? outlineColor,
    int? outlineThickness,
    int? rotation,
    String? text,
    double? x,
    double? y,
  }) => .new(
    fillColor: fillColor ?? this.fillColor,
    fontSize: fontSize ?? this.fontSize,
    rotation: rotation ?? this.rotation,
    text: text ?? this.text,
    x: x ?? this.x,
    y: y ?? this.y,
  );
}
