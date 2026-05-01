import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:frigatebird/src/ffi/bindings.dart' as ffi;
import 'package:frigatebird/src/ffi/ffi_marshal.dart';
import 'package:frigatebird/src/model/draw_element.dart';
import 'package:frigatebird/src/model/ffi_color.dart';
import 'package:test/test.dart';

void main() {
  group('FfiMarshal round-trip', () {
    test('Rectangle round-trip via Rust echo', () {
      const rect = RectElement(
        blur: 2,
        cornerRadius: 10,
        fillColor: FfiColor(0xFFFF0000),
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
        final echoedPtr = ffi.ffi_echo_element(bundle.elementsPtr);
        final decoded = FfiMarshal.decodeElements(
          echoedPtr,
          bundle.count,
          bundle.textBufferPtr,
          payloadBufferLen: bundle.arenaPtr.ref.textLen,
        );

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
        fontSize: 32,
        rotation: -45,
        text: 'Hello FFI',
        x: 5,
        y: 15,
      );

      final bundle = FfiMarshal.encodeElements([text], malloc);
      try {
        final echoedPtr = ffi.ffi_echo_element(bundle.elementsPtr);
        final decoded = FfiMarshal.decodeElements(
          echoedPtr,
          bundle.count,
          bundle.textBufferPtr,
          payloadBufferLen: bundle.arenaPtr.ref.textLen,
        );

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
        const TextElement(fontSize: 40, text: 'Longer string', x: 3, y: 3),
      ];

      final bundle = FfiMarshal.encodeElements(elements, malloc);
      try {
        final echoedPtr = ffi.ffi_echo_element(bundle.elementsPtr);
        final decoded = FfiMarshal.decodeElements(
          echoedPtr,
          bundle.count,
          bundle.textBufferPtr,
          payloadBufferLen: bundle.arenaPtr.ref.textLen,
        );

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
      final bundle = FfiMarshal.encodeElements(
        const [TextElement(text: 'hi', x: 0, y: 0)],
        // Dart 3.8 formatting.
        allocator,
      )..free();
      expect(bundle.free, returnsNormally, reason: 'double-free must be safe');
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
