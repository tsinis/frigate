import 'package:frigatebird/src/ffi/ffi_abi.dart';
import 'package:test/test.dart';

void main() {
  group('FfiAbi.assertAll', () {
    test('succeeds on the host platform', () {
      expect(FfiAbi.assertAll, returnsNormally);
    });

    test('is idempotent, calling twice does not throw', () {
      FfiAbi.assertAll();
      expect(FfiAbi.assertAll, returnsNormally);
    });
  });

  group('FfiAbi.assertPolygonPayload', () {
    test('passes with the correct expected size', () {
      expect(FfiAbi.assertPolygonPayload, returnsNormally);
    });
  });
}
