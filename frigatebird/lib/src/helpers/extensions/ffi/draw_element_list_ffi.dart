import 'dart:convert' show utf8;
import 'dart:ffi';
import 'dart:typed_data' show BytesBuilder;

import '../../../ffi/ffi_element.dart';
import '../../../ffi/serialized_elements.dart';
import '../../../model/draw_element.dart';

/// Serialize a list of [DrawElement]s into native memory: a contiguous [FfiElement] array plus a
/// shared UTF-8 text buffer (only allocated when the list contains [TextElement]s).
///
/// Ownership: the returned [SerializedElements] owns both pointers; caller MUST call
/// `serialized.free()` to release them.
extension DrawElementListFfi on List<DrawElement> {
  SerializedElements toNative(Allocator allocator) {
    // The elements pointer is allocated BEFORE the try-block so the `final` binding is in scope
    // for the catch. Anything that can throw after this point (text buffer allocation, UTF-8
    // encoding) must free this pointer — otherwise the SerializedElements wrapper is never
    // returned and the caller can't reach it.
    final elementsPtr = allocator<FfiElement>(length);
    try {
      final textBytes = BytesBuilder();
      for (int i = 0; i < length; i += 1) {
        final element = this[i];
        final ref = (elementsPtr + i).ref;
        _writeCommonFields(ref, element);
        _writeTypeSpecificFields(ref, element, textBytes);
      }

      final textTotal = textBytes.length;
      Pointer<Uint8> textBufferPtr = nullptr;
      if (textTotal > 0) {
        textBufferPtr = allocator<Uint8>(textTotal);
        try {
          textBufferPtr.asTypedList(textTotal).setAll(0, textBytes.toBytes());
        } on Object {
          allocator.free(textBufferPtr);
          rethrow;
        }
      }

      return SerializedElements(
        allocator: allocator,
        count: length,
        elementsPtr: elementsPtr,
        textBufferLen: textTotal,
        textBufferPtr: textBufferPtr,
      );
    } on Object {
      allocator.free(elementsPtr);
      rethrow;
    }
  }
}

/// Fields every element shares. `width` and `height` are reused across shape kinds — for text,
/// `height` is the font em-box size and `width` stays 0.
///
/// Rotation is written as integer degrees; Rust does the degrees → radians conversion at render
/// time so the Dart-side `int` stays in SMI range (no boxing).
void _writeCommonFields(FfiElement ref, DrawElement element) {
  ref
    ..elementType = element.elementType.value
    ..x = element.x
    ..y = element.y
    ..width = element.width
    ..height = element.height
    ..rotationDeg = element.rotation
    ..fillColorArgb = element.fillColor.argb
    ..outlineColorArgb = element.outlineColor.argb
    ..outlineThickness = element.outlineThickness
    ..blur = element.blur
    // Text-specific defaults; overridden below for TextElement.
    ..textOffset = 0
    ..textLength = 0;
}

/// Fields that only apply to specific subtypes. Exhaustive over the sealed `DrawElement` — the
/// compiler guarantees we handle every variant (and flags adding a new one).
void _writeTypeSpecificFields(FfiElement ref, DrawElement element, BytesBuilder textBytes) {
  // ignore: prefer-correct-switch-length, adding a 3rd shape type will bump us past the threshold.
  switch (element) {
    case RectElement():
      // Width/height are already written by _writeCommonFields — rectangles have no extra state.
      break;

    case TextElement():
      final offset = textBytes.length;
      final encoded = utf8.encode(element.text);
      textBytes.add(encoded);
      ref
        ..textOffset = offset
        ..textLength = encoded.length;
  }
}
