import 'package:frigatebird/src/model/ffi_color.dart';
import 'package:test/test.dart';

void main() => group(FfiColor, () {
  test('default constructor packs ARGB correctly', () {
    const raw = FfiColor(0xFF000000);
    const color = FfiColor.from();

    expect(color.argb, 0xFF000000);
    expect(color.argb, raw.argb);
  });

  test(
    'default to string override provides correct output',
    () => expect(const FfiColor.from().toString(), 'FfiColor(0xFF000000)'),
  );

  test('constructor packs ARGB correctly with custom values', () {
    const color = FfiColor.from(alpha: 128, blue: 255);

    expect(color.argb, 0x800000FF);
  });
});
