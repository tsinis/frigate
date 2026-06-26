import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:frigatebird/src/ffi/ffi_abi.dart';
import 'package:frigatebird/src/ffi/ffi_element.dart';
import 'package:frigatebird/src/ffi/ffi_test_helpers.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(FfiAbi.assertAll);

  group('FFI Layout Stability', () {
    test('ffi_zero_element correctly zeroes a Dart-allocated FfiElement', () {
      final ptr = calloc<FfiElement>();
      try {
        // Poison with non-zero.
        final ref = ptr.ref;
        final rect = ref.payload.rectangle;
        ref.tag = 0xBE;
        rect.x = 123.456;

        ffi_zero_element(ptr);

        expect(ref.tag, isZero);
        expect(rect.x, isZero);
        expect(rect.rotationDeg, isZero);
      } finally {
        calloc.free(ptr);
      }
    });

    test('ffi_fill_element_0xAA fills with 0xAA pattern', () {
      final ptr = calloc<FfiElement>();
      try {
        ffi_fill_element_0xAA(ptr);

        final ref = ptr.ref;
        final rect = ref.payload.rectangle;
        expect(ref.tag, 0xAA);
        expect(rect.x, isNot(0.0), reason: '0xAAAAAAAAAAAAAAAA as double is some non-zero value');
        expect(rect.rotationDeg, 0xAAAAAAAA.toSigned(32));
      } finally {
        calloc.free(ptr);
      }
    });
  });
}
