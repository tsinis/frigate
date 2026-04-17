import 'dart:typed_data';

import 'package:frigatebird/src/ffi/native_image.dart';
import 'package:test/test.dart';

void main() => group(NativeImage, () {
  test('holds the dimensions passed at construction', () {
    final image = NativeImage.fromBytes(Uint8List.fromList([1, 2, 3]), height: 20, width: 10);
    addTearDown(image.dispose);
    expect((image.width, image.height, image.length), (10, 20, 3), reason: 'metadata round-trip');
  });

  test('bytes is a zero-copy view of native memory', () {
    final source = Uint8List.fromList([0x10, 0x20, 0x30]);
    final image = NativeImage.fromBytes(source, height: 1, width: 3);
    addTearDown(image.dispose);
    expect(image.bytes, source, reason: 'native bytes match the source copy');
    expect(image.bytes.length, 3, reason: 'length reflects source, not allocation slack');
  });

  test('dispose is idempotent', () {
    final image = NativeImage.fromBytes(Uint8List.fromList([1]), height: 1, width: 1)..dispose();
    expect(image.dispose, returnsNormally, reason: 'second dispose must not double-free');
  });

  test('address throws StateError after dispose', () {
    final image = NativeImage.fromBytes(Uint8List.fromList([1]), height: 1, width: 1)..dispose();
    expect(
      () => image.address,
      throwsStateError,
      reason: 'reading a freed pointer is a use-after-free footgun',
    );
  });

  test('bytes throws StateError after dispose', () {
    final image = NativeImage.fromBytes(Uint8List.fromList([1]), height: 1, width: 1)..dispose();
    expect(
      () => image.bytes,
      throwsStateError,
      reason: 'the view points into freed memory, fail loudly instead of silent UB',
    );
  });
});
