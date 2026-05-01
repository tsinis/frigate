import 'dart:ffi';

import 'package:frigatebird/src/ffi/ffi_error.dart';
import 'package:frigatebird/src/ffi/ffi_result_count.dart';
import 'package:test/test.dart';

void main() {
  group(OkCount, () {
    test('can be constructed with a value', () {
      const result = OkCount(42);
      expect(result.value, 42);
    });

    test('is a sealed subclass of FfiResultCount', () {
      const result = OkCount(42);
      expect(result, isA<FfiResultCount>());
    });

    test('instances with same value are equal', () {
      const ok1 = OkCount(123);
      const ok2 = OkCount(123);
      expect(ok1, equals(ok2));
    });

    test('instances with different values are not equal', () {
      const ok1 = OkCount(123);
      const ok2 = OkCount(456);
      expect(ok1, isNot(equals(ok2)));
    });

    test('handles zero value', () {
      const result = OkCount(0);
      expect(result.value, 0);
    });

    test('handles max u32 value', () {
      const result = OkCount(0xFFFFFFFF);
      expect(result.value, 0xFFFFFFFF);
    });

    test('const instances with same value are identical', () {
      const ok1 = OkCount(100);
      const ok2 = OkCount(100);
      expect(identical(ok1, ok2), isTrue);
    });
  });

  group(ErrCount, () {
    test('can be constructed with code and message', () {
      const result = ErrCount(.font, 'invalid font file');
      expect(result.code, FfiErrorCode.font);
      expect(result.message, 'invalid font file');
    });

    test('is a sealed subclass of FfiResultCount', () {
      const result = ErrCount(.io, 'test');
      expect(result, isA<FfiResultCount>());
    });

    test('instances with same values are equal', () {
      const err1 = ErrCount(.utf8, 'invalid utf8');
      const err2 = ErrCount(.utf8, 'invalid utf8');
      expect(err1, equals(err2));
    });

    test('instances with different codes are not equal', () {
      const err1 = ErrCount(.io, 'same');
      const err2 = ErrCount(.decode, 'same');
      expect(err1, isNot(equals(err2)));
    });

    test('instances with different messages are not equal', () {
      const err1 = ErrCount(.render, 'msg1');
      const err2 = ErrCount(.render, 'msg2');
      expect(err1, isNot(equals(err2)));
    });
  });

  group(FfiResultCountStruct, () {
    test('size is 8 bytes', () => expect(sizeOf<FfiResultCountStruct>(), 8));
  });

  group(FfiResultCountPayload, () {
    test(
      'size is 4 bytes (union with u32 and FfiError)',
      () => expect(sizeOf<FfiResultCountPayload>(), 4),
    );
  });
}
