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

@Native<Size Function()>(isLeaf: true)
external int sizeof_polygon_payload();

// --- Drop Hooks ---.

@Native<Pointer<FfiArena> Function(Size)>(isLeaf: true)
external Pointer<FfiArena> ffi_arena_create(int errorCap);

@Native<Void Function(Pointer<FfiArena>)>(isLeaf: true)
external void ffi_arena_free(Pointer<FfiArena> arena);

@Native<Void Function(ByteBuffer)>(isLeaf: true)
external void free_byte_buffer(ByteBuffer buf);

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
    ByteBuffer,
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
  ByteBuffer foregroundPng,
  int dx,
  int dy,
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
///   - `arena.error` — error message buffer (Rust-owned `c_slice::Box<u8>`, Dart reads on err).
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

/// Background-treatment + foreground composite render: reads the image from [imagePath], applies
/// the optional [treatmentPtr] (full-image blur + tint + crop rect), draws all [elementsPtr]
/// shapes, composites the optional sharp foreground from [foregroundPath], crops, and writes the
/// result to [outputPath].
///
/// Pipeline (original image space, crop last): blur → tint → shapes → foreground → crop.
/// [treatmentPtr] and [foregroundPath] may be null. [fontPath] may be null when no element has a
/// text tag. Variable-length text and error data are exchanged through [arena] (same as
/// [draw_elements]).
///
/// Returns a `u8` status code (0 for success, see `FfiErrorCode`).
///
/// **Not `isLeaf: true`** — CPU-heavy; run via `Isolate.run`.
@Native<
  Uint8 Function(
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<RectanglePayload>,
    Pointer<Utf8>,
    Pointer<FfiElement>,
    Size,
    Uint8,
    Pointer<FfiArena>,
  )
>()
external int compose(
  Pointer<Utf8> imagePath,
  Pointer<Utf8> outputPath,
  Pointer<Utf8> fontPath,
  Pointer<RectanglePayload> treatmentPtr,
  Pointer<Utf8> foregroundPath,
  Pointer<FfiElement> elementsPtr,
  int elementsCount,
  int imageQuality,
  Pointer<FfiArena> arena,
);

/// Standalone region blur: applies a Gaussian blur to a region in the image.
///
/// Returns a `u8` status code (0 for success, see `FfiErrorCode`).
@Native<Uint8 Function(Pointer<Utf8>, Pointer<Utf8>, RectanglePayload, Uint8, Pointer<FfiArena>)>()
external int blur_region(
  Pointer<Utf8> imagePath,
  Pointer<Utf8> outputPath,
  RectanglePayload region,
  int imageQuality,
  Pointer<FfiArena> arena,
);

/// Standalone full-image blur: applies a Gaussian blur to the entire image.
///
/// Returns a `u8` status code (0 for success, see `FfiErrorCode`).
@Native<Uint8 Function(Pointer<Utf8>, Pointer<Utf8>, Uint8, Uint8, Pointer<FfiArena>)>()
external int blur(
  Pointer<Utf8> imagePath,
  Pointer<Utf8> outputPath,
  int radiusPx,
  int imageQuality,
  Pointer<FfiArena> arena,
);

/// Rotates an image by 90° increments (quarter turns).
///
/// `quarterTurns`: 0 = no-op, 1 = 90° CW, 2 = 180°, 3 = 270° CW. Values ≥ 4 are mod 4.
/// If `outputPath` is null, overwrites `imagePath`.
///
/// Returns a `u8` status code (0 for success, see `FfiErrorCode`).
@Native<Uint8 Function(Pointer<Utf8>, Pointer<Utf8>, Uint8, Uint8, Pointer<FfiArena>)>()
external int rotate(
  Pointer<Utf8> imagePath,
  Pointer<Utf8> outputPath,
  int quarterTurns,
  int imageQuality,
  Pointer<FfiArena> arena,
);

/// Converts an image to JPEG format at the specified quality.
///
/// Reads any supported format, writes JPEG. If `outputPath` is null, overwrites `imagePath`
/// (which must then have a .jpg/.jpeg extension).
///
/// Returns a `u8` status code (0 for success, see `FfiErrorCode`).
@Native<Uint8 Function(Pointer<Utf8>, Pointer<Utf8>, Uint8, Pointer<FfiArena>)>()
external int to_jpg(
  Pointer<Utf8> imagePath,
  Pointer<Utf8> outputPath,
  int imageQuality,
  Pointer<FfiArena> arena,
);

/// Resizes an image to exact `width × height` dimensions.
///
/// `filter`: 0 = Nearest, 1 = Triangle (bilinear), 2 = CatmullRom, 3 = Lanczos3.
/// If `outputPath` is null, overwrites `imagePath`.
///
/// Returns a `u8` status code (0 for success, see `FfiErrorCode`).
@Native<
  Uint8 Function(Pointer<Utf8>, Pointer<Utf8>, Uint32, Uint32, Uint8, Uint8, Pointer<FfiArena>)
>()
external int resize(
  Pointer<Utf8> imagePath,
  Pointer<Utf8> outputPath,
  int width,
  int height,
  int filter,
  int imageQuality,
  Pointer<FfiArena> arena,
);
