import 'package:frigatebird/frigatebird.dart';
import 'package:test/test.dart';

void main() {
  group('ResizeFilter', () {
    test('wire values match Rust enum', () {
      expect(ResizeFilter.nearest.wire, equals(0));
      expect(ResizeFilter.bilinear.wire, equals(1));
      expect(ResizeFilter.catmullRom.wire, equals(2));
      expect(ResizeFilter.lanczos3.wire, equals(3));
    });

    test('values list contains all four filters', () {
      expect(ResizeFilter.values, hasLength(4));
    });

    test('each wire value is unique', () {
      final wires = ResizeFilter.values.map((filter) => filter.wire).toSet();
      expect(wires, hasLength(4));
    });
  });
}
