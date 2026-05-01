// FFI bindings — symbol names + parameter ordering are dictated by the C ABI of the Rust
// `extern "C"` exports, not by our Dart style preferences. Top-level `@Native()` functions
// (not a static-class wrapper) is the standard idiom for `dart:ffi`.
// ignore_for_file: prefer-named-parameters, prefer-static-class
// ignore_for_file: non_constant_identifier_names, prefer-typedefs-for-callbacks

/// Hand-written `@Native()` FFI bindings for the Rust crate `frigate`.
///
/// NOT code-generated — ffigen is not used. The `@Native()` annotation auto-resolves the compiled
/// Rust library via the code asset system (`native_toolchain_rust` + build hook), so no
/// `DynamicLibrary.open()` needed.
///
/// Symbol names (snake_case) MUST match the Rust `#[unsafe(no_mangle)] pub unsafe extern "C"`
/// function names exactly. Positional parameters are required by the C ABI.
@DefaultAsset('package:frigatebird/src/ffi/bindings.dart')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'byte_buffer.dart';
import 'ffi_arena.dart';
import 'ffi_element.dart';
import 'ffi_rect_element.dart';
import 'ffi_result.dart';

/// Round-trips an [FfiElement] through Rust unchanged. Used by layout round-trip tests to verify
/// that the Dart-side struct layout matches the Rust-side layout without any data transformation.
///
/// `isLeaf: true` — O(1) identity function, never calls back into Dart.
@Native<Pointer<FfiElement> Function(Pointer<FfiElement>)>(isLeaf: true)
external Pointer<FfiElement> ffi_echo_element(Pointer<FfiElement> ptr);

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
  int imageQuality,
);

/// Free a Rust-allocated byte buffer (returned by [export_image]). Null-safe.
///
/// `isLeaf: true` — never calls back into Dart, so the Dart VM can skip the safepoint preamble.
@Native<Void Function(Pointer<Uint8>, Size)>(isLeaf: true)
external void free_bytes(Pointer<Uint8> ptr, int len);

/// Unified render call: reads the image from [imagePath], composites all [FfiElement]s
/// (rectangles, text, future shapes), writes the result to [outputPath].
///
/// [fontPath] may be null when no element has a text tag.
/// Variable-length text and error data are exchanged through [arena]:
///   - `arena.text_buf` / `arena.text_len` — UTF-8 text sidecar (Dart-owned, read-only by Rust).
///   - `arena.error_buf` / `arena.error_cap` — error message buffer (Dart-owned, Rust writes on err).
///
/// Returns [FfiResultUnit]: `tag == 0` on success; `tag == 1` on error with code + message in arena.
@Native<
  FfiResultUnit Function(
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<FfiElement>,
    Size,
    Uint8,
    Pointer<FfiArena>,
  )
>()
external FfiResultUnit draw_elements(
  Pointer<Utf8> imagePath,
  Pointer<Utf8> outputPath,
  Pointer<Utf8> fontPath,
  Pointer<FfiElement> elementsPtr,
  int elementsCount,
  int imageQuality,
  Pointer<FfiArena> arena,
);
