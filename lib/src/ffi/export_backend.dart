import 'dart:typed_data';

import '../frigate_draw_dart.dart';

/// Platform-agnostic export contract.
///
/// Native impl uses NativeImage (zero-copy via stable malloc pointer).
/// Web/WASM impl will use Rust WASM module (not yet implemented).
abstract interface class ExportBackend {
  /// Load source image bytes. On native, copies once into native heap
  /// so subsequent exports are zero-copy.
  Future<void> loadImage(Uint8List bytes, {required int height, required int width});

  /// Render overlays onto the loaded image and return encoded JPEG bytes.
  Future<Uint8List> export({required List<RectElement> rects, int jpegQuality = 90});

  /// Free native resources. Do NOT call while [export] is in progress.
  void dispose();
}
