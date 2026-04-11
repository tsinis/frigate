import 'dart:ui' show Rect;

import '../frigate_draw_dart.dart' show RectElement;

extension RectElementExtension on RectElement {
  /// Converts to `dart:ui` [Rect] for rendering only.
  @pragma('dart2js:tryInline')
  @pragma('vm:prefer-inline')
  Rect get rect => .fromLTWH(x, y, width, height);
}
