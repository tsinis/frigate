import 'dart:ui' show Color;

import '../../dart/model/draw_element.dart'; // ignore: avoid-importing-entrypoint-exports, not entrypoint.

extension DrawElementExtension on DrawElement {
  /// Converts to `dart:ui` [Color] for rendering only.
  @pragma('dart2js:tryInline')
  @pragma('vm:prefer-inline')
  Color get uiColor => .new(color.argb);
}
