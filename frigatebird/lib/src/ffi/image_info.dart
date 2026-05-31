// ignore_for_file: prefer-single-declaration-per-file

import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'bindings.dart' as ffi;
import 'ffi_abi.dart';
import 'ffi_arena_handle.dart';
import 'ffi_result_unit.dart';
import 'image_info_exception.dart';
import 'image_info_struct.dart';

/// Dart-friendly result of [ImageInformation.probe].
@pragma('vm:deeply-immutable')
final class ImageInformation {
  const ImageInformation({
    required this.width,
    required this.height,
    this.formatWire = _defaultFormatWire,
    this.orientationWire = _defaultOrientationWire,
  });

  /// Convenience constructor that accepts enums.
  factory ImageInformation.from({
    required int width,
    required int height,
    ImageFormat format = .unknown,
    ExifOrientation orientation = .normal,
  }) => ImageInformation(
    formatWire: format.wire,
    height: height,
    orientationWire: orientation.wire,
    width: width,
  );

  /// Internal constructor for FFI.
  const ImageInformation._raw({
    required this.width,
    required this.height,
    required this.formatWire,
    required this.orientationWire,
  });

  /// Synchronous version. Public for use inside isolate workers and tests.
  // ignore: avoid-non-empty-constructor-bodies, description: FFI setup requires complex init.
  factory ImageInformation.probeSync(String path) {
    FfiAbi.assertAll();

    final pathPtr = path.toNativeUtf8(allocator: calloc);

    Pointer<ImageInfoStruct> infoPtr = nullptr;
    FfiArenaHandle? arena;

    try {
      infoPtr = calloc<ImageInfoStruct>();
      arena = FfiArenaHandle.allocate();

      final code = ffi.get_image_info(pathPtr, arena.ptr, infoPtr);
      final result = arena.readResult(code);

      if (result is ErrUnit) {
        throw ImageInfoException.from(code: result.code, message: result.message);
      }

      final i = infoPtr.ref;

      return ImageInformation._raw(
        formatWire: i.format,
        height: i.height,
        orientationWire: i.orientation,
        width: i.width,
      );
    } finally {
      calloc.free(pathPtr);
      if (infoPtr != nullptr) calloc.free(infoPtr);
      arena?.free();
    }
  }

  /// Width AFTER applying EXIF orientation.
  final int width;

  /// Height AFTER applying EXIF orientation.
  final int height;

  /// Oriented image format.
  final int formatWire;

  /// Raw EXIF orientation tag 1..=8 (1 = no rotation). Diagnostic — Rust has
  /// already swapped width/height for tags 5..=8 before returning.
  final int orientationWire;

  static const _defaultFormatWire = 255; // ImageFormat.unknown.wire.
  static const _defaultOrientationWire = 1; // ExifOrientation.normal.wire.

  /// Oriented image format as an enum.
  ImageFormat get format => ImageFormat.fromWire(formatWire);

  /// EXIF orientation as an enum.
  ExifOrientation get orientation => ExifOrientation.fromWire(orientationWire);

  /// Async entry point. Runs the FFI call on a worker isolate so the UI
  /// isolate is never blocked by file I/O or EXIF parsing.
  static Future<ImageInformation> probe(String path) =>
      Isolate.run(() => ImageInformation.probeSync(path));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImageInformation &&
          runtimeType == other.runtimeType &&
          width == other.width &&
          height == other.height &&
          formatWire == other.formatWire &&
          orientationWire == other.orientationWire;

  @override
  int get hashCode => Object.hash(width, height, formatWire, orientationWire);

  @override
  String toString() =>
      'ImageInformation(width: $width, height: $height, format: $format, orientation: $orientation)';
}

enum ImageFormat {
  jpg(1),
  png(0),
  unknown(255);

  const ImageFormat(this.wire);
  final int wire;

  static ImageFormat fromWire(int v) => switch (v) {
    0 => png,
    1 => jpg,
    _ => unknown,
  };
}

enum ExifOrientation {
  flipH(2),
  flipV(4),
  normal(1),
  rotate180(3),
  rotate270(8),
  rotate90(6),
  transpose(5),
  transverse(7);

  const ExifOrientation(this.wire);
  final int wire;

  static ExifOrientation fromWire(int v) => switch (v) {
    2 => flipH,
    3 => rotate180,
    4 => flipV,
    5 => transpose,
    6 => rotate90,
    7 => transverse,
    8 => rotate270,
    _ => normal,
  };
}
