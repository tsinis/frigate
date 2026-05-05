import 'dart:ffi';
import 'dart:isolate' show Isolate;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../constants/draw_constants.dart';
import 'bindings.dart' as ffi;
import 'byte_buffer.dart';
import 'ffi_marshal.dart';
import 'ffi_result_unit.dart';

/// Zero-copy merge backend using `dart:ffi` + Rust.
///
/// Merges a foreground PNG (typically the drawing layer) onto a background image file.
final class ExportBackendNative {
  const ExportBackendNative();

  /// Merges [foregroundPng] onto the image at [backgroundPath] and returns the result as bytes.
  ///
  /// [offsetX] and [offsetY] are the top-left offset of the foreground on the background.
  /// [outFormat]: 0 for PNG, 1 for JPEG.
  Future<Uint8List> merge({
    required String backgroundPath,
    required Uint8List foregroundPng,
    int imageQuality = DrawConstants.defaultImageQuality,
    int offsetX = 0,
    int offsetY = 0,
    int outFormat = 0,
  }) => Isolate.run(
    () => _doMerge(
      _MergeArgs(
        backgroundPath: backgroundPath,
        foregroundPng: foregroundPng,
        imageQuality: imageQuality,
        offsetX: offsetX,
        offsetY: offsetY,
        outFormat: outFormat,
      ),
    ),
  );

  static Uint8List _doMerge(_MergeArgs args) {
    final _MergeArgs(
      :backgroundPath,
      :foregroundPng,
      :imageQuality,
      :offsetX,
      // ignore: avoid-similar-names, offsetX and offsetY are standard pairings
      :offsetY,
      :outFormat,
    ) = args;

    Pointer<Utf8> bgCStr = nullptr;
    Pointer<Uint8> fgPtr = nullptr;
    Pointer<ByteBuffer> outPtr = nullptr;
    FfiArenaHandle? arenaHandle;

    try {
      bgCStr = backgroundPath.toNativeUtf8();
      assert(bgCStr != nullptr, 'Failed to convert backgroundPath to C string');
      final fgLen = foregroundPng.length;
      fgPtr = malloc<Uint8>(fgLen);
      fgPtr.asTypedList(fgLen).setAll(0, foregroundPng);
      outPtr = malloc<ByteBuffer>();
      // We need an arena for potential error messages.
      arenaHandle = FfiMarshal.encodeElements([], malloc);

      final arenaRef = arenaHandle.arenaPtr.ref;

      final code = ffi.merge(
        bgCStr,
        fgPtr,
        fgLen,
        offsetX,
        offsetY,
        outFormat,
        imageQuality,
        arenaHandle.arenaPtr,
        outPtr,
      );

      final result = FfiResultUnit.decode(code, arenaRef.errorBuf, arenaRef.errorCap);

      if (result is ErrUnit) {
        throw StateError('Rust merge failed: ${result.message}');
      }

      final out = outPtr.ref;
      final outData = out.data;
      final outLen = out.length;

      if (outData == nullptr) {
        throw StateError('Rust merge failed (null output buffer)');
      }

      final Uint8List output;
      try {
        output = Uint8List.fromList(outData.asTypedList(outLen));
      } finally {
        ffi.free_bytes(outData, outLen);
      }

      return output;
    } finally {
      if (bgCStr != nullptr) malloc.free(bgCStr);
      if (fgPtr != nullptr) malloc.free(fgPtr);
      if (outPtr != nullptr) malloc.free(outPtr);
      arenaHandle?.free();
    }
  }
}

/// Arguments for `ExportBackendNative._doMerge`, sent to a background isolate.
final class _MergeArgs {
  const _MergeArgs({
    required this.backgroundPath,
    required this.foregroundPng,
    required this.imageQuality,
    required this.offsetX,
    required this.offsetY,
    required this.outFormat,
  });

  final String backgroundPath;
  final Uint8List foregroundPng;
  final int imageQuality;
  final int offsetX;
  final int offsetY;
  final int outFormat;
}
