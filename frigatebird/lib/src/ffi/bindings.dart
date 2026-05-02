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
///
/// Note: `ffi_echo_element` (test-only round-trip helper) is declared in
/// `ffi_echo_element.dart`, not here, to keep test infrastructure out of production code.
@DefaultAsset('package:frigatebird/src/ffi/bindings.dart')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'byte_buffer.dart';
import 'ffi_arena.dart';
import 'ffi_element.dart';
import 'ffi_rect_element.dart';
import 'ffi_result_unit.dart';

/// Bytes-in / bytes-out path used by the Flutter `ExportBackend`.
///
/// Coordinates in [rectsPtr] are pixel-space (no normalization). Returns a Rust-allocated
/// [ByteBuffer]; caller must check `data == nullptr` (panic) and free with [free_bytes].
@Native<ByteBuffer Function(Pointer<Uint8>, Size, Pointer<FfiRectElement>, Size, Uint8)>()
// TODO: We need to get rid of this method everywhere! Migrate draw_elements.
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
/// Result is written to [out] rather than returned by value. Returning a 6-byte struct by value
/// has target-specific ABI differences between SysV x86-64, Win64, AArch64 AAPCS, and ARMv7;
/// an out-pointer sidesteps these completely.
///
/// **Not `isLeaf: true`**: this is a CPU-heavy image-processing call. `isLeaf` would prevent the
/// Dart VM from scheduling GC while it runs — acceptable only for O(1) functions. All real work
/// must run via `Isolate.run` so the calling isolate stays responsive.
@Native<
  Void Function(
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<FfiElement>,
    Size,
    Uint8,
    Pointer<FfiArena>,
    Pointer<FfiResultUnitStruct>,
  )
>()
external void draw_elements(
  Pointer<Utf8> imagePath,
  Pointer<Utf8> outputPath,
  Pointer<Utf8> fontPath,
  Pointer<FfiElement> elementsPtr,
  int elementsCount,
  int imageQuality,
  Pointer<FfiArena> arena,
  Pointer<FfiResultUnitStruct> out,
);
