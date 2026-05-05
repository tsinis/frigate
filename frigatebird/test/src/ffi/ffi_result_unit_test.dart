import 'package:frigatebird/src/ffi/ffi_error.dart';
import 'package:frigatebird/src/ffi/ffi_result_unit.dart';
import 'package:test/test.dart';

void main() {
  group(OkUnit, () {
    test('can be constructed', () {
      const result = OkUnit();
      expect(result, isA<OkUnit>());
    });

    test('is a sealed subclass of FfiResultUnit', () {
      const result = OkUnit();
      expect(result, isA<FfiResultUnit>());
    });

    test('instances are equal', () {
      const ok1 = OkUnit();
      const ok2 = OkUnit();
      expect(ok1, equals(ok2));
    });

    test('const instances are identical', () {
      const ok1 = OkUnit();
      const ok2 = OkUnit();
      expect(identical(ok1, ok2), isTrue);
    });
  });

  group(ErrUnit, () {
    test('can be constructed with code and message', () {
      const result = ErrUnit(.decode, 'image decode failed');
      expect(result.code, FfiErrorCode.decode);
      expect(result.message, 'image decode failed');
    });

    test('is a sealed subclass of FfiResultUnit', () {
      const result = ErrUnit(.io, 'test');
      expect(result, isA<FfiResultUnit>());
    });
  });

  group('FfiErrorCode', () {
    test('success has index 0', () {
      expect(FfiErrorCode.success.index, 0);
    });

    test('panic has index 1', () {
      expect(FfiErrorCode.panic.index, 1);
    });

    test('invalidArg has index 2', () {
      expect(FfiErrorCode.invalidArg.index, 2);
    });

    test('io has index 3', () {
      expect(FfiErrorCode.io.index, 3);
    });

    test('decode has index 4', () {
      expect(FfiErrorCode.decode.index, 4);
    });

    test('encode has index 5', () {
      expect(FfiErrorCode.encode.index, 5);
    });

    test('font has index 6', () {
      expect(FfiErrorCode.font.index, 6);
    });

    test('render has index 7', () {
      expect(FfiErrorCode.render.index, 7);
    });

    test('utf8 has index 8', () {
      expect(FfiErrorCode.utf8.index, 8);
    });

    test('unknown has index 9', () {
      expect(FfiErrorCode.unknown.index, 9);
    });

    test('fromCode maps valid indices', () {
      expect(FfiErrorCode.fromCode(0), FfiErrorCode.success);
      expect(FfiErrorCode.fromCode(3), FfiErrorCode.io);
      expect(FfiErrorCode.fromCode(8), FfiErrorCode.utf8);
    });

    test('fromCode maps out-of-range codes to unknown', () {
      expect(FfiErrorCode.fromCode(255), FfiErrorCode.unknown);
      expect(FfiErrorCode.fromCode(-1), FfiErrorCode.unknown);
      expect(FfiErrorCode.fromCode(100), FfiErrorCode.unknown);
    });

    test('description provides human-readable strings', () {
      expect(FfiErrorCode.success.description, 'success');
      expect(FfiErrorCode.decode.description, 'image decode failed');
      expect(FfiErrorCode.font.description, 'font parse failed');
      expect(FfiErrorCode.unknown.description, 'unrecognized error code');
    });
  });
}
