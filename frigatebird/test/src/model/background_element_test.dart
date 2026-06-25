import 'package:frigatebird/frigatebird.dart';
import 'package:test/test.dart';

void main() => group(BackgroundElement, () {
  test('defaults are a no-op treatment (zero blur, transparent tint, no rotation/outline)', () {
    const element = BackgroundElement(height: 80, width: 100, x: 0, y: 0);

    expect(
      (
        element.blur,
        element.fillColor,
        element.rotation,
        element.outlineColor,
        element.outlineThickness,
      ),
      (0, FfiColor.transparent, 0, FfiColor.transparent, 0),
    );
  });

  test('cover builds a full-image treatment anchored at the origin', () {
    const element = BackgroundElement.cover(height: 480, width: 640);

    expect((element.x, element.y, element.width, element.height), (0.0, 0.0, 640.0, 480.0));
  });

  test('zero is an empty treatment', () {
    expect(
      (BackgroundElement.zero.width, BackgroundElement.zero.height, BackgroundElement.zero.blur),
      (0.0, 0.0, 0),
    );
  });

  test('copyWith updates blur, tint and crop rect', () {
    const original = BackgroundElement(height: 80, width: 100, x: 0, y: 0);
    final updated = original.copyWith(
      blur: 40,
      fillColor: .black,
      height: 40,
      width: 50,
      x: 10,
      y: 20,
    );

    expect((updated.x, updated.y, updated.width, updated.height), (10.0, 20.0, 50.0, 40.0));
    expect(updated.blur, 40);
    expect(updated.fillColor, FfiColor.black);
  });

  test('copyWith preserves fields that are not overridden', () {
    const original = BackgroundElement(
      blur: 25,
      fillColor: .black,
      height: 80,
      width: 100,
      x: 1,
      y: 2,
    );
    final updated = original.copyWith(x: 5);

    expect(updated.blur, 25, reason: 'omitted blur falls back to the original');
    expect(updated.fillColor, FfiColor.black, reason: 'omitted tint falls back to the original');
    expect((updated.x, updated.y, updated.width, updated.height), (5.0, 2.0, 100.0, 80.0));
  });

  test('copyWith asserts rotation stays 0', () {
    const original = BackgroundElement(height: 80, width: 100, x: 0, y: 0);

    expect(() => original.copyWith(rotation: 30), throwsA(isA<AssertionError>()));
  });

  test('copyWith asserts outline stays transparent / zero', () {
    const original = BackgroundElement(height: 80, width: 100, x: 0, y: 0);

    expect(() => original.copyWith(outlineColor: .black), throwsA(isA<AssertionError>()));
    expect(() => original.copyWith(outlineThickness: 4), throwsA(isA<AssertionError>()));
  });

  test('equality and hashCode compare rect, blur and tint', () {
    const alpha = BackgroundElement(blur: 10, height: 80, width: 100, x: 0, y: 0);
    const twin = BackgroundElement(blur: 10, height: 80, width: 100, x: 0, y: 0);
    const gamma = BackgroundElement(blur: 20, height: 80, width: 100, x: 0, y: 0);

    expect(alpha, twin);
    expect(alpha.hashCode, twin.hashCode);
    expect(alpha, isNot(gamma));
  });

  test('equality compares the tint for non-identical instances', () {
    // Runtime copyWith results aren't canonicalized like const literals.
    // The `==` chain therefore skips the identity short-circuit and compares every field.
    const template = BackgroundElement(blur: 10, height: 8, width: 9, x: 0, y: 0);
    final base = template.copyWith(fillColor: .black);
    final sameFill = template.copyWith(fillColor: .black);
    final otherFill = template.copyWith(); // Keeps the default transparent tint.

    expect(base == sameFill, isTrue, reason: 'equal in every field including tint');
    expect(base == otherFill, isFalse, reason: 'differs only in tint');
  });

  test('toString surfaces the treatment fields', () {
    const element = BackgroundElement(blur: 12, height: 80, width: 100, x: 1, y: 2);

    expect(element.toString(), contains('BackgroundElement('));
    expect(element.toString(), contains('blur: 12'));
  });

  test('is a sealed DrawElement subtype', () {
    const subject = BackgroundElement(height: 1, width: 1, x: 0, y: 0);

    expect(subject, isA<DrawElement>());
  });
});
