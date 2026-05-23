import 'dart:ffi';

import 'package:frigatebird/src/ffi/ffi_element.dart';
import 'package:frigatebird/src/ffi/ffi_element_type.dart';
import 'package:test/test.dart';

void main() {
  group('FfiElement layout', () {
    test(
      'struct is 72 bytes (tag(8)+payload(64))',
      () => expect(sizeOf<FfiElement>(), 72, reason: 'wire-size contract'),
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
      'TextPayload is 48 bytes',
      () => expect(
        sizeOf<TextPayload>(),
        48,
        reason: '3*f64(24)+i32(4)+u32(4)+u8+pad(3)+u32+u32+u32 = 48',
      ),
    );

    test(
      'PolygonPayload is 64 bytes',
      () => expect(sizeOf<PolygonPayload>(), 64, reason: '8*usize = 64'),
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

    test(
      'oval has wire value 2',
      () => expect(FfiElementType.oval.value, 2, reason: 'oval discriminator'),
    );

    test(
      'polygon has wire value 3',
      () => expect(FfiElementType.polygon.value, 3, reason: 'polygon discriminator'),
    );
  });
}
