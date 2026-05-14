import 'dart:ffi';
import 'dart:isolate' show Isolate;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../constants/draw_constants.dart';
import 'bindings.dart' as ffi;
import 'byte_buffer.dart';
import 'ffi_arena_handle.dart';
import 'ffi_result_unit.dart';
import 'image_info.dart';
import 'native_image.dart';

/// Zero-copy merge backend using `dart:ffi` + Rust.
///
/// Merges a foreground PNG (typically the drawing layer) onto a background image file.
final class ExportBackendNative {
  const ExportBackendNative();

  /// Merges [foregroundPng] onto the image at [backgroundPath] and returns the result as bytes.
  ///
  /// [offsetX] and [offsetY] are the top-left offset of the foreground on the background.
  /// [outFormat]: PNG or JPEG.
  Future<Uint8List> merge({
    required String backgroundPath,
    required Uint8List foregroundPng,
    int imageQuality = DrawConstants.defaultImageQuality,
    int offsetX = 0,
    // ignore: avoid-similar-names, offsetX and offsetY are standard pairings
    int offsetY = 0,
    ImageFormat outFormat = .png,
  }) async {
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

    // Wrap the foreground PNG in a NativeImage to get a stable address for Isolate.run.
    final fgImage = NativeImage.fromBytes(foregroundPng, height: 0, width: 0);
    // Capture address and length as primitives BEFORE Isolate.run.
    // NativeImage/Pointer cannot cross isolate boundaries.
    final fgAddress = fgImage.address;
    final fgLength = fgImage.length;

    try {
      return await Isolate.run<Uint8List>(
        () => _doMerge(
          _MergeArgs(
            backgroundPath: backgroundPath,
            foregroundAddress: fgAddress,
            foregroundLen: fgLength,
            imageQuality: clampedQuality,
            offsetX: offsetX,
            offsetY: offsetY,
            outFormatWire: outFormat.wire,
          ),
        ),
      );
    } finally {
      // The wrapper stays alive in the caller isolate until Isolate.run completes,
      // ensuring the memory is not freed while the worker isolate uses it.
      fgImage.dispose();
    }
  }

  static Uint8List _doMerge(_MergeArgs args) {
    final _MergeArgs(
      :backgroundPath,
      :foregroundAddress,
      :foregroundLen,
      :imageQuality,
      :offsetX,
      // ignore: avoid-similar-names, offsetX and offsetY are standard pairings
      :offsetY,
      :outFormatWire,
    ) = args;

    if (backgroundPath.isEmpty) {
      throw StateError('Rust merge failed: backgroundPath cannot be empty');
    }

    if (foregroundAddress == 0 || foregroundLen == 0) {
      throw StateError('Rust merge failed: Missing foreground bytes');
    }

    Pointer<Utf8> bgCStr = nullptr;
    Pointer<ByteBuffer> outPtr = nullptr;
    Pointer<ByteBuffer> fgBuf = nullptr;
    FfiArenaHandle? arenaHandle;

    try {
      bgCStr = backgroundPath.toNativeUtf8(allocator: calloc);
      assert(bgCStr != nullptr, 'Failed to convert backgroundPath to C string');

      outPtr = calloc<ByteBuffer>();
      arenaHandle = FfiArenaHandle.allocate(); // We need an arena for potential error messages.

      fgBuf = calloc<ByteBuffer>();
      fgBuf.ref
        ..ptr = Pointer<Uint8>.fromAddress(foregroundAddress)
        ..len = foregroundLen;

      final code = ffi.merge(
        bgCStr,
        fgBuf.ref,
        offsetX,
        offsetY,
        outFormatWire,
        imageQuality.clamp(0, 100),
        arenaHandle.ptr,
        outPtr,
      );

      final result = arenaHandle.readResult(code);

      if (result is ErrUnit) {
        throw StateError('Rust merge failed: ${result.message}');
      }

      final out = outPtr.ref;
      if (out.ptr == nullptr) throw StateError('Rust merge failed (null output buffer)');

      return Uint8List.fromList(out.ptr.asTypedList(out.len));
    } finally {
      if (bgCStr != nullptr) calloc.free(bgCStr);
      if (fgBuf != nullptr) calloc.free(fgBuf);
      // Rust-owned buffer must be freed eagerly before isolate exits.
      if (outPtr != nullptr) {
        if (outPtr.ref.ptr != nullptr) ffi.free_byte_buffer(outPtr.ref);
        calloc.free(outPtr);
      }
      arenaHandle?.free();
    }
  }
}

// These types are kept in the same file because they are private to ExportBackendNative's internals.
// ignore_for_file: prefer-single-declaration-per-file

/// Arguments for `ExportBackendNative._doMerge`, sent to a background isolate.
@pragma('vm:deeply-immutable')
final class _MergeArgs {
  const _MergeArgs({
    required this.backgroundPath,
    required this.foregroundAddress,
    required this.foregroundLen,
    required this.imageQuality,
    required this.offsetX,
    required this.offsetY,
    required this.outFormatWire,
  });

  final String backgroundPath;
  final int foregroundAddress;
  final int foregroundLen;
  final int imageQuality;
  final int offsetX;
  final int offsetY;
  final int outFormatWire;

  /// Output format as an enum.
  ImageFormat get outFormat => ImageFormat.fromWire(outFormatWire);
}
