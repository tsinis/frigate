// Co-locates the FfiArenaHandle with the marshaller that creates it. The index lookup is O(1) and safe by design.
// ignore_for_file: prefer-single-declaration-per-file, avoid-enum-values-by-index, prefer-boolean-prefixes

import 'dart:convert' show utf8;
import 'dart:ffi';
import 'dart:typed_data' show BytesBuilder, Float64x2List, Uint8List;

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart' show visibleForTesting;

import '../model/draw_element.dart';
import '../model/ffi_color.dart';
import 'ffi_abi.dart';
import 'ffi_allocator_utils.dart';
import 'ffi_arena_handle.dart';
import 'ffi_element.dart';
import 'ffi_element_type.dart';

/// Safe handle for FFI memory spanning a render batch of [FfiElement]s.
///
/// Owns the [elementsPtr] and the variable-length [textBufferPtr]. Holds an [FfiArenaHandle]
/// for error reporting and passing text/image buffer pointers to Rust.
final class FfiElementsHandle implements Finalizable {
  FfiElementsHandle._({
    required this.allocator,
    required this.elementsPtr,
    required this.count,
    required this.arena,
    required this.textBufferPtr,
    required this.polygonVerticesPtrs,
  });

  final Allocator allocator;
  final Pointer<FfiElement> elementsPtr;
  final int count;
  final FfiArenaHandle arena;
  final Pointer<Uint8> textBufferPtr;
  final List<Pointer<Double>> polygonVerticesPtrs;

  static final _finalizer = NativeFinalizer(malloc.nativeFree);

  bool _freed = false;

  /// Frees the elements array, the text buffer, and the inner arena.
  void free() {
    if (_freed) return;
    _freed = true;
    if (isMallocCompatible(allocator)) _finalizer.detach(this);
    if (elementsPtr != nullptr) allocator.free(elementsPtr);
    if (textBufferPtr != nullptr) allocator.free(textBufferPtr);
    for (final ptr in polygonVerticesPtrs) {
      if (ptr != nullptr) allocator.free(ptr);
    }
    arena.free();
  }
}

/// Marshaller to convert between domain [DrawElement]s and raw [FfiElement]s.
sealed class FfiMarshal {
  /// Encodes a list of [DrawElement]s into native memory and builds a ready-to-use [FfiElementsHandle].
  ///
  /// Caller MUST call `FfiElementsHandle.free` on the returned object to prevent memory leaks.
  /// If a custom [allocator] is provided, it MUST be malloc-compatible if automatic
  /// finalization (fallback cleanup) is expected.
  static FfiElementsHandle encodeElements(
    List<DrawElement> drawElements,
    Allocator allocator, {
    int errorCap = FfiAbi.errorCapBytes,
  }) {
    final elementsPtr = drawElements.isEmpty ? nullptr : allocator<FfiElement>(drawElements.length);
    final payloadBytes = BytesBuilder();
    final polygonVerticesPtrs = <Pointer<Double>>[];
    Pointer<Uint8> textBufferPtr = nullptr;

    try {
      for (final (i, item) in drawElements.indexed) {
        final ref = (elementsPtr + i).ref;

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

          case OvalElement():
            assert(
              item.outlineThickness >= 0 && item.outlineThickness <= 255,
              'outlineThickness must be in 0..255',
            );
            assert(item.blur >= 0 && item.blur <= 255, 'blur must be in 0..255');

            (ref..tag = FfiElementType.oval.value).payload.oval
              ..x = item.x
              ..y = item.y
              ..width = item.width
              ..height = item.height
              ..rotationDeg = item.rotation
              ..fillColorArgb = item.fillColor.argb
              ..outlineColorArgb = item.outlineColor.argb
              ..outlineThickness = item.outlineThickness.clamp(0, 255)
              ..blur = item.blur.clamp(0, 255);

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

          case PolygonElement():
            assert(item.blur >= 0 && item.blur <= 255, 'blur must be in 0..255');
            assert(
              item.outlineThickness >= 0 && item.outlineThickness <= 255,
              'outlineThickness must be in 0..255',
            );

            final vertices = item.vertices;
            final vPtr = allocator<Double>(vertices.length * 2);
            polygonVerticesPtrs.add(vPtr);
            final vView = vPtr.asTypedList(vertices.length * 2);
            final vRaw = vertices.buffer.asFloat64List();
            final vOffset = vertices.offsetInBytes ~/ 8;
            vView.setRange(0, vertices.length * 2, vRaw, vOffset);

            (ref..tag = FfiElementType.polygon.value).payload.polygon
              ..x = item.x
              ..y = item.y
              ..width = item.width
              ..height = item.height
              ..verticesPtr = vPtr
              ..vertexCount = vertices.length
              ..fillColorArgb = item.fillColor.argb
              ..outlineColorArgb = item.outlineColor.argb
              ..outlineThickness = item.outlineThickness.clamp(0, 255)
              ..rotationDeg = item.rotation
              ..blur = item.blur.clamp(0, 255);

          case MaskRegionElement():
            assert(item.blur >= 0 && item.blur <= 255, 'blur must be in 0..255');
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
              ..cornerRadius = 0;
        }
      }

      final payloadTotal = payloadBytes.length;
      if (payloadTotal > 0) {
        textBufferPtr = allocator<Uint8>(payloadTotal);
        try {
          textBufferPtr.asTypedList(payloadTotal).setAll(0, payloadBytes.toBytes());
        } on Object {
          allocator.free(textBufferPtr);

          rethrow;
        }
      }

      final arena = FfiArenaHandle.allocate(errorCapacity: errorCap);
      arena.ptr.ref
        ..textBuf = textBufferPtr
        ..textLen = payloadTotal;

      final handle = FfiElementsHandle._(
        allocator: allocator,
        arena: arena,
        count: drawElements.length,
        elementsPtr: elementsPtr,
        polygonVerticesPtrs: polygonVerticesPtrs,
        textBufferPtr: textBufferPtr,
      );

      if (isMallocCompatible(allocator)) {
        if (elementsPtr != nullptr) {
          FfiElementsHandle._finalizer.attach(handle, elementsPtr.cast<Void>(), detach: handle);
        }
        if (textBufferPtr != nullptr) {
          FfiElementsHandle._finalizer.attach(handle, textBufferPtr.cast<Void>(), detach: handle);
        }
        for (final ptr in polygonVerticesPtrs) {
          if (ptr != nullptr) {
            FfiElementsHandle._finalizer.attach(handle, ptr.cast<Void>(), detach: handle);
          }
        }
      }

      return handle;
    } on Object {
      if (elementsPtr != nullptr) allocator.free(elementsPtr);
      if (textBufferPtr != nullptr) allocator.free(textBufferPtr);
      for (final ptr in polygonVerticesPtrs) {
        if (ptr != nullptr) allocator.free(ptr);
      }

      rethrow;
    }
  }

  /// Decodes [FfiElement]s back into domain [DrawElement]s.
  ///
  /// Returns a record with the successfully decoded `elements` and any `unknownTags`
  /// encountered (typically from a newer Rust binary).
  @visibleForTesting
  static ({List<DrawElement> elements, List<int> unknownTags}) decodeElements(
    Pointer<FfiElement> inElementsPtr,
    int count,
    Pointer<Uint8> payloadBufferPtr, {
    // Both params describe the same buffer — related names are intentional.
    // ignore: avoid-similar-names
    required int payloadBufferLen,
  }) {
    final textBytes = payloadBufferPtr == nullptr
        ? Uint8List(0)
        : payloadBufferPtr.asTypedList(payloadBufferLen);

    final outElements = <DrawElement>[];
    final outUnknownTags = <int>[];

    for (int i = 0; i < count; i += 1) {
      final element = (inElementsPtr + i).ref;
      final tag = element.tag;

      // Guard against tags that this Dart build doesn't know about (e.g. newer Rust binary).
      // `tag` is @Uint8 so it is always ≥ 0; only the upper bound matters.
      if (tag >= FfiElementType.values.length) {
        outUnknownTags.add(tag);

        continue;
      }

      switch (FfiElementType.values[tag]) {
        case .rectangle:
          final rect = element.payload.rectangle;
          // ignore: prefer-moving-to-variable, clarity over micro-optimization in a hot path.
          if (rect.fillColorArgb == FfiColor.transparent.argb &&
              // ignore: prefer-moving-to-variable, clarity over micro-optimization in a hot path.
              rect.outlineColorArgb == FfiColor.transparent.argb &&
              rect.outlineThickness == 0 &&
              rect.cornerRadius == 0 &&
              rect.blur > 0) {
            outElements.add(
              MaskRegionElement(
                blur: rect.blur,
                height: rect.height,
                rotation: rect.rotationDeg,
                width: rect.width,
                x: rect.x,
                y: rect.y,
              ),
            );
          } else {
            outElements.add(
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
          }

        case .oval:
          final oval = element.payload.oval;
          outElements.add(
            OvalElement(
              blur: oval.blur,
              fillColor: FfiColor(oval.fillColorArgb),
              height: oval.height,
              outlineColor: FfiColor(oval.outlineColorArgb),
              outlineThickness: oval.outlineThickness,
              rotation: oval.rotationDeg,
              width: oval.width,
              x: oval.x,
              y: oval.y,
            ),
          );

        case .text:
          final txt = element.payload.text;
          final start = txt.textOffset;
          final end = start + txt.textLen;
          // Guard against a corrupt or malicious text-slice reference.
          // `start` and `end` are u32-derived so always ≥ 0; only the upper bound matters.
          // Note: `start` and `txt.textLen` originate from u32 fields in Rust, and Dart uses
          // 64-bit ints, so `start + txt.textLen` cannot overflow.
          if (end < start || end > textBytes.length) {
            throw StateError('Corrupt text slice: offset=$start, len=${txt.textLen}');
          }
          // Use a view (no copy) over the shared text buffer — `sublist` would allocate.
          final text = utf8.decode(
            textBytes.buffer.asUint8List(textBytes.offsetInBytes + start, txt.textLen),
          );
          outElements.add(
            TextElement(
              blur: txt.blur,
              fillColor: FfiColor(txt.fillColorArgb),
              fontId: txt.fontId,
              height: txt.height,
              rotation: txt.rotationDeg,
              text: text,
              x: txt.x,
              y: txt.y,
            ),
          );

        case .polygon:
          final poly = element.payload.polygon;
          final polyCount = poly.vertexCount;
          if (polyCount > 0 && poly.verticesPtr == nullptr) {
            throw ArgumentError(
              'Malformed FFI polygon buffer: verticesPtr is null for polyCount=$polyCount',
            );
          }

          // Copy coordinate pairs from the native float buffer into a fresh heap list.
          // This ensures the vertex data is safe after the native memory gets freed.
          final polyRaw = poly.verticesPtr.asTypedList(polyCount * 2);
          final verts = Float64x2List(polyCount);
          // NOTE: This assumes Float64x2List layout is [x0, y0, x1, y1, ...] in double representation.
          // This is guaranteed on the Dart VM, but might vary on other platforms (e.g. dart2wasm).
          // Guarded by the PolygonElement round-trip unit tests.
          verts.buffer.asFloat64List().setAll(0, polyRaw);
          outElements.add(
            PolygonElement(
              blur: poly.blur,
              fillColor: FfiColor(poly.fillColorArgb),
              height: poly.height,
              outlineColor: FfiColor(poly.outlineColorArgb),
              outlineThickness: poly.outlineThickness,
              rotation: poly.rotationDeg,
              vertices: verts,
              width: poly.width,
              x: poly.x,
              y: poly.y,
            ),
          );
      }
    }

    return (elements: outElements, unknownTags: outUnknownTags);
  }
}
