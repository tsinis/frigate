import 'dart:ui' show Color;

import 'package:frigatebird/frigatebird.dart';

extension DrawElementExtension on DrawElement {
  /// Converts fill color to `dart:ui` [Color] for rendering only.
  @pragma('dart2js:tryInline')
  @pragma('vm:prefer-inline')
  Color get uiFillColor => .new(fillColor.argb);

  /// Converts outline color to `dart:ui` [Color] for rendering only.
  @pragma('dart2js:tryInline')
  @pragma('vm:prefer-inline')
  Color get uiOutlineColor {
    final element = this;

    return .new(element is RectElement ? element.outlineColor.argb : FfiColor.black.argb);
  }
}
