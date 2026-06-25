part of 'draw_element.dart';

/// A single, image-wide background treatment: a **crop** region (`x`/`y`/`width`/`height`),
/// a background **blur** radius, and an optional **tint** ([fillColor]).
///
/// Unlike the shape elements it is never placed in the editor's element list — it lives in a
/// dedicated slot and is passed to the Rust `compose` call as the *treatment* (not as a drawn
/// shape). The canonical render pipeline is: blur → tint → shapes → sharp foreground → crop.
///
/// Rotation is meaningless for a global treatment, so it is forced to `0` (the background tool
/// shows resize handles only, no rotation knob). Outline is forced transparent / zero — a
/// background treatment never strokes a border. Defaults are a no-op treatment: `blur: 0`,
/// `fillColor: transparent`.
@pragma('vm:deeply-immutable')
final class BackgroundElement extends ImmutableDrawElement {
  const BackgroundElement({
    required super.height,
    required super.width,
    required super.x,
    required super.y,
    super.blur = 0,
    super.fillColor = .transparent,
  }) : super(outlineColor: .transparent, outlineThickness: 0);

  /// A full-image treatment covering [width] × [height] with no blur and no tint — the default
  /// the editor instantiates when the background tool is first armed.
  const BackgroundElement.cover({required double height, required double width})
    : this(height: height, width: width, x: 0, y: 0);

  static const zero = BackgroundElement(height: 0, width: 0, x: 0, y: 0);

  @override
  BackgroundElement copyWith({
    int? blur,
    FfiColor? fillColor,
    double? height,
    FfiColor? outlineColor,
    int? outlineThickness,
    int? rotation,
    double? width,
    double? x,
    double? y,
  }) {
    assert(rotation == null || rotation == 0, 'BackgroundElement rotation must be 0');
    assert(
      outlineColor == null || outlineColor == .transparent,
      'BackgroundElement outlineColor must be transparent',
    );
    assert(
      outlineThickness == null || outlineThickness == 0,
      'BackgroundElement outlineThickness must be 0',
    );

    return .new(
      blur: blur ?? this.blur,
      fillColor: fillColor ?? this.fillColor,
      height: height ?? this.height,
      width: width ?? this.width,
      x: x ?? this.x,
      y: y ?? this.y,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackgroundElement &&
          other.x == x &&
          other.y == y &&
          other.width == width &&
          other.height == height &&
          other.blur == blur &&
          other.fillColor == fillColor;

  @override
  int get hashCode => Object.hash(x, y, width, height, blur, fillColor);

  @override
  String toString() =>
      'BackgroundElement(x: $x, y: $y, width: $width, height: $height, blur: $blur, '
      'fillColor: $fillColor)';
}
