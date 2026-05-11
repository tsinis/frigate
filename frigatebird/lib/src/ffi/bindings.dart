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
import 'image_info_struct.dart';

// --- Size Oracles ---.

@Native<Size Function()>(isLeaf: true)
external int sizeof_ffi_element();

@Native<Size Function()>(isLeaf: true)
external int sizeof_ffi_payload();

@Native<Size Function()>(isLeaf: true)
external int sizeof_ffi_arena();

@Native<Size Function()>(isLeaf: true)
external int sizeof_ffi_error();

@Native<Size Function()>(isLeaf: true)
external int sizeof_image_info();

// --- Drop Hooks ---.

@Native<Void Function(Pointer<FfiArena>)>()
external void ffi_arena_drop(Pointer<FfiArena> arena);

@Native<Void Function(Pointer<ByteBuffer>)>()
external void free_byte_buffer(Pointer<ByteBuffer> buf);

/// Returns oriented dimensions and metadata for an image without decoding full pixel data.
///
/// Returns a `u8` status code. Result info is written to [out].
@Native<Uint8 Function(Pointer<Utf8>, Pointer<FfiArena>, Pointer<ImageInfoStruct>)>()
external int get_image_info(
  Pointer<Utf8> path,
  Pointer<FfiArena> arena,
  Pointer<ImageInfoStruct> out,
);

/// Bytes-in / path-in merge: composites `foreground_png` bytes over the image at `backgroundPath`
/// and returns the result as a byte buffer owned by Rust.
///
/// Returns a `u8` status code. Result buffer is written to `*out`.
@Native<
  Uint8 Function(
    Pointer<Utf8>,
    Pointer<Uint8>,
    Size,
    Int32,
    Int32,
    Uint8,
    Uint8,
    Pointer<FfiArena>,
    Pointer<ByteBuffer>,
  )
>()
external int merge(
  Pointer<Utf8> backgroundPath,
  Pointer<Uint8> foregroundPngPtr,
  int foregroundPngLen,
  int offsetX,
  int offsetY,
  int outFormat,
  int imageQuality,
  Pointer<FfiArena> arena,
  Pointer<ByteBuffer> out,
);

/// Unified render call: reads the image from [imagePath], composites all [FfiElement]s
/// (rectangles, text, future shapes), writes the result to [outputPath].
///
/// [fontPath] may be null when no element has a text tag.
/// Variable-length text and error data are exchanged through [arena]:
///   - `arena.text_buf` / `arena.text_len` — UTF-8 text sidecar (Dart-owned, read-only by Rust).
///   - `arena.error_buf` / `arena.error_cap` — error message buffer (Dart-owned, Rust writes on err).
///
/// Returns a `u8` status code (0 for success, see `FfiErrorCode`).
///
/// **Not `isLeaf: true`**: this is a CPU-heavy image-processing call. `isLeaf` would prevent the
/// Dart VM from scheduling GC while it runs — acceptable only for O(1) functions. All real work
/// must run via `Isolate.run` so the calling isolate stays responsive.
@Native<
  Uint8 Function(
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<FfiElement>,
    Size,
    Uint8,
    Pointer<FfiArena>,
  )
>()
external int draw_elements(
  Pointer<Utf8> imagePath,
  Pointer<Utf8> outputPath,
  Pointer<Utf8> fontPath,
  Pointer<FfiElement> elementsPtr,
  int elementsCount,
  int imageQuality,
  Pointer<FfiArena> arena,
);
