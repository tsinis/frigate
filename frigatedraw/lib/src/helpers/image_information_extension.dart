import 'dart:ui' show Size;

import 'package:frigatebird/frigatebird.dart' show ImageInformation;

/// Extension on nullable [ImageInformation] to easily retrieve Flutter [Size].
extension ImageInformationExtension on ImageInformation? {
  /// The [Size] of the image, or [Size.zero] if null.
  @pragma('dart2js:tryInline')
  @pragma('vm:prefer-inline')
  Size get size => .new(this?.width.toDouble() ?? 0, this?.height.toDouble() ?? 0);
}
