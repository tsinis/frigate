import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:frigatebird/src/ffi/ffi_arena_handle.dart';
import 'package:frigatebird/src/ffi/ffi_result_unit.dart';
import 'package:test/test.dart';

void main() => group(FfiArenaHandle, () {
  test('allocate sets up arena pointers and zero-initializes errorBuf', () {
    final arena = FfiArenaHandle.allocate();
    try {
      final ptr = arena.ptr;
      final ref = ptr.ref;
      final isNotZero = isNot(0);
      expect(ptr.address, isNotZero);
      expect(ref.errorBuf.address, isNotZero);
      expect(ref.errorCap, FfiArenaHandle.defaultErrorCapacity);

      // Assert zero-initialized.
      expect(ref.errorBuf[0], 0);
    } finally {
      arena.free();
    }
  });

  test('readResult decodes error from buffer', () {
    final arena = FfiArenaHandle.allocate(errorCapacity: 128);
    try {
      const msg = 'Some error';
      final encoded = msg.toNativeUtf8();
      try {
        final errorBuf = arena.ptr.ref.errorBuf;
        final source = encoded.cast<Uint8>();

        // Manually write into the buffer.
        for (final (i, byte) in source.asTypedList(encoded.length).indexed) {
          errorBuf[i] = byte;
        }
        errorBuf[encoded.length] = 0;

        final result = arena.readResult(2); // InvalidArg.
        if (result case final ErrUnit err) {
          expect(err.message, msg);
        } else {
          fail('Expected ErrUnit');
        }
      } finally {
        calloc.free(encoded);
      }
    } finally {
      arena.free();
    }
  });

  test('errorMessage throws if freed', () {
    final arena = FfiArenaHandle.allocate()..free();
    expect(() => arena.errorMessage, throwsStateError);
  });

  test('allocate with custom finalizer', () {
    // ignore: prefer-explicit-type-arguments, it's a test.
    final finalizer = NativeFinalizer(calloc.nativeFree.cast());
    final arena = FfiArenaHandle.allocate(finalizer: finalizer);
    expect(arena.ptr.address, isNot(0));
    // Do not call arena.free() because the custom allocator was not provided,
    // so arena.free() will try to use `calloc.free` but `finalizer` is already attached
    // and might double-free if we aren't careful, but since we used standard calloc
    // we should just let the GC handle it or detach it explicitly.
    // Let's just let it be finalized.
  });
});
