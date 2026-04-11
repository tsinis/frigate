// ignore_for_file: prefer-named-parameters, prefer-static-class
// ignore_for_file: non_constant_identifier_names, prefer-typedefs-for-callbacks

/// Hand-written `@Native()` FFI bindings for the Rust crate `frigate_draw`.
///
/// NOT code-generated — ffigen is not used. The `@Native()` annotation auto-resolves the compiled
/// Rust library via the code asset system (`native_toolchain_rust` + build hook), so no
/// `DynamicLibrary.open()` needed.
///
/// Symbol names (snake_case) MUST match the Rust `#[no_mangle] pub extern "C"` function names
/// exactly. Positional parameters are required by the C ABI.
@DefaultAsset('package:frigate_draw/src/ffi/bindings.dart')
library;

import 'dart:ffi';

import 'byte_buffer.dart';
import 'ffi_rect_element.dart';

/// Render rectangle overlays onto a source image and encode as JPEG.
///
/// Called from a background isolate (via compute) — never on the UI thread.
/// Rust decodes the source image (PNG/JPEG), draws stroked rects with
/// tiny-skia, and encodes the composited result as JPEG.
///
/// Rect coordinates are **normalized** (0.0–1.0 relative to image size).
/// Rust denormalizes using decoded image dimensions — no width/height
/// params needed, eliminates Flutter↔Rust decoder dimension mismatch.
///
/// Memory contract:
/// - [imgPtr] + [imgLen]: caller-owned source image bytes (read-only by Rust).
/// - [rectsPtr] + [rectsCount]: caller-owned FfiRectElement array (read-only).
/// - Return value: Rust-allocated ByteBuffer. Caller MUST check for null
///   (indicates panic in Rust), then free via [free_bytes].
@Native<
  ByteBuffer Function(
    Pointer<Uint8>, // Encoded source image bytes (PNG/JPEG).
    Size, // Byte length of source image.
    Pointer<FfiRectElement>, // Array of normalized rectangle overlays.
    Size, // Number of rects in the array.
    Uint8, // Output JPEG quality (0 to 100).
  )
>()
external ByteBuffer export_image(
  Pointer<Uint8> imgPtr,
  int imgLen,
  Pointer<FfiRectElement> rectsPtr,
  int rectsCount,
  int jpegQuality,
);

/// Free a Rust-allocated byte buffer (returned by [export_image]).
///
/// Rust created the buffer via `into_boxed_slice()` + `Box::into_raw()`,
/// guaranteeing capacity == len. This function reconstructs a `Vec` (via
/// `Vec::from_raw_parts`) and drops it, returning the memory to the allocator.
/// Null pointers are safely ignored (panic case from [export_image]).
///
/// `isLeaf: true` — this function is trivial (reconstruct `Vec`, drop), never calls back into Dart,
/// and completes in nanoseconds. Safe to freeze GC for the duration.
///
/// Signature: two args (ptr + len) — NOT compatible with `NativeFinalizerFunction` (single
/// `Pointer<Void>` arg). That is why we call this explicitly (Option B) rather than using
/// `asTypedList(finalizer:)`.
@Native<Void Function(Pointer<Uint8>, Size)>(isLeaf: true)
external void free_bytes(Pointer<Uint8> ptr, int len);
