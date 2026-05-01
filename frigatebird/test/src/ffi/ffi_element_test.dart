import 'dart:ffi';

import 'package:frigatebird/src/ffi/ffi_element.dart';
import 'package:frigatebird/src/ffi/ffi_element_type.dart';
import 'package:test/test.dart';

void main() {
  group('FfiElement layout', () {
    test(
      'struct is 64 bytes (tag(1)+pad(7)+payload(56))',
      () => expect(sizeOf<FfiElement>(), 64, reason: 'wire-size contract'),
    );

    test(
      'RectanglePayload is 48 bytes',
      () => expect(
        sizeOf<RectanglePayload>(),
        48,
        reason: '4*f64(32)+i32(4)+u32(4)+u32(4)+u8+u8+u16 = 48',
      ),
    );

    test(
      'TextPayload is 56 bytes',
      () => expect(
        sizeOf<TextPayload>(),
        56,
        reason: '4*f64(32)+i32(4)+u32(4)+u8+pad(3)+u32+u32+u32 = 56',
      ),
    );
  });

  group('FfiElementType', () {
    test(
      'rectangle has wire value 0',
      () => expect(FfiElementType.rectangle.value, isZero, reason: 'rectangle discriminator'),
    );

    test(
      'text has wire value 1',
      () => expect(FfiElementType.text.value, 1, reason: 'text discriminator'),
    );
  });
}
