// ignore_for_file: prefer-named-parameters, prefer-static-class
// ignore_for_file: non_constant_identifier_names, prefer-typedefs-for-callbacks

/// Hand-written `@Native()` FFI bindings for the Rust crate `frigate`.
///
/// NOT code-generated — ffigen is not used. The `@Native()` annotation auto-resolves the compiled
/// Rust library via the code asset system (`native_toolchain_rust` + build hook), so no
/// `DynamicLibrary.open()` needed.
///
/// Symbol names (snake_case) MUST match the Rust `#[no_mangle] pub extern "C"` function names
/// exactly. Positional parameters are required by the C ABI.
@DefaultAsset('package:frigatebird/src/ffi/bindings.dart')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'byte_buffer.dart';
import 'ffi_element.dart';
import 'ffi_rect_element.dart';

/// Bytes-in / bytes-out path used by the Flutter `ExportBackend`.
///
/// Coordinates in [rectsPtr] are pixel-space (no normalization). Returns a Rust-allocated
/// [ByteBuffer]; caller must check `data == nullptr` (panic) and free with [free_bytes].
@Native<ByteBuffer Function(Pointer<Uint8>, Size, Pointer<FfiRectElement>, Size, Uint8)>()
external ByteBuffer export_image(
  Pointer<Uint8> imgPtr,
  int imgLen,
  Pointer<FfiRectElement> rectsPtr,
  int rectsCount,
  int jpegQuality,
);

/// Free a Rust-allocated byte buffer (returned by [export_image]). Null-safe.
///
/// `isLeaf: true` — never calls back into Dart, so the Dart VM can skip the safepoint preamble.
@Native<Void Function(Pointer<Uint8>, Size)>(isLeaf: true)
external void free_bytes(Pointer<Uint8> ptr, int len);

/// Unified render call: takes a mixed [FfiElement] array (rectangles, text, future shapes), reads
/// the image from [imagePath], writes the composited result to [outputPath].
///
/// [fontPath] may be null when no [FfiElement] in the array has `elementType` of text.
/// [textBuffer] + [textBufferLen] back the variable-length text content; each text element points
/// into this buffer via `textOffset` + `textLength`. May be null when no text elements.
///
/// Returns an integer error code:
/// - `0`  success
/// - `1`  image read/decode failed
/// - `2`  font read failed
/// - `3`  font parse failed
/// - `4`  text not valid UTF-8
/// - `5`  path not valid UTF-8
/// - `6`  image write failed
/// - `7`  null pointer for a required argument
/// - `8`  text element present but no font supplied
/// - `99` Rust panic
///
/// `isLeaf: true` because the function performs synchronous I/O and never calls back into Dart.
@Native<
  Int32 Function(
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<FfiElement>,
    Size,
    Pointer<Uint8>,
    Size,
    Uint8,
  )
>(isLeaf: true)
external int render_image(
  Pointer<Utf8> imagePath,
  Pointer<Utf8> outputPath,
  Pointer<Utf8> fontPath,
  Pointer<FfiElement> elementsPtr,
  int elementsCount,
  Pointer<Uint8> textBuffer,
  int textBufferLen,
  int jpegQuality,
);
