import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:frigatebird/src/ffi/ffi_arena_handle.dart';
import 'package:frigatebird/src/ffi/ffi_result_unit.dart';
import 'package:test/test.dart';

void main() => group(FfiArenaHandle, () {
  test('allocate sets up arena pointers and zero-initializes error', () {
    final arena = FfiArenaHandle.allocate();
    try {
      final ptr = arena.ptr;
      final ref = ptr.ref;
      final isNotZero = isNot(0);
      expect(ptr.address, isNotZero);
      expect(ref.error.ptr.address, isNotZero);
      expect(ref.error.len, FfiArenaHandle.defaultErrorCapacity);

      // Assert zero-initialized.
      expect(ref.error.ptr[0], isZero);
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
        final errorBuf = arena.ptr.ref.error.ptr;
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
});
