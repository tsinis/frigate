import 'dart:ffi';
import 'dart:isolate' show Isolate;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../constants/draw_constants.dart';
import '../model/draw_element.dart';
import 'bindings.dart' as ffi;
import 'export_backend.dart';
import 'ffi_abi.dart';
import 'ffi_rect_element.dart';
import 'native_image.dart';

/// Factory for conditional import — selected when `dart.library.ffi` is available.
ExportBackend createExportBackend() {
  assertFfiRectElementAbi();

  return _NativeExportBackend();
}

/// Zero-copy export backend using `dart:ffi` + Rust.
///
/// WHY [NativeImage]: Dart GC can relocate Uint8List at any time. [NativeImage] stores bytes in
/// malloc'd memory (stable address), so we pass `int address` to the export isolate — no copy of
/// the source image during export.
///
/// Manual free: result bytes are copied to a Dart [Uint8List] and the Rust-allocated buffer is
/// freed immediately. Simple, safe, no finalizer signature mismatch.
final class _NativeExportBackend implements ExportBackend {
  NativeImage? _image;

  @override
  Future<void> loadImage(Uint8List bytes, {required int height, required int width}) async {
    _image?.dispose();
    _image = NativeImage.fromBytes(bytes, height: height, width: width);
  }

  @override
  Future<Uint8List> export({
    required List<RectElement> rects,
    int imageQuality = DrawConstants.defaultImageQuality,
  }) {
    final image = _image;
    if (image == null) throw StateError('Call loadImage() before export().');
    final NativeImage(:address, :length) = image;

    return Isolate.run(
      () => _doExport(
        _ExportArgs(imageQuality: imageQuality, imgAddress: address, imgLen: length, rects: rects),
      ),
    );
  }

  @override
  void dispose() {
    _image?.dispose();
    _image = null;
  }

  /// Runs in a background isolate via [Isolate.run].
  ///
  /// WHY Pointer.fromAddress: Pointer cannot cross isolate boundaries, but int can. The underlying
  /// native memory is the same — zero copy. RectElement is @pragma('vm:deeply-immutable') —
  /// zero-copy transfer.
  static Uint8List _doExport(_ExportArgs args) {
    final _ExportArgs(:imageQuality, :imgAddress, :imgLen, :rects) = args;
    final rectsPtr = rects.toNative(malloc);
    final imgPtr = Pointer<Uint8>.fromAddress(imgAddress);
    final result = ffi.export_image(imgPtr, imgLen, rectsPtr, rects.length, imageQuality);
    // Always free rects (we allocated them above). Do NOT free imgPtr — NativeImage owns it.
    malloc.free(rectsPtr);
    // Null data pointer means Rust panicked (catch_unwind returned Err).
    if (result.data == nullptr) {
      throw StateError('Rust export_image failed (panic in native render)');
    }
    // Copy result to Dart-managed memory, then free the Rust-allocated buffer. Manual free — safe,
    // no finalizer signature issues. try/finally guarantees free_bytes runs even on OOM (real on
    // mobile with large images).
    final Uint8List output;
    try {
      output = Uint8List.fromList(result.data.asTypedList(result.length));
    } finally {
      ffi.free_bytes(result.data, result.length);
    }

    return output;
  }
}

/// Arguments for [_NativeExportBackend._doExport], sent to a background isolate.
final class _ExportArgs {
  const _ExportArgs({
    required this.imageQuality,
    required this.imgAddress,
    required this.imgLen,
    required this.rects,
  });

  final int imageQuality;
  final int imgAddress;
  final int imgLen;
  final List<RectElement> rects;
}
