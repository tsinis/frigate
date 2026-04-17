import 'package:frigatebird/src/ffi/ffi_abi.dart';
import 'package:test/test.dart';

void main() {
  group('FfiAbi.assertElement', () {
    test(
      'succeeds on the host platform (72 bytes)',
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

  group('FfiAbi.assertRectElement', () {
    test(
      'succeeds on the host platform (48 bytes after adding shapeParam)',
      () => expect(FfiAbi.assertRectElement, returnsNormally),
    );

    test('throws AssertionError when the expected size is wrong', () {
      expect(() => FfiAbi.assertRectElement(expectedSize: 999), throwsA(isA<AssertionError>()));
    });
  });
}
