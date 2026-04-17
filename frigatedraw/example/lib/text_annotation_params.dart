import 'package:flutter/foundation.dart';

/// Value bundle produced by the text annotation dialog; `null` when the user cancels.
@immutable
@pragma('vm:deeply-immutable')
final class TextAnnotationParams {
  const TextAnnotationParams({required this.fontSize, required this.rotation, required this.text});

  final double fontSize;
  final int rotation;
  final String text;
}
