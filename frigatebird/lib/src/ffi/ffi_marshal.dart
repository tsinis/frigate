// Co-locates the FfiArenaHandle with the marshaller that creates it. The index lookup is O(1) and safe by design.
// ignore_for_file: prefer-single-declaration-per-file, avoid-enum-values-by-index, prefer-boolean-prefixes

import 'dart:convert' show utf8;
import 'dart:ffi';
import 'dart:typed_data' show BytesBuilder, Uint8List;

import '../model/draw_element.dart';
import '../model/ffi_color.dart';
import 'ffi_abi.dart';
import 'ffi_arena.dart';
import 'ffi_element.dart';
import 'ffi_element_type.dart';

/// Safe handle for FFI memory spanning a render batch.
///
/// Owns the [elementsPtr], the [arenaPtr] (the struct itself), and the variable-length
/// [textBufferPtr] and [errorBufferPtr] that the arena points to. Exposes an idempotent [free]
/// method so the caller can guarantee no leaks from `try`/`finally`.
final class FfiArenaHandle {
  // Private constructor — only [FfiMarshal.encodeElements] should create handles. A public
  // constructor would let callers assemble mismatched pointers and call free() → double-free / UB.
  FfiArenaHandle._({
    required this.allocator,
    required this.elementsPtr,
    required this.count,
    required this.arenaPtr,
    required this.textBufferPtr,
    required this.errorBufferPtr,
  });

  final Allocator allocator;
  final Pointer<FfiElement> elementsPtr;
  final int count;
  final Pointer<FfiArena> arenaPtr;
  final Pointer<Uint8> textBufferPtr;
  final Pointer<Uint8> errorBufferPtr;

  bool _freed = false;

  void free() {
    if (_freed) return;
    _freed = true;
    if (elementsPtr != nullptr) allocator.free(elementsPtr);
    if (textBufferPtr != nullptr) allocator.free(textBufferPtr);
    if (errorBufferPtr != nullptr) allocator.free(errorBufferPtr);
    allocator.free(arenaPtr);
  }
}

/// Marshaller to convert between domain [DrawElement]s and raw [FfiElement]s.
sealed class FfiMarshal {
  /// Encodes a list of [DrawElement]s into native memory and builds a ready-to-use [FfiArena].
  ///
  /// Caller MUST call [FfiArenaHandle.free] on the returned object to prevent memory leaks.
  static FfiArenaHandle encodeElements(
    List<DrawElement> drawElements,
    Allocator allocator, {
    int errorCap = FfiAbi.errorCapBytes,
  }) {
    final elementsPtr = drawElements.isEmpty ? nullptr : allocator<FfiElement>(drawElements.length);
    final payloadBytes = BytesBuilder();

    try {
      for (final (i, item) in drawElements.indexed) {
        final ref = (elementsPtr + i).ref;

        // DrawElement is sealed with exactly 2 variants — exhaustive, cannot reach minimum of 3.
        // ignore: prefer-correct-switch-length
        switch (item) {
          case RectElement():
            assert(
              item.outlineThickness >= 0 && item.outlineThickness <= 255,
              'outlineThickness must be in 0..255',
            );
            assert(item.blur >= 0 && item.blur <= 255, 'blur must be in 0..255');
            assert(
              item.cornerRadius >= 0 && item.cornerRadius <= 65535,
              'cornerRadius must be in 0..65535',
            );

            (ref..tag = FfiElementType.rectangle.value).payload.rectangle
              ..x = item.x
              ..y = item.y
              ..width = item.width
              ..height = item.height
              ..rotationDeg = item.rotation
              ..fillColorArgb = item.fillColor.argb
              ..outlineColorArgb = item.outlineColor.argb
              ..outlineThickness = item.outlineThickness.clamp(0, 255)
              ..blur = item.blur.clamp(0, 255)
              ..cornerRadius = item.cornerRadius.clamp(0, 65535);

          case TextElement():
            assert(item.blur >= 0 && item.blur <= 255, 'blur must be in 0..255');

            final encoded = utf8.encode(item.text);
            // Offset captured *before* append so it points to the start of this element's text.
            (ref..tag = FfiElementType.text.value).payload.text
              ..x = item.x
              ..y = item.y
              ..height = item.height
              ..rotationDeg = item.rotation
              ..fillColorArgb = item.fillColor.argb
              ..blur = item.blur.clamp(0, 255)
              ..fontId = item.fontId
              ..textOffset = payloadBytes.length
              ..textLen = encoded.length;
            payloadBytes.add(encoded);
        }
      }

      final payloadTotal = payloadBytes.length;
      Pointer<Uint8> textBufferPtr = nullptr;
      if (payloadTotal > 0) {
        textBufferPtr = allocator<Uint8>(payloadTotal);
        try {
          textBufferPtr.asTypedList(payloadTotal).setAll(0, payloadBytes.toBytes());
        } on Object {
          allocator.free(textBufferPtr);

          rethrow;
        }
      }

      Pointer<Uint8> errorBufferPtr = nullptr;
      if (errorCap > 0) {
        try {
          errorBufferPtr = allocator<Uint8>(errorCap);
        } on Object {
          if (textBufferPtr != nullptr) allocator.free(textBufferPtr);

          rethrow;
        }
      }

      Pointer<FfiArena> arenaPtr;
      try {
        arenaPtr = allocator<FfiArena>();
        arenaPtr.ref
          ..textBuf = textBufferPtr
          ..textLen = payloadTotal
          ..imageBuf = nullptr
          ..imageLen = 0
          ..errorBuf = errorBufferPtr
          ..errorCap = errorCap;
      } on Object {
        if (textBufferPtr != nullptr) allocator.free(textBufferPtr);
        if (errorBufferPtr != nullptr) allocator.free(errorBufferPtr);

        rethrow;
      }

      return FfiArenaHandle._(
        allocator: allocator,
        arenaPtr: arenaPtr,
        count: drawElements.length,
        elementsPtr: elementsPtr,
        errorBufferPtr: errorBufferPtr,
        textBufferPtr: textBufferPtr,
      );
    } on Object {
      if (elementsPtr != nullptr) allocator.free(elementsPtr);

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
    final textBytes = payloadBufferPtr == nullptr
        ? Uint8List(0)
        : payloadBufferPtr.asTypedList(payloadBufferLen);

    final result = <DrawElement>[];
    for (int i = 0; i < count; i += 1) {
      final element = (elementsPtr + i).ref;
      final tag = element.tag;

      // Guard against tags that this Dart build doesn't know about (e.g. newer Rust binary).
      // `tag` is @Uint8 so it is always ≥ 0; only the upper bound matters.
      if (tag >= FfiElementType.values.length) continue;

      // DrawElement is sealed with exactly 2 variants — exhaustive, cannot reach minimum of 3.
      // ignore: prefer-correct-switch-length
      switch (FfiElementType.values[tag]) {
        case .rectangle:
          final rect = element.payload.rectangle;
          result.add(
            RectElement(
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
            ),
          );

        case .text:
          final txt = element.payload.text;
          final start = txt.textOffset;
          final end = start + txt.textLen;
          // Guard against a corrupt or malicious text-slice reference.
          // `start` and `end` are u32-derived so always ≥ 0; only the upper bound matters.
          if (end < start || end > textBytes.length) continue;
          // Use a view (no copy) over the shared text buffer — `sublist` would allocate.
          final text = utf8.decode(
            textBytes.buffer.asUint8List(textBytes.offsetInBytes + start, txt.textLen),
          );
          result.add(
            TextElement(
              blur: txt.blur,
              fillColor: FfiColor(txt.fillColorArgb),
              fontId: txt.fontId,
              fontSize: txt.height,
              rotation: txt.rotationDeg,
              text: text,
              x: txt.x,
              y: txt.y,
            ),
          );
      }
    }

    return result;
  }
}
