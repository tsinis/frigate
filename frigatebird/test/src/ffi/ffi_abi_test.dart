import 'package:frigatebird/src/ffi/ffi_abi.dart';
import 'package:test/test.dart';

void main() {
  group('FfiAbi.assertElement', () {
    test(
      'succeeds on the host platform (56 bytes)',
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
