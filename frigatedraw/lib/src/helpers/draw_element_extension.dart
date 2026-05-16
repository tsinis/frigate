import 'dart:ui' show Color, Offset, Rect;

import 'package:frigatebird/frigatebird.dart';

extension DrawElementExtension on DrawElement {
  /// Converts to `dart:ui` [Rect] for rendering only.
  @pragma('dart2js:tryInline')
  @pragma('vm:prefer-inline')
  Rect get rect => .fromLTWH(x, y, width, height);

  /// Converts fill color to `dart:ui` [Color] for rendering only.
  @pragma('dart2js:tryInline')
  @pragma('vm:prefer-inline')
  Color get uiFillColor => .new(fillColor.argb);

  /// Converts outline color to `dart:ui` [Color] for rendering only.
  @pragma('dart2js:tryInline')
  @pragma('vm:prefer-inline')
  Color get uiOutlineColor => .new(outlineColor.argb);

  @pragma('dart2js:tryInline')
  @pragma('vm:prefer-inline')
  DrawElement copyWithDrag({required Offset a, required Offset b}) {
    final shape = Rect.fromPoints(a, b);

    // ignore: prefer-class-destructuring, readability creating a new object just for destructuring.
    return copyWith(height: shape.height, width: shape.width, x: shape.left, y: shape.top);
  }
}
