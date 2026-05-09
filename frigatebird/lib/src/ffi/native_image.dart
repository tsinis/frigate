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
/// Life-cycle: create once at image load, dispose when done. Reading [address] or [bytes] after
/// [dispose] throws [StateError] — a silent use-after-free footgun would be much worse than a
/// loud crash. NEVER dispose while an export is in progress.
///
/// **Dangling-alias caveat:** the dispose-throws guard fires *at the getter call site only*. If
/// a caller has already captured the [Uint8List] returned by [bytes] or the [int] returned by
/// [address], that captured reference is *not* invalidated by [dispose] — the `Uint8List` still
/// aliases freed heap memory, and the `int` still holds the old numeric address. Using either
/// after [dispose] is undefined behavior and the VM cannot detect it. Rule of thumb: treat every
/// `bytes`/`address` read as valid only for the duration of a single synchronous span; never
/// hold one across an `await` or an isolate hop without also keeping the [NativeImage] alive.
final class NativeImage implements Finalizable {
  NativeImage._(this._pointer, this.height, this.length, this.width)
    : _bytes = _pointer.asTypedList(length);

  /// Copy [dartBytes] into native heap once. The source can then be GC'd.
  // ignore: avoid-non-empty-constructor-bodies, this factory constructor is the only way to create a NativeImage.
  factory NativeImage.fromBytes(Uint8List dartBytes, {required int height, required int width}) {
    final length = dartBytes.length;
    final pointer = calloc<Uint8>(length)..asTypedList(length).setRange(0, length, dartBytes);

    final image = NativeImage._(pointer, height, length, width);
    image._attach(); // ignore: cascade_invocations, attach is a separate step after construction.

    return image;
  }

  /// Byte length of the encoded image (PNG/JPEG bytes, NOT raw RGBA).
  final int length;

  /// Image width in pixels — source of truth for document-space coordinates.
  final int width;

  /// Image height in pixels — source of truth for document-space coordinates.
  final int height;

  static final _finalizer = NativeFinalizer(calloc.nativeFree);

  final Uint8List _bytes;
  final Pointer<Uint8> _pointer;
  bool _isDisposed = false;

  void _attach() {
    _finalizer.attach(this, _pointer.cast<Void>(), detach: this);
  }

  /// Zero-copy view of native memory for Flutter widgets.
  ///
  /// WHY asTypedList and not Uint8List.fromList: asTypedList creates a VIEW backed by native
  /// memory, not a copy. The native memory is stable (malloc, not GC-managed), so the view
  /// remains valid until [dispose]. Calling this getter after [dispose] throws [StateError] —
  /// but a `Uint8List` already obtained from a prior call is *not* re-checked; it keeps
  /// aliasing the (now freed) native buffer and must be dropped before [dispose] runs.
  Uint8List get bytes {
    _throwIfDisposed();

    return _bytes;
  }

  /// Raw pointer address as int — safe to send between isolates.
  ///
  /// WHY int and not Pointer: `Pointer` cannot cross isolate boundaries. int can. Reconstruct with
  /// `Pointer.fromAddress(address)`. Calling this getter after [dispose] throws [StateError] so
  /// the read itself can't hand a freed pointer to Rust — but an `int` *already captured* from a
  /// previous call is just a scalar and silently goes stale when [dispose] frees the heap. Keep
  /// the [NativeImage] alive for the entire span you're using the address (across isolate
  /// messages in particular).
  int get address {
    _throwIfDisposed();

    return _pointer.address;
  }

  /// Free native memory. Idempotent — calling twice is safe. After this, [address] and [bytes]
  /// throw [StateError] at the getter call site. The throw does *not* retroactively invalidate
  /// any `Uint8List` view or `int` address the caller captured earlier; the caller must drop
  /// those references themselves before calling [dispose].
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _finalizer.detach(this);
    calloc.free(_pointer);
  }

  void _throwIfDisposed() {
    if (_isDisposed) throw StateError('NativeImage used after dispose');
  }
}
