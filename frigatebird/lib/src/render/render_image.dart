import 'dart:ffi';
import 'dart:isolate' show Isolate;

import 'package:ffi/ffi.dart';

import '../constants/draw_constants.dart';
import '../ffi/bindings.dart' as ffi;
import '../ffi/ffi_abi.dart';
import '../ffi/serialized_elements.dart';
import '../helpers/extensions/ffi/draw_element_list_ffi.dart';
import '../model/draw_element.dart';
import 'render_exception.dart';
import 'render_image_args.dart';

/// Entry point for compositing [DrawElement]s onto an image and writing the result to disk.
///
/// Class with statics rather than a top-level function so the package's render API has a
/// discoverable namespace (`RenderImage.` autocompletes the entry point) instead of leaking
/// `renderImage` into every file that imports the package root.
sealed class RenderImage {
  /// Render [elements] onto the image at [imagePath] and write the composited result to
  /// [outputPath]. Mixed element kinds (rectangles, text, …) are dispatched in Rust by the
  /// `FfiElement.elementType` discriminator.
  ///
  /// File I/O is performed entirely in Rust — Dart only assembles the FFI struct array.
  /// Validation is handled with [assert] (debug-only invariants) plus [int.clamp] (graceful in
  /// release); missing/corrupted files surface as a [RenderException] from Rust.
  ///
  /// [fontPath] is required when [elements] contains any [TextElement]. Output format is
  /// dispatched by the extension of [outputPath]: `.png` (lossless, alpha preserved,
  /// [imageQuality] ignored) or `.jpg`/`.jpeg` (alpha flattened, [imageQuality] applies).
  ///
  /// **[imageQuality] is clamped, not validated.** Debug builds assert the value lies in
  /// `[DrawConstants.minImageQuality, DrawConstants.maxImageQuality]`; release builds silently
  /// clamp to that range. A caller who passes `-5` in release gets `0` (lowest quality); a
  /// caller who passes `150` gets `100`. Rationale: this API already raises [RenderException]
  /// for genuine failures from Rust — throwing on a stylistic parameter out-of-range would
  /// force every caller to guard a range that has only two well-known correct values
  /// (a slider min/max).
  ///
  /// Runs in a background isolate via [Isolate.run] — never blocks the calling thread.
  static Future<void> run({
    required List<DrawElement> elements,
    required String imagePath,
    required String outputPath,
    String? fontPath,
    int imageQuality = DrawConstants.defaultImageQuality,
  }) {
    // Fails loudly if the Dart VM struct layout has drifted from Rust `#[repr(C)]`. Debug-only,
    // but CI runs in debug and the mismatch would corrupt every subsequent read.
    FfiAbi.assertElement();
    assert(
      !elements.any((e) => e is TextElement) || fontPath != null,
      'fontPath must be supplied when elements contains a TextElement',
    );
    assert(
      imageQuality >= DrawConstants.minImageQuality &&
          imageQuality <= DrawConstants.maxImageQuality,
      'imageQuality must be in [${DrawConstants.minImageQuality}, '
      '${DrawConstants.maxImageQuality}], got $imageQuality',
    );

    final clampedQuality = imageQuality.clamp(
      DrawConstants.minImageQuality,
      DrawConstants.maxImageQuality,
    );

    return Isolate.run(
      () => _runWorker(
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

  static void _runWorker(RenderImageArgs args) {
    final RenderImageArgs(:elements, :fontPath, :imagePath, :imageQuality, :outputPath) = args;
    // Allocations live inside the try so that a partial failure (e.g. OOM on the second string)
    // still hits the `finally` and releases anything that already succeeded. Each cleanup call
    // null-guards independently because any of these four allocations can throw.
    Pointer<Utf8> imageCStr = nullptr;
    Pointer<Utf8> outputCStr = nullptr;
    Pointer<Utf8> fontCStr = nullptr;
    SerializedElements? serialized;
    try {
      imageCStr = imagePath.toNativeUtf8();
      outputCStr = outputPath.toNativeUtf8();
      fontCStr = fontPath?.toNativeUtf8() ?? nullptr;
      serialized = elements.toNative(malloc);
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
      if (imageCStr != nullptr) malloc.free(imageCStr);
      if (outputCStr != nullptr) malloc.free(outputCStr);
      if (fontCStr != nullptr) malloc.free(fontCStr);
      serialized?.free();
    }
  }
}
