import 'package:frigatebird/src/ffi/ffi_abi.dart';
import 'package:test/test.dart';

void main() {
  group('FfiAbi.assertAll', () {
    test('succeeds on the host platform', () {
      expect(FfiAbi.assertAll, returnsNormally);
    });
  });
}
