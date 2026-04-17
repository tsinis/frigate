import 'dart:ffi';

import 'ffi_element.dart';

/// Owning handle for the native memory backing a serialized `List<DrawElement>`.
///
/// Holds pointers to (a) a contiguous [FfiElement] array of [count] entries and (b) an optional
/// shared UTF-8 text buffer used by `TextElement`s. Caller MUST call [free] when done; a second
/// call is safe — [free] is idempotent (mirrors `NativeImage.dispose`) so callers can use the
/// classic try/finally pattern without worrying about whether an inner `finally` already fired.
final class SerializedElements {
  SerializedElements({
    required this.allocator,
    required this.count,
    required this.elementsPtr,
    required this.textBufferLen,
    required this.textBufferPtr,
  }) : assert(
         (textBufferLen == 0) == (textBufferPtr == nullptr),
         'textBufferLen and textBufferPtr must agree: both zero/null or both non-zero/non-null',
       );

  final Allocator allocator;
  final int count;
  final Pointer<FfiElement> elementsPtr;
  final int textBufferLen;
  final Pointer<Uint8> textBufferPtr;

  bool _isFreed = false;

  /// Single source of truth for "is there a text buffer?" — the pointer. Keeping this aligned
  /// with [free]'s own `textBufferPtr != nullptr` guard prevents the two from drifting.
  bool get hasText => textBufferPtr != nullptr;

  /// Release both native allocations. Idempotent: subsequent calls are no-ops so callers can
  /// safely put a `finally { serialized.free(); }` next to an explicit `serialized.free()`
  /// earlier in the happy path without risking a double-free.
  void free() {
    if (_isFreed) return;
    _isFreed = true;
    allocator.free(elementsPtr);
    if (textBufferPtr != nullptr) allocator.free(textBufferPtr);
  }
}
