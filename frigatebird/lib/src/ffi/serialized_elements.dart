import 'dart:ffi';

import 'ffi_element.dart';

/// Owning handle for the native memory backing a serialized `List<DrawElement>`.
///
/// Holds pointers to (a) a contiguous [FfiElement] array of [count] entries and (b) an optional
/// shared UTF-8 text buffer used by `TextElement`s. Caller MUST [free] both when done.
final class SerializedElements {
  const SerializedElements({
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

  bool get hasText => textBufferLen > 0;

  void free() {
    allocator.free(elementsPtr);
    if (textBufferPtr != nullptr) allocator.free(textBufferPtr);
  }
}
