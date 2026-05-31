// Tests intentionally spell out default values for clarity.
// ignore_for_file: avoid_redundant_argument_values, avoid-passing-default-values

import 'dart:typed_data' show Float64x2, Float64x2List;

import 'package:frigatebird/src/model/draw_element.dart';
import 'package:frigatebird/src/model/ffi_color.dart';
import 'package:test/test.dart';

void main() {
  group('RectElement equality', () {
    test('two identical instances are equal', () {
      const a = RectElement(
        cornerRadius: 4,
        fillColor: FfiColor(0xFFAABBCC),
        height: 50,
        outlineColor: FfiColor(0xFF112233),
        outlineThickness: 3,
        rotation: 45,
        width: 100,
        x: 10,
        y: 20,
      );
      const b = RectElement(
        cornerRadius: 4,
        fillColor: FfiColor(0xFFAABBCC),
        height: 50,
        outlineColor: FfiColor(0xFF112233),
        outlineThickness: 3,
        rotation: 45,
        width: 100,
        x: 10,
        y: 20,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('different cornerRadius makes not equal', () {
      const a = RectElement(cornerRadius: 4, height: 50, width: 100, x: 10, y: 20);
      const b = RectElement(cornerRadius: 8, height: 50, width: 100, x: 10, y: 20);
      expect(a, isNot(equals(b)));
    });

    test('different x makes not equal', () {
      const a = RectElement(height: 50, width: 100, x: 10, y: 20);
      const b = RectElement(height: 50, width: 100, x: 11, y: 20);
      expect(a, isNot(equals(b)));
    });

    test('copyWith produces equal when no changes', () {
      const original = RectElement(height: 50, width: 100, x: 10, y: 20);
      final copy = original.copyWith();
      expect(copy, equals(original));
      expect(copy.hashCode, original.hashCode);
    });
  });

  group('OvalElement equality', () {
    test('two identical instances are equal', () {
      const a = OvalElement(
        fillColor: FfiColor(0xFF00FF00),
        height: 30,
        outlineColor: FfiColor(0xFF0000FF),
        outlineThickness: 2,
        rotation: 90,
        width: 60,
        x: 5,
        y: 10,
      );
      const b = OvalElement(
        fillColor: FfiColor(0xFF00FF00),
        height: 30,
        outlineColor: FfiColor(0xFF0000FF),
        outlineThickness: 2,
        rotation: 90,
        width: 60,
        x: 5,
        y: 10,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('different rotation makes not equal', () {
      const a = OvalElement(height: 30, rotation: 0, width: 60, x: 5, y: 10);
      const b = OvalElement(height: 30, rotation: 45, width: 60, x: 5, y: 10);
      expect(a, isNot(equals(b)));
    });

    test('copyWith produces equal when no changes', () {
      const original = OvalElement(height: 30, width: 60, x: 5, y: 10);
      final copy = original.copyWith();
      expect(copy, equals(original));
      expect(copy.hashCode, original.hashCode);
    });
  });

  group('TextElement equality', () {
    test('two identical instances are equal', () {
      const a = TextElement(
        fillColor: FfiColor(0xFFFF0000),
        fontId: 1,
        height: 24,
        rotation: 15,
        text: 'hello',
        x: 10,
        y: 20,
      );
      const b = TextElement(
        fillColor: FfiColor(0xFFFF0000),
        fontId: 1,
        height: 24,
        rotation: 15,
        text: 'hello',
        x: 10,
        y: 20,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('different text makes not equal', () {
      const a = TextElement(text: 'hello', x: 10, y: 20);
      const b = TextElement(text: 'world', x: 10, y: 20);
      expect(a, isNot(equals(b)));
    });

    test('different fontId makes not equal', () {
      const a = TextElement(fontId: 0, text: 'hi', x: 0, y: 0);
      const b = TextElement(fontId: 1, text: 'hi', x: 0, y: 0);
      expect(a, isNot(equals(b)));
    });

    test('copyWith produces equal when no changes', () {
      const original = TextElement(text: 'test', x: 5, y: 10);
      final copy = original.copyWith();
      expect(copy, equals(original));
      expect(copy.hashCode, original.hashCode);
    });
  });

  group('PolygonElement equality', () {
    test('two instances with same vertices are equal', () {
      final vertices = Float64x2List.fromList(
        [Float64x2(0, 0), Float64x2(10, 0), Float64x2(5, 10)],
      );
      final a = PolygonElement(height: 10, vertices: vertices, width: 10, x: 0, y: 0);
      final b = PolygonElement(height: 10, vertices: vertices, width: 10, x: 0, y: 0);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('different vertex content makes not equal', () {
      final triangle = Float64x2List.fromList([Float64x2(0, 0), Float64x2(10, 0), Float64x2(5, 10)]);
      final shifted = Float64x2List.fromList([Float64x2(0, 0), Float64x2(10, 0), Float64x2(5, 11)]);
      final a = PolygonElement(height: 10, vertices: triangle, width: 10, x: 0, y: 0);
      final b = PolygonElement(height: 10, vertices: shifted, width: 10, x: 0, y: 0);
      expect(a, isNot(equals(b)));
    });

    test('different vertex count makes not equal', () {
      final triangle = Float64x2List.fromList([Float64x2(0, 0), Float64x2(10, 0), Float64x2(5, 10)]);
      final quad = Float64x2List.fromList(
        [Float64x2(0, 0), Float64x2(10, 0), Float64x2(5, 10), Float64x2(7, 5)],
      );
      final a = PolygonElement(height: 10, vertices: triangle, width: 10, x: 0, y: 0);
      final b = PolygonElement(height: 10, vertices: quad, width: 10, x: 0, y: 0);
      expect(a, isNot(equals(b)));
    });
  });

  group('MaskRegionElement equality with non-const FfiColor', () {
    test('non-const fillColor compares by value not identity', () {
      // ignore: prefer_const_constructors, deliberately non-const to exercise value equality.
      final color = FfiColor(0xFF123456);
      final a = MaskRegionElement(fillColor: color, height: 50, width: 80, x: 10, y: 20);
      // ignore: prefer_const_constructors, deliberately non-const to exercise value equality.
      final b = MaskRegionElement(fillColor: FfiColor(0xFF123456), height: 50, width: 80, x: 10, y: 20);
      expect(a, equals(b), reason: 'value equality, not identity');
      expect(a.hashCode, b.hashCode);
    });
  });

  group('cross-type inequality', () {
    test('RectElement is not equal to OvalElement with same geometry', () {
      const rect = RectElement(height: 50, width: 100, x: 10, y: 20);
      const oval = OvalElement(height: 50, width: 100, x: 10, y: 20);
      // ignore: avoid-misused-test-matchers, deliberately testing cross-type inequality.
      expect(rect, isNot(equals(oval)));
    });
  });
}
