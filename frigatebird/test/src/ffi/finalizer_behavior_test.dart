import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:frigatebird/src/ffi/native_image.dart';
import 'package:test/test.dart';

void main() {
  group('Finalizer Behavior', () {
    test(
      'NativeImage wrapper retains allocation, dropping wrapper triggers exact-count GC',
      () async {
        final trackingAllocator = _TrackingAllocator(malloc);
        final testFinalizer = Finalizer<int>(trackingAllocator.recordFinalizerFree);

        // We use a nullable variable to allow dropping the reference.
        ({int address, NativeImage wrapper})? result = _createAndDropWrapper(
          trackingAllocator,
          testFinalizer,
        );
        final address = result.address;

        // Force GC. The wrapper is still retained.
        await _forceGC();
        expect(result.wrapper.bytes.length, 100);
        _reachabilityFence(result.wrapper);

        // Wait for any asynchronous cleanup.
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(trackingAllocator.outstandingCount, 1, reason: 'Wrapper retains the allocation');

        // Now drop the wrapper.
        // ignore: avoid-unused-assignment, dropped for GC test.
        result = null;

        // Force GC and finalizer execution.
        bool isFreed = false;
        for (int i = 0; i < 20; i += 1) {
          await _forceGC();

          // Wait for finalizers to run.
          await Future<void>.delayed(const Duration(milliseconds: 50));
          if (trackingAllocator.outstandingCount == 0) {
            isFreed = true;

            break;
          }
        }

        expect(isFreed, isTrue, reason: 'Dropping wrapper frees the allocation');

        // Suppress unused warning.
        expect(address, isNot(0));
      },
    );
  });
}

({int address, NativeImage wrapper}) _createAndDropWrapper(
  _TrackingAllocator allocator,
  Finalizer<int> finalizer,
) {
  final data = Uint8List(100);
  final image = NativeImage.testWithAllocator(data, allocator: allocator, height: 10, width: 10);
  final address = image.address;
  finalizer.attach(image, address, detach: image);

  return (address: address, wrapper: image);
}

Future<void> _forceGC() async {
  // Allocate memory to attempt to trigger GC.
  // This is a best-effort heuristic. Callers should perform bounded retries.
  for (int i = 0; i < 5; i += 1) {
    // Yield to allow GC events to process (zero-duration yield).
    await Future<void>.delayed(.zero);
    final _ = List.generate(100_000, (index) => Object());
  }
}

class _TrackingAllocator implements Allocator {
  _TrackingAllocator(this._inner);
  final Allocator _inner;

  final _allocations = <int, int>{};

  int get outstandingCount => _allocations.length;

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    final ptr = _inner.allocate<T>(byteCount, alignment: alignment);
    _allocations[ptr.address] = byteCount;

    return ptr;
  }

  @override
  void free(Pointer<NativeType> pointer) {
    if (pointer == nullptr) return;
    if (!_allocations.containsKey(pointer.address)) {
      throw StateError('Double free or free of non-allocated pointer at ${pointer.address}');
    }
    final _ = _allocations.remove(pointer.address);
    _inner.free(pointer);
  }

  /// Called manually by test Finalizers to simulate the NativeFinalizer running.
  void recordFinalizerFree(int address) {
    if (!_allocations.containsKey(address)) {
      throw StateError('Finalizer freed untracked address $address');
    }
    final _ = _allocations.remove(address);
  }
}

@pragma('vm:never-inline')
// ignore: no-empty-block, avoid-unnecessary-nullable-parameters, it's a test.
void _reachabilityFence(Object? _) {}
