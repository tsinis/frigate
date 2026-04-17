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
  });

  final Allocator allocator;
  final int count;
  final Pointer<FfiElement> elementsPtr;
  final int textBufferLen;
  final Pointer<Uint8> textBufferPtr;

  bool _isFreed = false;

  bool get hasText => textBufferLen > 0;

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
