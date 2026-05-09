import 'package:frigatebird/src/model/ffi_color.dart';
import 'package:test/test.dart';

void main() => group(FfiColor, () {
  test(
    'FfiColor.black packs opaque black',
    () => expect(FfiColor.black.argb, 0xFF000000, reason: 'alpha=255, rgb=000'),
  );

  test(
    'FfiColor.transparent is zero',
    () => expect(FfiColor.transparent.argb, 0, reason: 'alpha=0, rgb=000'),
  );

  test('raw and named constants agree on the wire', () {
    // Deliberately construct via the raw int to verify the wire form matches FfiColor.black.
    // ignore: use_named_constants, comparing FfiColor.black against its raw bit pattern.
    const raw = FfiColor(0xFF000000);
    expect(FfiColor.black.argb, raw.argb, reason: 'named constant == raw bit pattern');
  });

  test(
    'toString renders ARGB in hex',
    () => expect(FfiColor.black.toString(), 'FfiColor(0xFF000000)'),
  );

  test('from() packs custom alpha + blue correctly', () {
    const color = FfiColor.from(alpha: 128, blue: 255);
    expect(color.argb, 0x800000FF, reason: 'alpha=80h, blue=FFh, other channels=0');
  });

  group('range guards', () {
    test('rejects argb < 0 (would wrap to a huge u32 on the FFI wire)', () {
      expect(
        () => FfiColor(-1),
        throwsA(isA<AssertionError>()),
        reason: 'negative argb silently wraps via Dart Uint32 marshaling',
      );
    });

    test('rejects argb > 0xFFFFFFFF (would lose high bits)', () {
      expect(
        () => FfiColor(0x1_0000_0000),
        throwsA(isA<AssertionError>()),
        reason: 'values past u32::MAX truncate silently when written to the FFI slot',
      );
    });

    test('accepts the full legal u32 range at both ends', () {
      // ignore: use_named_constants, exercising the raw constructor at the boundary.
      expect(const FfiColor(0).argb, 0, reason: 'lower bound');
      expect(const FfiColor(0xFFFFFFFF).argb, 0xFFFFFFFF, reason: 'upper bound');
    });
  });
});
