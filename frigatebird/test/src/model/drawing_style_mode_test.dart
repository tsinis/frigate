import 'package:frigatebird/frigatebird.dart';
import 'package:test/test.dart';

void main() {
  group('ColorStyle', () {
    test('equality and hashCode work correctly', () {
      const base = ColorStyle();
      expect(base, equals(const ColorStyle()));
      expect(base.hashCode, equals(const ColorStyle().hashCode));

      expect(base, isNot(equals(const ColorStyle(color: FfiColor(0xFFFF0000)))));
      expect(base.hashCode, isNot(equals(const ColorStyle(color: FfiColor(0xFFFF0000)).hashCode)));

      expect(base, isNot(equals(const ColorStyle(outlineColor: .black, outlineThickness: 2))));
      expect(
        base.hashCode,
        isNot(equals(const ColorStyle(outlineColor: .black, outlineThickness: 2).hashCode)),
      );
    });

    test('default values are set correctly', () {
      expect(const ColorStyle().color, equals(FfiColor.black));
      expect(const ColorStyle().outlineColor, equals(FfiColor.transparent));
      expect(const ColorStyle().outlineThickness, equals(0));
    });
  });

  group('BlurStyle', () {
    test('equality and hashCode work correctly', () {
      const base = BlurStyle();
      expect(base, equals(const BlurStyle()));
      expect(base.hashCode, equals(const BlurStyle().hashCode));

      expect(base, isNot(equals(const BlurStyle(blur: 20))));
      expect(base.hashCode, isNot(equals(const BlurStyle(blur: 20).hashCode)));

      expect(base, isNot(equals(const BlurStyle(outlineColor: .black, outlineThickness: 2))));
      expect(
        base.hashCode,
        isNot(equals(const BlurStyle(outlineColor: .black, outlineThickness: 2).hashCode)),
      );
    });

    test('default values are set correctly', () {
      expect(const BlurStyle().blur, equals(10));
      expect(const BlurStyle().outlineColor, equals(FfiColor.transparent));
      expect(const BlurStyle().outlineThickness, equals(0));
    });
  });
}
