// ignore_for_file: prefer-single-declaration-per-file, file-name-should-match-class

import 'dart:typed_data';

import '../model/draw_element.dart';
import 'export_backend.dart';

// TODO! The Rust crate would need to be compiled separately with
// `wasm-pack / cargo build --target wasm32-unknown-unknown` and loaded via JS interop.
// That's the "real work" you said to just document/structure for now, not implement.

/// Factory for conditional import — selected when `dart.library.js_interop`
/// is available (WASM builds).
// ignore: prefer-static-class, required top-level for conditional import pattern.
ExportBackend createExportBackend() => const _WebExportBackend();

// ignore: prefer-match-file-name, it's conditional import target.
class _WebExportBackend implements ExportBackend {
  const _WebExportBackend();

  @override
  Future<void> loadImage(Uint8List bytes, {required int height, required int width}) async {
    // TODO(wasm): store bytes for WASM Rust module.
  }

  @override
  Future<Uint8List> export({required List<RectElement> rects, int jpegQuality = 90}) =>
      throw UnimplementedError(
        'WASM export backend not yet implemented. '
        'Requires wasm-pack build pipeline for the Rust crate.',
      );

  @override
  void dispose() {
    // TODO(wasm): free WASM-side resources.
  }
}
