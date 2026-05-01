import 'dart:ui' show Color, Rect;

import 'package:frigatebird/frigatebird.dart' show RectElement;

extension RectElementExtension on RectElement {
  /// Converts to `dart:ui` [Rect] for rendering only.
  @pragma('dart2js:tryInline')
  @pragma('vm:prefer-inline')
  Rect get rect => .fromLTWH(x, y, width, height);

  /// Converts outline color to `dart:ui` [Color] for rendering only.
  ///
  /// Lives here rather than on `DrawElement` because outline properties are
  /// exclusive to rectangles — accessing it on other element types would be meaningless.
  @pragma('dart2js:tryInline')
  @pragma('vm:prefer-inline')
  Color get uiOutlineColor => .new(outlineColor.argb);
}
