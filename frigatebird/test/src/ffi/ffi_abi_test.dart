import 'package:frigatebird/src/ffi/ffi_abi.dart';
import 'package:test/test.dart';

void main() {
  group('FfiAbi.assertElement', () {
    test(
      'succeeds on the host platform (64 bytes)',
      () => expect(FfiAbi.assertElement, returnsNormally),
    );

    test('throws AssertionError when the expected size is wrong', () {
      expect(
        () => FfiAbi.assertElement(expectedSize: 999),
        throwsA(isA<AssertionError>()),
        reason: 'mismatched expected size must fail loudly, this is the whole point',
      );
    });
  });

  group('FfiAbi.assertArena', () {
    test(
      'succeeds on the host platform (48 bytes)',
      () => expect(FfiAbi.assertArena, returnsNormally),
    );

    test(
      'throws AssertionError when the expected size is wrong',
      () => expect(() => FfiAbi.assertArena(expectedSize: 999), throwsA(isA<AssertionError>())),
    );
  });

  group('FfiAbi.assertError', () {
    test(
      'succeeds on the host platform (4 bytes)',
      () => expect(FfiAbi.assertError, returnsNormally),
    );

    test('throws AssertionError when the expected size is wrong', () {
      expect(() => FfiAbi.assertError(expectedSize: 999), throwsA(isA<AssertionError>()));
    });
  });

  group('FfiAbi.assertResultUnit', () {
    test(
      'succeeds on the host platform (6 bytes - Rust FfiResultUnit is 6, not 8)',
      () => expect(FfiAbi.assertResultUnit, returnsNormally),
    );

    test('throws AssertionError when the expected size is wrong', () {
      expect(() => FfiAbi.assertResultUnit(expectedSize: 999), throwsA(isA<AssertionError>()));
    });

    test('rejects the old incorrect size of 8 (proves the _pad bug is gone)', () {
      // Before the fix, FfiResultUnitStruct had an extra @Uint8() _pad field that pushed
      // Dart's view to 8 bytes while Rust's repr(C,u8) enum is only 6 bytes. Asserting that
      // the actual size is NOT 8 (and is 6) locks this regression out permanently.
      expect(
        () => FfiAbi.assertResultUnit(expectedSize: 8),
        throwsA(isA<AssertionError>()),
        reason: 'Dart struct must be 6 bytes to match Rust - 8 would read stack garbage',
      );
    });
  });

  group('FfiAbi.assertResultCount', () {
    test(
      'succeeds on the host platform (8 bytes - Rust FfiResultCount is 8)',
      () => expect(FfiAbi.assertResultCount, returnsNormally),
    );

    test('throws AssertionError when the expected size is wrong', () {
      expect(() => FfiAbi.assertResultCount(expectedSize: 999), throwsA(isA<AssertionError>()));
    });
  });

  group('FfiAbi.assertRectElement', () {
    test(
      'succeeds on the host platform (48 bytes)',
      () => expect(FfiAbi.assertRectElement, returnsNormally),
    );

    test('throws AssertionError when the expected size is wrong', () {
      expect(() => FfiAbi.assertRectElement(expectedSize: 999), throwsA(isA<AssertionError>()));
    });
  });
}
