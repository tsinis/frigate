import 'dart:ui' show Color;

import 'package:frigatebird/frigatebird.dart';

extension OvalElementExtension on OvalElement {
  /// Converts outline color to `dart:ui` [Color] for rendering only.
  @pragma('dart2js:tryInline')
  @pragma('vm:prefer-inline')
  Color get uiOutlineColor => .new(outlineColor.argb);
}
