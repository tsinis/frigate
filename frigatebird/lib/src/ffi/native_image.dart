import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Owns image bytes in native heap (malloc).
///
/// WHY native heap instead of Dart Uint8List: Dart GC can relocate Uint8List at any time
/// (compacting GC). Native memory has a stable address — safe to share between isolates (as int)
/// and with Rust FFI (as Pointer) without copies.
///
/// Flutter reads via [bytes] (zero-copy view). Rust reads via [address] (zero-copy pointer
/// reconstruction).
///
/// Lifecycle: create once at image load, dispose when done. Reading [address] or [bytes] after
/// [dispose] throws [StateError] — a silent use-after-free footgun would be much worse than a
/// loud crash. NEVER dispose while an export is in progress.
final class NativeImage {
  NativeImage._(this._pointer, this.height, this.length, this.width)
    : _bytes = _pointer.asTypedList(length);

  /// Copy [dartBytes] into native heap once. The source can then be GC'd.
  // ignore: avoid-non-empty-constructor-bodies, this factory constructor is the only way to create a NativeImage.
  factory NativeImage.fromBytes(Uint8List dartBytes, {required int height, required int width}) {
    final length = dartBytes.length;
    final pointer = malloc<Uint8>(length)..asTypedList(length).setRange(0, length, dartBytes);

    return NativeImage._(pointer, height, length, width);
  }

  /// Byte length of the encoded image (PNG/JPEG bytes, NOT raw RGBA).
  final int length;

  /// Image width in pixels — source of truth for document-space coordinates.
  final int width;

  /// Image height in pixels — source of truth for document-space coordinates.
  final int height;

  final Uint8List _bytes;
  final Pointer<Uint8> _pointer;
  bool _isDisposed = false;

  /// Zero-copy view of native memory for Flutter widgets.
  ///
  /// WHY asTypedList and not Uint8List.fromList: asTypedList creates a VIEW backed by native
  /// memory, not a copy. The native memory is stable (malloc, not GC-managed), so the view
  /// remains valid until [dispose]. After dispose, reading throws [StateError].
  Uint8List get bytes {
    _throwIfDisposed();

    return _bytes;
  }

  /// Raw pointer address as int — safe to send between isolates.
  ///
  /// WHY int and not Pointer: `Pointer` cannot cross isolate boundaries. int can. Reconstruct with
  /// `Pointer.fromAddress(address)`. After dispose, reading throws [StateError] so a caller can
  /// never accidentally hand a freed pointer to Rust.
  int get address {
    _throwIfDisposed();

    return _pointer.address;
  }

  /// Free native memory. Idempotent — calling twice is safe. After this, [address] and [bytes]
  /// throw [StateError].
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    malloc.free(_pointer);
  }

  void _throwIfDisposed() {
    if (_isDisposed) {
      throw StateError('NativeImage used after dispose');
    }
  }
}
