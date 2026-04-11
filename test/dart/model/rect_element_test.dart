import 'package:frigate_draw/frigate_draw.dart';
import 'package:test/test.dart';

void main() => group(RectElement, () {
  test('default values', () {
    const rect = RectElement(height: 50, width: 100, x: 10, y: 20);

    expect(rect.strokeWidth, 2.0);
    expect(rect.color.argb, const FfiColor.from().argb);
  });

  test('FfiColor packs ARGB correctly', () => expect(const FfiColor.from().argb, 0xFF000000));

  test('FfiColor packs ARGB correctly with custom values', () {
    const color = FfiColor.from(alpha: 128, blue: 255);
    const raw = FfiColor(2_147_483_903);

    expect(color.argb, 0x800000FF);
    expect(color.argb, raw.argb);
  });

  test('copyWith preserves unchanged fields', () {
    const original = RectElement(height: 50, width: 100, x: 10, y: 20, strokeWidth: 5);
    final RectElement(:color, :height, :strokeWidth, :width, :x, :y) = original.copyWith(x: 30);

    expect(x, 30);
    expect(y, 20);
    expect(width, 100);
    expect(height, 50);
    expect(strokeWidth, 5.0);
    expect(color.argb, const FfiColor.from().argb);
  });

  test('is deeply immutable', () {
    const rect = RectElement(height: 10, width: 10, x: 0, y: 0);
    final moved = rect.copyWith(x: 5);

    expect(rect.x, isZero);
    expect(moved.x, 5);
  });
});
