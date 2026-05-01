import 'dart:ffi';
import 'dart:isolate' show Isolate;

import 'package:ffi/ffi.dart';

import '../constants/draw_constants.dart';
import '../ffi/bindings.dart' as ffi;
import '../ffi/ffi_abi.dart';
import '../ffi/ffi_arena.dart';
import '../ffi/ffi_marshal.dart';
import '../ffi/ffi_result.dart';
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
    required String outputPath, // TODO: Make nullable/optional.
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
    const msgBufCapacity = 256;
    Pointer<Utf8> imageCStr = nullptr;
    Pointer<Utf8> outputCStr = nullptr;
    Pointer<Utf8> fontCStr = nullptr;
    Pointer<FfiArena> arenaPtr = nullptr;
    Pointer<Uint8> msgBuf = nullptr;
    FfiElementBundle? bundle;
    try {
      imageCStr = imagePath.toNativeUtf8();
      outputCStr = outputPath.toNativeUtf8();
      fontCStr = fontPath?.toNativeUtf8() ?? nullptr;
      bundle = FfiMarshal.encodeElements(elements, malloc);
      arenaPtr = malloc<FfiArena>();
      msgBuf = malloc<Uint8>(msgBufCapacity);
      arenaPtr.ref
        ..textBuf = bundle.payloadBufferPtr
        ..textLen = bundle.payloadBufferLen
        ..imageBuf = nullptr
        ..imageLen = 0
        ..errorBuf = msgBuf
        ..errorCap = msgBufCapacity;

      final rawResult = ffi.draw_elements(
        imageCStr,
        outputCStr,
        fontCStr,
        bundle.elementsPtr,
        bundle.count,
        imageQuality,
        arenaPtr,
      );

      if (rawResult.toDomain(msgBuf, msgBufCapacity) case Err(:final code, :final message)) {
        throw RenderException(code, message);
      }
    } finally {
      if (imageCStr != nullptr) malloc.free(imageCStr);
      if (outputCStr != nullptr) malloc.free(outputCStr);
      if (fontCStr != nullptr) malloc.free(fontCStr);
      if (msgBuf != nullptr) malloc.free(msgBuf);
      if (arenaPtr != nullptr) malloc.free(arenaPtr);
      if (bundle != null) {
        malloc.free(bundle.elementsPtr);
        if (bundle.payloadBufferPtr != nullptr) malloc.free(bundle.payloadBufferPtr);
      }
    }
  }
}
