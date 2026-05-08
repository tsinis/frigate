import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'ffi_arena.dart';

/// Owns a heap-allocated [FfiArena] AND every buffer hanging off it.
///
/// Life-cycle:
///   final arena = FfiArenaHandle.allocate();
///   try {
///     ffi.some_call(..., arena.ptr, ...);
///   } finally {
///     arena.free();
///   }
///
/// Do NOT pass [ptr] to code that outlives this handle — after [free] the
/// pointer is dangling.
final class FfiArenaHandle {
  const FfiArenaHandle._(this.ptr);

  /// Allocates a zero-initialized arena with an error buffer attached.
  /// Text and image buffers stay `nullptr`/0 — callers that need them
  /// should populate the fields before the FFI call and free them in [free]
  /// (or extend this class).
  // ignore: avoid-non-empty-constructor-bodies, it's a factory that needs to do work.
  factory FfiArenaHandle.allocate({int errorCapacity = defaultErrorCapacity}) {
    assert(errorCapacity > 0, 'errorCapacity must be positive');

    final arenaPtr = calloc<FfiArena>(); // Zeroed.
    final errorBuf = calloc<Uint8>(errorCapacity); // Zeroed.
    arenaPtr.ref
      ..errorBuf = errorBuf
      ..errorCap = errorCapacity;

    // A textBuf, textLen, imageBuf, imageLen are already null/0 from calloc.
    return FfiArenaHandle._(arenaPtr);
  }

  /// Default error-buffer capacity. 512 bytes covers every error message
  /// Rust currently writes (longest is ~50 chars). Bump only if needed.
  static const defaultErrorCapacity = 512;

  /// Pointer to the C-side struct. Pass to FFI calls as `arena.ptr`.
  final Pointer<FfiArena> ptr;

  /// Reads the NUL-terminated UTF-8 message Rust wrote into `errorBuf`.
  /// Returns `null` if the buffer is missing, empty, or starts with NUL.
  ///
  /// `toDartString()` (without `length:`) scans for the first NUL byte and
  /// stops there, which matches Rust's `write_error_to_arena` contract.
  // ignore: prefer-getter-over-method, potentially useful for future extensions.
  String? readErrorMessage() {
    final i = ptr.ref;
    if (i.errorBuf == nullptr || i.errorCap == 0) return null;
    if (i.errorBuf.value == 0) return null; // Empty / nothing written.

    return i.errorBuf.cast<Utf8>().toDartString();
  }

  /// Frees the error buffer, any text/image buffers that were attached, and
  /// the arena struct itself. Safe to call once. Calling twice is undefined.
  void free() {
    final i = ptr.ref;
    if (i.errorBuf != nullptr) calloc.free(i.errorBuf);
    if (i.textBuf != nullptr) calloc.free(i.textBuf);
    if (i.imageBuf != nullptr) calloc.free(i.imageBuf);
    calloc.free(ptr);
  }
}
