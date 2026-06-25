// ignore_for_file: prefer-class-destructuring
import 'dart:ffi';
import 'dart:isolate' show Isolate;

import 'package:ffi/ffi.dart';

import '../constants/draw_constants.dart';
import '../ffi/bindings.dart' as ffi;
import '../ffi/ffi_abi.dart';
import '../ffi/ffi_arena_handle.dart';
import '../ffi/ffi_element.dart';
import '../ffi/ffi_marshal.dart';
import '../ffi/ffi_result_unit.dart';
import '../model/draw_element.dart';
import 'render_exception.dart';
import 'render_image_args.dart';
import 'resize_filter.dart';

/// Entry point for compositing [DrawElement]s onto an image and writing the result to disk.
///
/// Class with statics rather than a top-level function so the package's render API has a
/// discoverable namespace (`RenderImage.` autocompletes the entry point) instead of leaking
/// `renderImage` into every file that imports the package root.
sealed class RenderImage {
  /// Render [elements] onto the image at [backgroundPath] and write the composited result to
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
    required String backgroundPath,
    required List<DrawElement> elements,
    String? fontPath,
    String? outputPath,
    int imageQuality = DrawConstants.defaultImageQuality,
  }) {
    // Fails loudly if the Dart VM struct layout has drifted from Rust `#[repr(C)]`.
    // Fatal error — mismatch would corrupt every subsequent read.
    FfiAbi.assertAll();
    if (backgroundPath.isEmpty) {
      throw const RenderException(.invalidArg, 'backgroundPath cannot be empty');
    }
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
          backgroundPath: backgroundPath,
          elements: elements,
          fontPath: fontPath,
          imageQuality: clampedQuality,
          outputPath: outputPath,
        ),
      ),
    );
  }

  static void _runWorker(RenderImageArgs args) {
    final RenderImageArgs(:backgroundPath, :elements, :fontPath, :imageQuality, :outputPath) = args;
    Pointer<Utf8> backgroundCStr = nullptr;
    Pointer<Utf8> outputCStr = nullptr;
    Pointer<Utf8> fontCStr = nullptr;
    FfiElementsHandle? handle;
    try {
      backgroundCStr = backgroundPath.toNativeUtf8(allocator: calloc);
      outputCStr = outputPath?.toNativeUtf8(allocator: calloc) ?? nullptr;
      fontCStr = fontPath?.toNativeUtf8(allocator: calloc) ?? nullptr;
      handle = FfiMarshal.encodeElements(elements, calloc);

      final code = ffi.draw_elements(
        backgroundCStr,
        outputCStr,
        fontCStr,
        handle.elementsPtr,
        handle.count,
        imageQuality,
        handle.arena.ptr,
      );

      final domainResult = handle.arena.readResult(code);
      if (domainResult is ErrUnit) throw RenderException(domainResult.code, domainResult.message);
    } finally {
      if (backgroundCStr != nullptr) calloc.free(backgroundCStr);
      if (outputCStr != nullptr) calloc.free(outputCStr);
      if (fontCStr != nullptr) calloc.free(fontCStr);
      handle?.free();
    }
  }

  /// Background-treatment + foreground composite: the unified background tool's save path.
  ///
  /// Reads [backgroundPath], then applies the canonical pipeline (original image space, crop last):
  /// full-image **blur** → **tint** → draw [elements] → composite the sharp **foreground** →
  /// **crop**, writing the result to [outputPath] (or overwriting [backgroundPath] when null).
  ///
  /// - [backgroundTreatment] (a [BackgroundElement]) carries the crop rect (`x/y/width/height`),
  ///   the full-image background `blur`, and the `fillColor` tint. Null = no treatment, in which
  ///   case this behaves like [run] (just shapes).
  /// - [foregroundPath] is an alpha PNG composited sharp at (0,0) **after** shapes and **before**
  ///   crop; it must match the background's pixel dimensions (clipped, never scaled).
  /// - [fontPath] is required when [elements] contains any [TextElement].
  ///
  /// Output format is dispatched by [outputPath]'s extension. [imageQuality] is clamped (see [run]).
  /// Runs in a background isolate via [Isolate.run].
  // ignore: parameters-ordering, required param 'backgroundPath' precedes all optional params, then optional params are alphabetical.
  static Future<void> compose({
    required String backgroundPath,
    BackgroundElement? backgroundTreatment,
    List<DrawElement> elements = const [],
    String? fontPath,
    String? foregroundPath,
    int imageQuality = DrawConstants.defaultImageQuality,
    String? outputPath,
  }) {
    FfiAbi.assertAll();
    if (backgroundPath.isEmpty) {
      throw const RenderException(.invalidArg, 'backgroundPath cannot be empty');
    }
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
      () => _runComposeWorker(
        backgroundPath: backgroundPath,
        backgroundTreatment: backgroundTreatment,
        elements: elements,
        fontPath: fontPath,
        foregroundPath: foregroundPath,
        imageQuality: clampedQuality,
        outputPath: outputPath,
      ),
    );
  }

  // ignore: avoid-long-parameter-list, mirrors the compose FFI surface 1:1.
  static void _runComposeWorker({
    required String backgroundPath,
    required BackgroundElement? backgroundTreatment,
    required List<DrawElement> elements,
    required String? fontPath,
    required String? foregroundPath,
    required int imageQuality,
    required String? outputPath,
  }) {
    Pointer<Utf8> backgroundCStr = nullptr;
    Pointer<Utf8> outputCStr = nullptr;
    Pointer<Utf8> fontCStr = nullptr;
    Pointer<Utf8> foregroundCStr = nullptr;
    Pointer<RectanglePayload> treatmentPtr = nullptr;
    FfiElementsHandle? handle;
    try {
      backgroundCStr = backgroundPath.toNativeUtf8(allocator: calloc);
      outputCStr = outputPath?.toNativeUtf8(allocator: calloc) ?? nullptr;
      fontCStr = fontPath?.toNativeUtf8(allocator: calloc) ?? nullptr;
      foregroundCStr = foregroundPath?.toNativeUtf8(allocator: calloc) ?? nullptr;

      final bgTreatment = backgroundTreatment;
      if (bgTreatment != null) {
        treatmentPtr = calloc<RectanglePayload>()
          ..ref.x = bgTreatment.x
          ..ref.y = bgTreatment.y
          ..ref.width = bgTreatment.width
          ..ref.height = bgTreatment.height
          ..ref.rotationDeg = 0
          ..ref.fillColorArgb = bgTreatment.fillColor.argb
          ..ref.outlineColorArgb = bgTreatment.outlineColor.argb
          ..ref.outlineThickness = 0
          ..ref.blur = bgTreatment.blur.clamp(0, 255)
          ..ref.cornerRadius = 0;
      }

      handle = FfiMarshal.encodeElements(elements, calloc);

      final code = ffi.compose(
        backgroundCStr,
        outputCStr,
        fontCStr,
        treatmentPtr,
        foregroundCStr,
        handle.elementsPtr,
        handle.count,
        imageQuality,
        handle.arena.ptr,
      );

      final domainResult = handle.arena.readResult(code);
      if (domainResult is ErrUnit) throw RenderException(domainResult.code, domainResult.message);
    } finally {
      if (backgroundCStr != nullptr) calloc.free(backgroundCStr);
      if (outputCStr != nullptr) calloc.free(outputCStr);
      if (fontCStr != nullptr) calloc.free(fontCStr);
      if (foregroundCStr != nullptr) calloc.free(foregroundCStr);
      if (treatmentPtr != nullptr) calloc.free(treatmentPtr);
      handle?.free();
    }
  }

  /// Standalone region blur: applies a Gaussian blur to [region] (an instance of [RectElement])
  /// and writes the output.
  ///
  /// File I/O is performed entirely in Rust. Runs in a background isolate via [Isolate.run].
  static Future<void> blur({
    required String imagePath,
    required RectElement region,
    String? outputPath,
    int imageQuality = DrawConstants.defaultImageQuality,
  }) {
    FfiAbi.assertAll();
    if (imagePath.isEmpty) {
      throw const RenderException(.invalidArg, 'imagePath cannot be empty');
    }
    final clampedQuality = imageQuality.clamp(
      DrawConstants.minImageQuality,
      DrawConstants.maxImageQuality,
    );

    return Isolate.run(
      () => _runBlurWorker(
        imagePath: imagePath,
        imageQuality: clampedQuality,
        outputPath: outputPath,
        region: region,
      ),
    );
  }

  static void _runBlurWorker({
    required String imagePath,
    required int imageQuality,
    required String? outputPath,
    required RectElement region,
  }) {
    Pointer<Utf8> imageCStr = nullptr;
    Pointer<Utf8> outputCStr = nullptr;
    FfiArenaHandle? arena;
    Pointer<RectanglePayload> payloadPtr = nullptr;
    try {
      imageCStr = imagePath.toNativeUtf8(allocator: calloc);
      outputCStr = outputPath?.toNativeUtf8(allocator: calloc) ?? nullptr;
      arena = FfiArenaHandle.allocate(errorCapacity: FfiAbi.errorCapBytes);

      // Allocate a native RectanglePayload to pass by value over FFI.
      payloadPtr = calloc<RectanglePayload>()
        ..ref.x = region.x
        ..ref.y = region.y
        ..ref.width = region.width
        ..ref.height = region.height
        ..ref.rotationDeg = region.rotation
        ..ref.fillColorArgb = region.fillColor.argb
        ..ref.outlineColorArgb = region.outlineColor.argb
        ..ref.outlineThickness = region.outlineThickness.clamp(0, 255)
        ..ref.blur = region.blur.clamp(0, 255)
        ..ref.cornerRadius = region.cornerRadius;

      final code = ffi.blur_region(imageCStr, outputCStr, payloadPtr.ref, imageQuality, arena.ptr);

      final domainResult = arena.readResult(code);
      if (domainResult is ErrUnit) throw RenderException(domainResult.code, domainResult.message);
    } finally {
      if (imageCStr != nullptr) calloc.free(imageCStr);
      if (outputCStr != nullptr) calloc.free(outputCStr);
      if (payloadPtr != nullptr) calloc.free(payloadPtr);
      arena?.free();
    }
  }

  /// Rotates an image by 90° increments.
  ///
  /// [quarterTurns]: 1 = 90° CW, 2 = 180°, 3 = 270° CW (= 90° CCW).
  /// Values are mod 4 (so 0 and 4 are no-ops that skip file I/O entirely).
  ///
  /// File I/O is performed entirely in Rust. Runs in a background isolate via [Isolate.run].
  static Future<void> rotate({
    required String imagePath,
    required int quarterTurns,
    String? outputPath,
    int imageQuality = DrawConstants.defaultImageQuality,
  }) {
    FfiAbi.assertAll();
    if (imagePath.isEmpty) {
      throw const RenderException(.invalidArg, 'imagePath cannot be empty');
    }
    final clampedQuality = imageQuality.clamp(
      DrawConstants.minImageQuality,
      DrawConstants.maxImageQuality,
    );

    return Isolate.run(
      () => _runRotateWorker(
        imagePath: imagePath,
        imageQuality: clampedQuality,
        outputPath: outputPath,
        quarterTurns: quarterTurns,
      ),
    );
  }

  static void _runRotateWorker({
    required String imagePath,
    required int imageQuality,
    required String? outputPath,
    required int quarterTurns,
  }) {
    Pointer<Utf8> imageCStr = nullptr;
    Pointer<Utf8> outputCStr = nullptr;
    FfiArenaHandle? arena;
    try {
      imageCStr = imagePath.toNativeUtf8(allocator: calloc);
      outputCStr = outputPath?.toNativeUtf8(allocator: calloc) ?? nullptr;
      arena = FfiArenaHandle.allocate(errorCapacity: FfiAbi.errorCapBytes);

      final code = ffi.rotate(
        imageCStr,
        outputCStr,
        quarterTurns.clamp(0, 255),
        imageQuality,
        arena.ptr,
      );

      final domainResult = arena.readResult(code);
      if (domainResult is ErrUnit) throw RenderException(domainResult.code, domainResult.message);
    } finally {
      if (imageCStr != nullptr) calloc.free(imageCStr);
      if (outputCStr != nullptr) calloc.free(outputCStr);
      arena?.free();
    }
  }

  /// Converts an image to JPEG format at the specified quality.
  ///
  /// Reads any supported format (PNG, JPEG), writes JPEG to [outputPath].
  /// If [outputPath] is not provided, overwrites [imagePath] (which must have .jpg/.jpeg ext).
  ///
  /// File I/O is performed entirely in Rust. Runs in a background isolate via [Isolate.run].
  static Future<void> toJpg({
    required String imagePath,
    String? outputPath,
    int imageQuality = DrawConstants.defaultImageQuality,
  }) {
    FfiAbi.assertAll();
    if (imagePath.isEmpty) {
      throw const RenderException(.invalidArg, 'imagePath cannot be empty');
    }
    final clampedQuality = imageQuality.clamp(
      DrawConstants.minImageQuality,
      DrawConstants.maxImageQuality,
    );

    return Isolate.run(
      () => _runToJpgWorker(
        imagePath: imagePath,
        imageQuality: clampedQuality,
        outputPath: outputPath,
      ),
    );
  }

  static void _runToJpgWorker({
    required String imagePath,
    required int imageQuality,
    required String? outputPath,
  }) {
    Pointer<Utf8> imageCStr = nullptr;
    Pointer<Utf8> outputCStr = nullptr;
    FfiArenaHandle? arena;
    try {
      imageCStr = imagePath.toNativeUtf8(allocator: calloc);
      outputCStr = outputPath?.toNativeUtf8(allocator: calloc) ?? nullptr;
      arena = FfiArenaHandle.allocate(errorCapacity: FfiAbi.errorCapBytes);

      final code = ffi.to_jpg(imageCStr, outputCStr, imageQuality, arena.ptr);

      final domainResult = arena.readResult(code);
      if (domainResult is ErrUnit) throw RenderException(domainResult.code, domainResult.message);
    } finally {
      if (imageCStr != nullptr) calloc.free(imageCStr);
      if (outputCStr != nullptr) calloc.free(outputCStr);
      arena?.free();
    }
  }

  /// Resizes an image to exact [width] × [height] dimensions.
  ///
  /// [filter] controls the interpolation algorithm (default: [ResizeFilter.bilinear]).
  /// If [outputPath] is not provided, overwrites [imagePath].
  ///
  /// [imageQuality] controls output quality if saving to JPEG. Ignored for PNG output.
  ///
  /// File I/O is performed entirely in Rust. Runs in a background isolate via [Isolate.run].
  static Future<void> resize({
    required int height,
    required String imagePath,
    required int width,
    String? outputPath,
    ResizeFilter filter = .bilinear,
    int imageQuality = DrawConstants.defaultImageQuality,
  }) {
    FfiAbi.assertAll();
    if (imagePath.isEmpty) throw const RenderException(.invalidArg, 'imagePath cannot be empty');
    if (width <= 0 || height <= 0) {
      throw const RenderException(.invalidArg, 'width and height must be > 0');
    }
    final clampedQuality = imageQuality.clamp(
      DrawConstants.minImageQuality,
      DrawConstants.maxImageQuality,
    );

    return Isolate.run(
      () => _runResizeWorker(
        filter: filter,
        height: height,
        imagePath: imagePath,
        imageQuality: clampedQuality,
        outputPath: outputPath,
        width: width,
      ),
    );
  }

  // ignore: avoid-long-parameter-list, mirrors the FFI function signature 1:1.
  static void _runResizeWorker({
    required ResizeFilter filter,
    required int height,
    required String imagePath,
    required int imageQuality,
    required String? outputPath,
    required int width,
  }) {
    Pointer<Utf8> imageCStr = nullptr;
    Pointer<Utf8> outputCStr = nullptr;
    FfiArenaHandle? arena;
    try {
      imageCStr = imagePath.toNativeUtf8(allocator: calloc);
      outputCStr = outputPath?.toNativeUtf8(allocator: calloc) ?? nullptr;
      arena = FfiArenaHandle.allocate(errorCapacity: FfiAbi.errorCapBytes);

      final code = ffi.resize(
        imageCStr,
        outputCStr,
        width,
        height,
        filter.wire,
        imageQuality,
        arena.ptr,
      );

      final domainResult = arena.readResult(code);
      if (domainResult is ErrUnit) throw RenderException(domainResult.code, domainResult.message);
    } finally {
      if (imageCStr != nullptr) calloc.free(imageCStr);
      if (outputCStr != nullptr) calloc.free(outputCStr);
      arena?.free();
    }
  }
}
