// ignore_for_file: avoid-collection-mutating-methods, omit-local-variable-types

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// Owns image bytes in native heap (malloc).
///
/// WHY native heap instead of Dart Uint8List: Dart GC can relocate Uint8List at any time
/// (compacting GC). Native memory has a stable address — safe to share between isolates (as int)
/// and with Rust FFI (as Pointer) without copies.
///
/// Flutter reads via [bytes] (zero-copy view). Rust reads via [address] (zero-copy pointer
/// reconstruction).
///
/// Lifecycle: create once at image load, dispose when done. NEVER dispose while an export is in
/// progress.
final class NativeImage {
  NativeImage._(this._ptr, this.height, this.length, this.width);

  /// Copy [dartBytes] into native heap once. The source can then be GC'd.
  // ignore: avoid-non-empty-constructor-bodies, this factory constructor is the only way to create a NativeImage.
  factory NativeImage.fromBytes(Uint8List dartBytes, {required int height, required int width}) {
    final len = dartBytes.length;
    final ptr = malloc<Uint8>(len)..asTypedList(len).setRange(0, len, dartBytes);

    return NativeImage._(ptr, height, len, width);
  }

  /// Byte length of the encoded image (PNG/JPEG bytes, NOT raw RGBA).
  final int length;

  /// Image width in pixels — source of truth for document-space coordinates.
  final int width;

  /// Image height in pixels — source of truth for document-space coordinates.
  final int height;

  /// Zero-copy view of native memory for Flutter widgets.
  ///
  /// WHY asTypedList and not Uint8List.fromList: asTypedList creates a VIEW backed by native
  /// memory, not a copy. The native memory is stable (malloc, not GC-managed), so the view remains
  /// valid until [dispose].
  // ignore: avoid-explicit-type-declaration, it's a self-documenting Uint8List view.
  late final Uint8List bytes = _ptr.asTypedList(length);

  /// Raw pointer address as int — safe to send between isolates.
  ///
  /// WHY int and not Pointer: `Pointer` cannot cross isolate boundaries. int can. Reconstruct with
  /// `Pointer.fromAddress(address)`.
  int get address => _ptr.address;

  final Pointer<Uint8> _ptr;

  bool _isDisposed = false;

  /// Free native memory. After this, [bytes] and any pointer from [address] become invalid
  /// (use-after-free).
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    malloc.free(_ptr);
  }
}
