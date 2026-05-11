// ignore_for_file: avoid-non-empty-constructor-bodies
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart' show visibleForTesting;

/// Owns image bytes in native heap (malloc).
///
/// WHY native heap instead of Dart Uint8List: Dart GC can relocate Uint8List at any time
/// (compacting GC). Native memory has a stable address — safe to share between isolates (as int)
/// and with Rust FFI (as Pointer) without copies.
///
/// Flutter reads via [bytes] (zero-copy view). Rust reads via [address] (zero-copy pointer
/// reconstruction).
///
/// Life-cycle: create once at image load. Memory is freed automatically via NativeFinalizer
/// when BOTH the wrapper and the [bytes] view are GC'ed. The wrapper holds a reference to the
/// view, and the view is attached to the same finalizer.
final class NativeImage implements Finalizable {
  NativeImage._(this._pointer, this._bytes, this.height, this.length, this.width, this._allocator);

  /// Copy [src] into native heap once. The source can then be GC'd.
  factory NativeImage.fromBytes(Uint8List src, {required int height, required int width}) =>
      NativeImage._withAllocator(src, allocator: malloc, height: height, width: width);

  @visibleForTesting
  factory NativeImage.testWithAllocator(
    Uint8List src, {
    required int height,
    required int width,
    required Allocator allocator,
  }) => NativeImage._withAllocator(src, allocator: allocator, height: height, width: width);

  factory NativeImage._withAllocator(
    Uint8List src, {
    required int height,
    required int width,
    required Allocator allocator,
  }) {
    final ptr = allocator<Uint8>(src.length);
    final view = ptr.asTypedList(src.length)..setAll(0, src);

    final image = NativeImage._(ptr, view, height, src.length, width, allocator);
    if (allocator == malloc) {
      _finalizer.attach(image, ptr.cast<Void>(), detach: image);
    }

    return image;
  }

  /// Byte length of the encoded image (PNG/JPEG bytes, NOT raw RGBA).
  final int length;

  /// Image width in pixels — source of truth for document-space coordinates.
  final int width;

  /// Image height in pixels — source of truth for document-space coordinates.
  final int height;

  static final _finalizer = NativeFinalizer(malloc.nativeFree.cast<NativeFinalizerFunction>());

  final Uint8List _bytes;
  final Pointer<Uint8> _pointer;
  final Allocator _allocator;
  bool _isDisposed = false;

  /// Zero-copy view of native memory for Flutter widgets.
  ///
  /// The memory stays alive as long as this view is alive.
  Uint8List get bytes {
    _throwIfDisposed();

    return _bytes;
  }

  /// Raw pointer address as int — safe to send between isolates.
  ///
  /// The memory stays alive as long as the [bytes] view is alive (which is kept
  /// alive by this wrapper).
  int get address {
    _throwIfDisposed();

    return _pointer.address;
  }

  /// Frees the native memory immediately.
  ///
  /// After calling [dispose], using [bytes] or [address] will throw a [StateError].
  /// The finalizer is detached to prevent a double-free.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    if (_allocator == malloc) {
      _finalizer.detach(this);
    }
    _allocator.free(_pointer);
  }

  void _throwIfDisposed() {
    if (_isDisposed) throw StateError('NativeImage used after dispose');
  }
}
