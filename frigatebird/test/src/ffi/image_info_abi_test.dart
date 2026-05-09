import 'package:frigatebird/src/ffi/ffi_abi.dart';
import 'package:test/test.dart';

void main() {
  group('FfiAbi.assertImageInfo', () {
    test(
      'succeeds on the host platform (12 bytes)',
      () => expect(FfiAbi.assertImageInfo, returnsNormally),
    );

    test('throws AssertionError when the expected size is wrong', () {
      expect(
        () => FfiAbi.assertImageInfo(expectedSize: 999),
        throwsA(isA<AssertionError>()),
        reason: 'mismatched expected size must fail loudly',
      );
    });
  });
}
