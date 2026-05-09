import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'bindings.dart' as ffi;
import 'ffi_abi.dart';
import 'ffi_arena_handle.dart';
import 'image_info_exception.dart';
import 'image_info_struct.dart';

/// Dart-friendly result of [ImageInformation.probe].
@pragma('vm:deeply-immutable')
final class ImageInformation {
  const ImageInformation({
    required this.width,
    required this.height,
    this.format = 255,
    this.orientation = 1,
  });

  /// Synchronous version. Public for use inside isolate workers and tests.
  /// Do NOT call directly from the UI isolate — use [probe].
  // ignore: avoid-non-empty-constructor-bodies, this factory constructor...
  factory ImageInformation.probeSync(String path) {
    FfiAbi.assertAll();

    final pathPtr = path.toNativeUtf8();

    Pointer<ImageInfoStruct> infoPtr = nullptr;
    FfiArenaHandle? arena;

    try {
      infoPtr = calloc<ImageInfoStruct>();
      arena = FfiArenaHandle.allocate();

      final code = ffi.get_image_info(pathPtr, arena.ptr, infoPtr);
      if (code != 0) {
        throw ImageInfoException(
          code: code,
          message: arena.readErrorMessage() ?? 'get_image_info failed ($code)',
        );
      }

      final i = infoPtr.ref;

      return ImageInformation(
        format: i.format,
        height: i.height,
        orientation: i.orientation,
        width: i.width,
      );
    } finally {
      arena?.free();
      if (infoPtr != nullptr) calloc.free(infoPtr);
      calloc.free(pathPtr);
    }
  }

  /// Width AFTER applying EXIF orientation.
  final int width;

  /// Height AFTER applying EXIF orientation.
  final int height;

  /// 0 = PNG, 1 = JPEG, 255 = unknown.
  final int format;

  /// Raw EXIF orientation tag 1..=8 (1 = no rotation). Diagnostic — Rust has
  /// already swapped width/height for tags 5..=8 before returning.
  final int orientation;

  /// Async entry point. Runs the FFI call on a worker isolate so the UI
  /// isolate is never blocked by file I/O or EXIF parsing.
  static Future<ImageInformation> probe(String path) =>
      Isolate.run(() => ImageInformation.probeSync(path));

  @override
  String toString() =>
      'ImageInformation(width: $width, height: $height, format: $format, orientation: $orientation)';
}
