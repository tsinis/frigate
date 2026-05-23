import 'dart:ui' show Color, Offset, Rect;

import 'package:frigatebird/frigatebird.dart';

import '../ui/draw_tool.dart';

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
    final Rect(:height, :left, :top, :width) = .fromPoints(a, b);

    return copyWith(height: height, width: width, x: left, y: top);
  }

  DrawTool get tool => switch (this) {
    TextElement() => .text,
    RectElement() => .rectangle,
    OvalElement() => .oval,
    PolygonElement() => .polygon,
  };
}
