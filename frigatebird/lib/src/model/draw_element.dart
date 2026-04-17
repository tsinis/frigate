import '../ffi/ffi_element_type.dart';
import 'ffi_color.dart';

part 'rect_element.dart';
part 'text_element.dart';

/// Base for all drawable elements that cross the FFI boundary.
///
/// Coordinates and sizes are in **document-space pixels** — Dart and Rust agree on units
/// end-to-end, no normalization step.
///
/// Every subtype has a [width] and [height] so the FFI layer can treat them uniformly. For shapes
/// with a natural bounding rect (rectangle, future circle/triangle) both fields are exposed in the
/// subtype constructor. For `TextElement`, `height` is the font em-box height (what callers think
/// of as "font size"); `width` is fixed at 0 because our current text renderer has no bounded-box
/// wrapping.
///
/// [blur], [outlineThickness] and [rotation] are `int` (pixels / degrees) rather than `double`:
/// sub-pixel precision adds nothing useful for these fields, and `int` stays in Dart's SMI tag
/// range (no boxing per instance).
///
/// [elementType] is a polymorphic getter — each subtype returns its own tag, so the FFI serializer
/// never needs `is` checks to write the discriminator.
@pragma('vm:deeply-immutable')
sealed class DrawElement {
  const DrawElement({
    required this.height,
    required this.width,
    required this.x,
    required this.y,
    this.blur = 0,
    this.fillColor = FfiColor.black,
    this.outlineColor = FfiColor.transparent,
    this.outlineThickness = 0,
    this.rotation = 0,
    this.shapeParam = 0,
  });

  /// Document-space x in pixels.
  final double x;

  /// Document-space y in pixels.
  final double y;

  /// Document-space width in pixels. Zero is legal (text has no bounded width today).
  final double width;

  /// Document-space height in pixels. For `TextElement` this is the font em-box height.
  final double height;

  /// Blur radius in pixels. Zero means no blur.
  final int blur;

  /// Fill color in 0xAARRGGBB packed form. Alpha encodes opacity — there is no separate opacity
  /// field anywhere.
  final FfiColor fillColor;

  /// Outline color in 0xAARRGGBB packed form. Ignored when [outlineThickness] is zero.
  final FfiColor outlineColor;

  /// Outline thickness in pixels. Zero means no outline.
  final int outlineThickness;

  /// Rotation in degrees — **visual clockwise on screen** (a positive value spins the element
  /// the way a clock's second hand moves). Rust converts to radians and applies the rotation
  /// in y-down screen coords, which is mathematically counter-clockwise; the result looks
  /// clockwise to the user. Callers reason about the visual direction, not the math.
  final int rotation;

  /// **Implementation detail** — do not read or write this field from outside the package.
  ///
  /// Subtypes write it via `super(...)` from a typed constructor parameter (e.g.
  /// `RectElement.cornerRadius`); the FFI serializer reads it on the way out to Rust. Each
  /// subtype interprets the same wire slot differently, which is exactly why there is no
  /// generic public API for it — callers should reach for the subtype-specific typed alias.
  ///
  /// Sealed-class enforcement: only [RectElement] and [TextElement] can pass it through
  /// `super`, so external code cannot mis-set it.
  ///
  /// `int` for the same SMI-tag-friendliness reason as [outlineThickness] / [blur].
  // TODO(tsinis): add meta annotation to enforce that only the intended subtypes can set this via `super` once that is supported.
  final int shapeParam;

  /// FFI discriminator for this element type. Implemented polymorphically by each subtype so the
  /// serializer doesn't need to runtime-check the subtype just to set the tag.
  FfiElementType get elementType;

  DrawElement copyWith({
    int? blur,
    FfiColor? fillColor,
    FfiColor? outlineColor,
    int? outlineThickness,
    int? rotation,
    double? x,
    double? y,
  });
}
