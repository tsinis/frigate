import 'dart:convert' show utf8;
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:frigatebird/src/ffi/ffi_abi.dart';
import 'package:frigatebird/src/ffi/ffi_arena_handle.dart';
import 'package:frigatebird/src/ffi/ffi_error.dart';
import 'package:frigatebird/src/ffi/ffi_result_unit.dart';
import 'package:frigatebird/src/ffi/ffi_test_helpers.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(FfiAbi.assertAll);

  group('FFI Error Channel', () {
    test('Round-trip every FfiErrorCode via ffi_force_error', () {
      final arena = FfiArenaHandle.allocate();
      try {
        for (final code in FfiErrorCode.values) {
          if (code == .success) continue;

          final msg = 'Forced error: ${code.name}';
          final msgPtr = msg.toNativeUtf8();
          try {
            final returnedCode = ffi_force_error(
              code.index, // Assuming FfiErrorCode index matches Rust enum discriminant.
              msgPtr.cast<Uint8>(),
              utf8.encode(msg).length,
              arena.ptr,
            );

            expect(returnedCode, code.index);
            final result = arena.readResult(returnedCode);
            if (result case final ErrUnit err) {
              expect(err.code, code);
              expect(err.message, msg);
            } else {
              fail('Expected ErrUnit');
            }
          } finally {
            calloc.free(msgPtr);
          }
        }
      } finally {
        arena.free();
      }
    });

    test('Unknown error code (version skew) maps to unknown', () {
      final arena = FfiArenaHandle.allocate();
      try {
        final result = arena.readResult(99);
        if (result case final ErrUnit err) {
          expect(err.code, FfiErrorCode.unknown);
        } else {
          fail('Expected ErrUnit');
        }
      } finally {
        arena.free();
      }
    });

    test('Truncation behavior (message > errorCap)', () {
      // Create an arena with a tiny buffer.
      final arena = FfiArenaHandle.allocate(errorCapacity: 4);
      try {
        const msg = 'Long message';
        final msgPtr = msg.toNativeUtf8();
        try {
          final returnedCode = ffi_force_error(
            FfiErrorCode.io.index,
            msgPtr.cast<Uint8>(),
            utf8.encode(msg).length,
            arena.ptr,
          );

          final result = arena.readResult(returnedCode);
          // Should be truncated to 3 chars + NUL.
          if (result case final ErrUnit err) {
            expect(err.message.length, lessThan(msg.length));
            expect(err.message, 'Lon');
          } else {
            fail('Expected ErrUnit');
          }
        } finally {
          calloc.free(msgPtr);
        }
      } finally {
        arena.free();
      }
    });
  });
}
