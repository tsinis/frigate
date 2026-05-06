// ignore_for_file: avoid_print, example code intentionally logs to stdout.

import 'dart:io' show exitCode;

import 'package:frigatebird/frigatebird.dart';

/// Renders a single red rectangle onto `input.jpg` and writes the result to `output.jpg`.
///
/// Run from this folder: `dart run main.dart`. Provide your own `input.jpg` beside it.
Future<void> main() async {
  const elements = <DrawElement>[
    RectElement(
      height: 80,
      outlineColor: FfiColor(0xFFFF0000),
      outlineThickness: 4,
      width: 120,
      x: 20,
      y: 20,
    ),
  ];

  try {
    await RenderImage.run(backgroundPath: 'input.jpg', elements: elements);
    print('wrote output.jpg');
  } on RenderException catch (error) {
    print('render failed: $error');
    exitCode = 1;
  }
}
