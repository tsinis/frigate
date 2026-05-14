// ignore_for_file: prefer-trailing-comma
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:frigatebird/src/ffi/ffi_marshal.dart';
import 'package:frigatebird/src/ffi/ffi_test_helpers.dart';
import 'package:frigatebird/src/model/draw_element.dart';
import 'package:frigatebird/src/model/ffi_color.dart';
import 'package:test/test.dart';

void main() {
  group('FfiMarshal round-trip', () {
    test('Rectangle round-trip via Rust echo', () {
      const rect = RectElement(
        blur: 2,
        cornerRadius: 10,
        fillColor: .black,
        height: 50,
        outlineColor: FfiColor(0xFF00FF00),
        outlineThickness: 5,
        rotation: 90,
        width: 100,
        x: 10,
        y: 20,
      );

      final bundle = FfiMarshal.encodeElements([rect], malloc);
      try {
        final echoedPtr = ffi_echo_element(bundle.elementsPtr);
        final decodeResult = FfiMarshal.decodeElements(
          echoedPtr,
          bundle.count,
          bundle.textBufferPtr,
          payloadBufferLen: bundle.arena.ptr.ref.textLen,
        );
        final decoded = decodeResult.elements;

        expect(decoded.length, 1);
        expect(decoded.first, isA<RectElement>(), reason: 'decoded element type');
        final result = decoded.whereType<RectElement>().first;
        expect(result.x, rect.x);
        expect(result.y, rect.y);
        expect(result.width, rect.width);
        expect(result.height, rect.height);
        expect(result.rotation, rect.rotation);
        expect(result.fillColor.argb, rect.fillColor.argb);
        expect(result.outlineColor.argb, rect.outlineColor.argb);
        expect(result.outlineThickness, rect.outlineThickness);
        expect(result.blur, rect.blur);
        expect(result.cornerRadius, rect.cornerRadius);
      } finally {
        bundle.free();
      }
    });

    test('Text round-trip via Rust echo', () {
      const text = TextElement(
        blur: 1,
        fillColor: FfiColor(0xFF0000FF),
        fontId: 42,
        height: 32,
        rotation: -45,
        text: 'Hello FFI',
        x: 5,
        y: 15,
      );

      final bundle = FfiMarshal.encodeElements([text], malloc);
      try {
        final echoedPtr = ffi_echo_element(bundle.elementsPtr);
        final decodeResult = FfiMarshal.decodeElements(
          echoedPtr,
          bundle.count,
          bundle.textBufferPtr,
          payloadBufferLen: bundle.arena.ptr.ref.textLen,
        );
        final decoded = decodeResult.elements;

        expect(decoded.length, 1);
        expect(decoded.first, isA<TextElement>(), reason: 'decoded element type');
        final result = decoded.whereType<TextElement>().first;
        expect(result.text, text.text);
        expect(result.x, text.x);
        expect(result.y, text.y);
        expect(result.rotation, text.rotation);
        expect(result.fillColor.argb, text.fillColor.argb);
        expect(result.fontSize, text.fontSize);
        expect(result.blur, text.blur);
        expect(result.fontId, text.fontId);
      } finally {
        bundle.free();
      }
    });

    test('Mixed elements round-trip', () {
      final elements = [
        const RectElement(height: 10, width: 10, x: 0, y: 0),
        const TextElement(text: 'A', x: 1, y: 1),
        const RectElement(cornerRadius: 2, height: 5, width: 5, x: 2, y: 2),
        const TextElement(height: 40, text: 'Longer string', x: 3, y: 3),
      ];

      final bundle = FfiMarshal.encodeElements(elements, malloc);
      try {
        final echoedPtr = ffi_echo_element(bundle.elementsPtr);
        final decodeResult = FfiMarshal.decodeElements(
          echoedPtr,
          bundle.count,
          bundle.textBufferPtr,
          payloadBufferLen: bundle.arena.ptr.ref.textLen,
        );
        final decoded = decodeResult.elements;

        expect(decoded.length, elements.length);
        for (final (i, item) in elements.indexed) {
          expect(decoded[i].toString(), item.toString());
        }
      } finally {
        bundle.free();
      }
    });
  });

  group('FfiMarshal.encodeElements failure handling', () {
    test('frees the elements array when the payload buffer allocation fails', () {
      // 1st allocation (elements) succeeds, 2nd (text buffer) throws → elements must be freed.
      final allocator = _FailingAllocator(failAfter: 1);
      final inputs = <DrawElement>[const TextElement(text: 'hi', x: 0, y: 0)];
      expect(
        () => FfiMarshal.encodeElements(inputs, allocator),
        throwsException,
        reason: 'mock OOM propagates',
      );
      expect(
        allocator.freedCount,
        allocator.succeededAllocations,
        reason: 'every successful allocation before the failure must be freed',
      );
    });

    test('frees nothing extra on the happy path (baseline)', () {
      final allocator = _FailingAllocator(failAfter: 10);
      final inputs = <DrawElement>[const TextElement(text: 'hi', x: 0, y: 0)];
      final bundle = FfiMarshal.encodeElements(inputs, allocator);
      expect(allocator.freedCount, isZero, reason: 'no frees until manual free()');
      bundle.free();
      expect(
        allocator.freedCount,
        allocator.succeededAllocations,
        reason: 'manual free releases every successful allocation',
      );
    });

    test('manual free is idempotent (second call is a no-op, not a double-free)', () {
      final allocator = _FailingAllocator(failAfter: 10);
      final bundle = FfiMarshal.encodeElements(const [
        TextElement(text: 'hi', x: 0, y: 0),
      ], allocator)..free();
      expect(bundle.free, returnsNormally, reason: 'double-free must be safe');
    });
  });

  group('FfiMarshal.decodeElements wire-safety', () {
    test('unknown tag is silently skipped (forward-compat)', () {
      // Encode a single rect so the pointer is valid, then manually corrupt the tag byte
      // to simulate a future variant this Dart build doesn't know about.
      const rect = RectElement(height: 10, width: 10, x: 0, y: 0);
      final bundle = FfiMarshal.encodeElements([rect], malloc);
      try {
        // Overwrite tag with a value beyond FfiElementType.values.length.
        bundle.elementsPtr.ref.tag = 99;
        final decodeResult = FfiMarshal.decodeElements(
          bundle.elementsPtr,
          1,
          bundle.textBufferPtr,
          payloadBufferLen: 0,
        );
        expect(decodeResult.elements, isEmpty, reason: 'unknown tag must be skipped');
        expect(decodeResult.unknownTags, [99], reason: 'unknown tag must be reported');
      } finally {
        bundle.free();
      }
    });

    test('round-trip with ffi_zero_element catches offset bugs', () {
      final handle = FfiMarshal.encodeElements([
        const RectElement(height: 0, width: 0, x: 0, y: 0),
      ], malloc);
      try {
        ffi_zero_element(handle.elementsPtr);
        final decodeResult = FfiMarshal.decodeElements(
          handle.elementsPtr,
          1,
          handle.textBufferPtr,
          payloadBufferLen: 0,
        );
        expect(decodeResult.elements.length, equals(1));
        final decoded = decodeResult.elements.first;

        if (decoded case final RectElement rect) {
          expect(rect.x, 0);
          expect(rect.y, 0);
          expect(rect.width, 0);
          expect(rect.height, 0);
          expect(rect.rotation, 0);
          expect(rect.fillColor.argb, 0);
        } else {
          fail('Expected RectElement');
        }
      } finally {
        handle.free();
      }
    });

    test('round-trip with ffi_fill_element_0xAA catches offset bugs', () {
      final handle = FfiMarshal.encodeElements([
        const RectElement(height: 0, width: 0, x: 0, y: 0),
      ], malloc);
      try {
        ffi_fill_element_0xAA(handle.elementsPtr);
        final decodeResult = FfiMarshal.decodeElements(
          handle.elementsPtr,
          1,
          handle.textBufferPtr,
          payloadBufferLen: 0,
        );

        expect(decodeResult.elements, isEmpty);
        expect(decodeResult.unknownTags, [0xAA], reason: '0xAA is an invalid tag');
      } finally {
        handle.free();
      }
    });

    test('out-of-bounds text offset throws StateError', () {
      // Encode a text element, then corrupt textOffset so it points past the buffer end.
      const text = TextElement(text: 'hi', x: 0, y: 0);
      final bundle = FfiMarshal.encodeElements([text], malloc);
      try {
        // Force an out-of-bounds offset on the first element's text payload.
        bundle.elementsPtr.ref.payload.text.textOffset = 999_999;
        expect(
          () => FfiMarshal.decodeElements(
            bundle.elementsPtr,
            1,
            bundle.textBufferPtr,
            payloadBufferLen: bundle.arena.ptr.ref.textLen,
          ),
          throwsStateError,
          reason: 'out-of-bounds text slice must throw StateError',
        );
      } finally {
        bundle.free();
      }
    });
  });
}

/// Allocator test double: forwards to [malloc] until the Nth allocation, then throws. Tracks
/// every successful allocation + every free so tests can assert no pointers leaked.
class _FailingAllocator implements Allocator {
  _FailingAllocator({required this.failAfter});

  final int failAfter;
  int succeededAllocations = 0;
  final _liveAddresses = <int>[];

  int get freedCount => succeededAllocations - _liveAddresses.length;

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    if (succeededAllocations >= failAfter) {
      throw Exception('mock allocator OOM after $succeededAllocations allocations');
    }
    final ptr = malloc.allocate<T>(byteCount, alignment: alignment);
    succeededAllocations += 1;
    _liveAddresses.add(ptr.address);

    return ptr;
  }

  @override
  void free(Pointer<NativeType> pointer) {
    final isKnown = _liveAddresses.remove(pointer.address);
    expect(isKnown, isTrue, reason: 'free() called on an address this allocator did not hand out');
    malloc.free(pointer);
  }
}
