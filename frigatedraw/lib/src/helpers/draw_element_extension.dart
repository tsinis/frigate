import 'dart:ui' show Color;

import 'package:frigatebird/frigatebird.dart';

extension DrawElementExtension on DrawElement {
  /// Converts to `dart:ui` [Color] for rendering only.
  @pragma('dart2js:tryInline')
  @pragma('vm:prefer-inline')
  Color get uiColor => .new(color.argb);
}
