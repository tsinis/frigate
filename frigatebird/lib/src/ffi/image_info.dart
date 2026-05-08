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
    this.format = 1,
    this.orientation = 1,
  });

  /// Width AFTER applying EXIF orientation.
  final int width;

  /// Height AFTER applying EXIF orientation.
  final int height;

  /// 0 = PNG, 1 = JPEG, 255 = unknown.
  final int format;

  /// Raw EXIF orientation tag 1..=8 (1 = no rotation). Diagnostic — Rust has
  /// already swapped width/height for tags 5..=8 before returning.
  final int orientation;

  /// True when the source file required a 90°/270° rotation.
  bool get isRotated => orientation >= 5 && orientation <= 8;

  bool get isZero => width == 0 && height == 0;

  /// Async entry point. Runs the FFI call on a worker isolate so the UI
  /// isolate is never blocked by file I/O or EXIF parsing.
  static Future<ImageInformation> probe(String path) => Isolate.run(() => probeSync(path));

  /// Synchronous version. Public for use inside isolate workers and tests.
  /// Do NOT call directly from the UI isolate — use [probe].
  static ImageInformation probeSync(String path) {
    FfiAbi.assertImageInfo();
    FfiAbi.assertArena();

    final pathPtr = path.toNativeUtf8();
    try {
      final infoPtr = calloc<ImageInfoStruct>();
      final arena = FfiArenaHandle.allocate();
      try {
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
        arena.free();
        calloc.free(infoPtr);
      }
    } finally {
      calloc.free(pathPtr);
    }
  }

  @override
  String toString() =>
      'ImageInformation(width: $width, height: $height, format: $format, orientation: $orientation)';
}
