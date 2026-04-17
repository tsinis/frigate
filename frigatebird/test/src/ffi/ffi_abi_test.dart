import 'package:frigatebird/src/ffi/ffi_abi.dart';
import 'package:test/test.dart';

void main() {
  group('assertFfiElementAbi', () {
    test(
      'succeeds on the host platform (72 bytes)',
      () => expect(assertFfiElementAbi, returnsNormally),
    );

    test('throws AssertionError when the expected size is wrong', () {
      expect(
        () => assertFfiElementAbi(expectedSize: 999),
        throwsA(isA<AssertionError>()),
        reason: 'mismatched expected size must fail loudly, this is the whole point',
      );
    });
  });

  group('assertFfiRectElementAbi', () {
    test(
      'succeeds on the host platform (40 bytes)',
      () => expect(assertFfiRectElementAbi, returnsNormally),
    );

    test('throws AssertionError when the expected size is wrong', () {
      expect(() => assertFfiRectElementAbi(expectedSize: 999), throwsA(isA<AssertionError>()));
    });
  });
}
