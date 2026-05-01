import 'dart:convert' show utf8;
import 'dart:ffi';
import 'dart:typed_data' show BytesBuilder;

import '../model/draw_element.dart';
import '../model/ffi_color.dart';
import 'ffi_element.dart';
import 'ffi_element_type.dart';

/// Pointers to native memory containing a contiguous [FfiElement] array plus a shared UTF-8
/// text buffer.
typedef FfiElementBundle = ({
  int count,
  Pointer<FfiElement> elementsPtr,
  int payloadBufferLen,
  Pointer<Uint8> payloadBufferPtr,
});

/// Marshaller to convert between domain [DrawElement]s and raw [FfiElement]s.
sealed class FfiMarshal {
  /// Encodes a list of [DrawElement]s into native memory.
  ///
  /// Caller MUST free both `elementsPtr` and `payloadBufferPtr` via `allocator.free`.
  static FfiElementBundle encodeElements(List<DrawElement> drawElements, Allocator allocator) {
    final elementsPtr = allocator<FfiElement>(drawElements.length);
    final payloadBytes = BytesBuilder();

    try {
      for (final (i, item) in drawElements.indexed) {
        final ref = (elementsPtr + i).ref;

        // DrawElement is sealed with exactly 2 variants — exhaustive, cannot reach minimum of 3.
        // ignore: prefer-correct-switch-length
        switch (item) {
          case RectElement():
            (ref..tag = FfiElementType.rectangle.value).payload.rectangle
              ..x = item.x
              ..y = item.y
              ..width = item.width
              ..height = item.height
              ..rotationDeg = item.rotation
              ..fillColorArgb = item.fillColor.argb
              ..outlineColorArgb = item.outlineColor.argb
              ..outlineThickness = item.outlineThickness
              ..blur = item.blur
              ..cornerRadius = item.cornerRadius;

          case TextElement():
            final encoded = utf8.encode(item.text);
            (ref..tag = FfiElementType.text.value).payload.text
              ..x = item.x
              ..y = item.y
              ..width = item.width
              ..height = item.height
              ..rotationDeg = item.rotation
              ..fillColorArgb = item.fillColor.argb
              ..blur = item.blur
              ..fontId = item.fontId
              ..textOffset = payloadBytes.length
              ..textLen = encoded.length;
            payloadBytes.add(encoded);
        }
      }

      final payloadTotal = payloadBytes.length;
      Pointer<Uint8> payloadBufferPtr = nullptr;
      if (payloadTotal > 0) {
        payloadBufferPtr = allocator<Uint8>(payloadTotal);
        try {
          payloadBufferPtr.asTypedList(payloadTotal).setAll(0, payloadBytes.toBytes());
        } on Object {
          allocator.free(payloadBufferPtr);
          rethrow;
        }
      }

      return (
        count: drawElements.length,
        elementsPtr: elementsPtr,
        payloadBufferLen: payloadTotal,
        payloadBufferPtr: payloadBufferPtr,
      );
    } on Object {
      allocator.free(elementsPtr);
      rethrow;
    }
  }

  /// Decodes [FfiElement]s back into domain [DrawElement]s.
  static List<DrawElement> decodeElements(
    Pointer<FfiElement> elementsPtr,
    int count,
    Pointer<Uint8> payloadBufferPtr, {
    // Both params describe the same buffer — related names are intentional.
    // ignore: avoid-similar-names
    required int payloadBufferLen,
  }) {
    final textBytes = payloadBufferPtr.asTypedList(payloadBufferLen);

    return List.generate(count, (i) {
      final element = (elementsPtr + i).ref;
      final type = FfiElementType.values.firstWhere((candidate) => candidate.value == element.tag);

      if (type == .rectangle) {
        final rect = element.payload.rectangle;

        return RectElement(
          blur: rect.blur,
          cornerRadius: rect.cornerRadius,
          fillColor: FfiColor(rect.fillColorArgb),
          height: rect.height,
          outlineColor: FfiColor(rect.outlineColorArgb),
          outlineThickness: rect.outlineThickness,
          rotation: rect.rotationDeg,
          width: rect.width,
          x: rect.x,
          y: rect.y,
        );
      }

      final txt = element.payload.text;
      final text = utf8.decode(textBytes.sublist(txt.textOffset, txt.textOffset + txt.textLen));

      return TextElement(
        blur: txt.blur,
        fillColor: FfiColor(txt.fillColorArgb),
        fontId: txt.fontId,
        fontSize: txt.height,
        rotation: txt.rotationDeg,
        text: text,
        x: txt.x,
        y: txt.y,
      );
    });
  }
}
