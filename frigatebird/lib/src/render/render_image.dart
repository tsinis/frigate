// `renderImage` is a free function by design: it mirrors the FFI-facing top-level binding it
// wraps and carries no per-instance state.
// ignore_for_file: prefer-static-class
import 'dart:ffi';
import 'dart:isolate' show Isolate;

import 'package:ffi/ffi.dart';

import '../constants/draw_constants.dart';
import '../ffi/bindings.dart' as ffi;
import '../ffi/serialized_elements.dart';
import '../helpers/extensions/ffi/draw_element_list_ffi.dart';
import '../model/draw_element.dart';
import 'render_exception.dart';
import 'render_image_args.dart';

/// Render [elements] onto the image at [imagePath] and write the composited result to
/// [outputPath]. Mixed element kinds (rectangles, text, …) are dispatched in Rust by the
/// `FfiElement.elementType` discriminator.
///
/// File I/O is performed entirely in Rust — Dart only assembles the FFI struct array. Validation
/// is handled with [assert] (debug-only invariants) plus [int.clamp] (graceful in release);
/// missing/corrupted files surface as a [RenderException] from Rust.
///
/// [fontPath] is required when [elements] contains any [TextElement]. Output format is dispatched
/// by the extension of [outputPath]: `.png` (lossless, alpha preserved, [imageQuality] ignored) or
/// `.jpg`/`.jpeg` (alpha flattened, [imageQuality] applies).
///
/// Runs in a background isolate via [Isolate.run] — never blocks the calling thread.
Future<void> renderImage({
  required List<DrawElement> elements,
  required String imagePath,
  required String outputPath,
  String? fontPath,
  int imageQuality = DrawConstants.defaultImageQuality,
}) {
  assert(
    !elements.any((e) => e is TextElement) || fontPath != null,
    'fontPath must be supplied when elements contains a TextElement',
  );
  assert(
    imageQuality >= DrawConstants.minImageQuality && imageQuality <= DrawConstants.maxImageQuality,
    'imageQuality must be in [${DrawConstants.minImageQuality}, '
    '${DrawConstants.maxImageQuality}], got $imageQuality',
  );

  final clampedQuality = imageQuality.clamp(
    DrawConstants.minImageQuality,
    DrawConstants.maxImageQuality,
  );

  return Isolate.run(
    () => _runRender(
      RenderImageArgs(
        elements: elements,
        fontPath: fontPath,
        imagePath: imagePath,
        imageQuality: clampedQuality,
        outputPath: outputPath,
      ),
    ),
  );
}

void _runRender(RenderImageArgs args) {
  final RenderImageArgs(:elements, :fontPath, :imagePath, :imageQuality, :outputPath) = args;
  final imageCStr = imagePath.toNativeUtf8();
  final outputCStr = outputPath.toNativeUtf8();
  final fontCStr = fontPath?.toNativeUtf8() ?? nullptr;
  final serialized = elements.toNative(malloc);
  try {
    final SerializedElements(:count, elementsPtr: elementArray, :textBufferLen, :textBufferPtr) =
        serialized;
    final code = ffi.render_image(
      imageCStr,
      outputCStr,
      fontCStr,
      elementArray,
      count,
      textBufferPtr,
      textBufferLen,
      imageQuality,
    );
    if (code != 0) throw RenderException.fromCode(code);
  } finally {
    malloc
      ..free(imageCStr)
      ..free(outputCStr);
    if (fontCStr != nullptr) malloc.free(fontCStr);
    serialized.free();
  }
}
