import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:frigatebird/src/ffi/ffi_marshal.dart';
import 'package:frigatebird/src/model/draw_element.dart';
import 'package:test/test.dart';

void main() {
  group('Memory Accounting', () {
    test('encodeElements + free loop has zero net allocations', () {
      final trackingAllocator = _TrackingAllocator(malloc);
      final elements = [
        const RectElement(height: 10, width: 10, x: 0, y: 0),
        const TextElement(text: 'Hello', x: 5, y: 5),
      ];

      for (int i = 0; i < 100; i += 1) {
        FfiMarshal.encodeElements(elements, trackingAllocator).free();
      }

      trackingAllocator.assertNoLeaks();
      expect(trackingAllocator.totalAllocated, greaterThan(0));
    });

    test('FfiElementsHandle failure mid-allocation leaks nothing', () {
      final trackingAllocator = _TrackingAllocator(malloc);
      final elements = [
        const TextElement(text: 'First', x: 0, y: 0),
        const TextElement(text: 'Second', x: 1, y: 1),
      ];

      // Let's see if we can at least verify that if text buffer allocation fails, elements are freed.
      // I'll create a special allocator that fails on the second call.
      final failingAllocator = _FailingAllocator(trackingAllocator, failAtCall: 2);

      expect(
        () => FfiMarshal.encodeElements(elements, failingAllocator),
        throwsA(
          isA<ArgumentError>().having((e) => e.message, 'message', contains('Injected failure')),
        ),
      );

      expect(trackingAllocator.outstandingCount, 0, reason: 'elements must be freed on error');
      expect(trackingAllocator.totalAllocated, 1, reason: 'only the first alloc succeeded');
    });
  });
}

class _FailingAllocator implements Allocator {
  _FailingAllocator(this.inner, {required this.failAtCall});
  final Allocator inner;
  final int failAtCall;
  int callCount = 0;

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    callCount += 1;
    if (callCount == failAtCall) {
      throw ArgumentError('Injected failure at call $callCount');
    }

    return inner.allocate<T>(byteCount, alignment: alignment);
  }

  @override
  void free(Pointer<NativeType> pointer) => inner.free(pointer);
}

class _TrackingAllocator implements Allocator {
  _TrackingAllocator(this._inner);
  final Allocator _inner;

  final _allocations = <int, int>{};
  int _totalAllocated = 0;

  int get outstandingCount => _allocations.length;
  int get totalAllocated => _totalAllocated;

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    final ptr = _inner.allocate<T>(byteCount, alignment: alignment);
    _allocations[ptr.address] = byteCount;
    _totalAllocated += 1;

    return ptr;
  }

  @override
  void free(Pointer<NativeType> pointer) {
    if (pointer == nullptr) {
      throw StateError('free called with nullptr');
    }

    if (!_allocations.containsKey(pointer.address)) {
      throw StateError('Double free or free of non-allocated pointer at ${pointer.address}');
    }
    final _ = _allocations.remove(pointer.address);
    _inner.free(pointer);
  }

  void assertNoLeaks() {
    if (outstandingCount == 0) {
      return;
    }

    final leaks = _allocations.entries
        .map((e) => '0x${e.key.toRadixString(16)} (${e.value} bytes)')
        .join(', ');

    throw StateError('Memory leak detected: $outstandingCount outstanding allocations: $leaks');
  }
}
